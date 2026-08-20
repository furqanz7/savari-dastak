import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

enum DastakCourierAction: String {
    case accept
    case decline
    case startToStore
    case arriveAtStore
    case confirmPickup
    case startDelivery
    case completeDelivery
}

enum DastakParcelPartnerAction: String {
    case accept
    case decline
    case startToPickup
    case confirmPickup
    case startDelivery
    case completeDelivery
}

@MainActor
final class DastakDeliveryPartnerModel: ObservableObject {
    @Published private(set) var partner: DeliveryPartnerSnapshot?
    @Published private(set) var courierDispatch: CourierDispatchSnapshot?
    @Published private(set) var parcelDispatch: ParcelPartnerSnapshot?
    @Published private(set) var earnings: DastakEarningsSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyOperation: String?
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let partnerClient: any DeliveryPartnerClient
    private let courierClient: any CourierDispatchClient
    private let parcelClient: any ParcelDeliveryClient
    private let earningsClient: any DastakEarningsClient
    private var actionKeys: [String: IdempotencyKey] = [:]
    private var refreshQueued = false
    private var lastLocationPublishedAt: Date?

    init(
        partnerClient: any DeliveryPartnerClient,
        courierClient: any CourierDispatchClient,
        parcelClient: any ParcelDeliveryClient,
        earningsClient: any DastakEarningsClient
    ) {
        self.partnerClient = partnerClient
        self.courierClient = courierClient
        self.parcelClient = parcelClient
        self.earningsClient = earningsClient
    }

    convenience init(functions: any FunctionClient) {
        self.init(
            partnerClient: SupabaseDeliveryPartnerClient(functions: functions),
            courierClient: SupabaseCourierDispatchClient(functions: functions),
            parcelClient: SupabaseParcelDeliveryClient(functions: functions),
            earningsClient: SupabaseDastakEarningsClient(functions: functions)
        )
    }

    var isOnline: Bool {
        partner?.availability?.status == .online
    }

    var hasActiveJob: Bool {
        courierDispatch?.currentJob != nil || parcelDispatch?.currentJob != nil
    }

    var isBusy: Bool {
        busyOperation != nil
    }

    func bootstrap() async {
        await refresh()
        isLoading = false
    }

    func refresh() async {
        refreshQueued = true
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        while refreshQueued, !Task.isCancelled {
            refreshQueued = false
            do {
                async let partnerSnapshot = partnerClient.selfSnapshot(idempotencyKey: makeKey())
                async let courierSnapshot = courierClient.partnerSnapshot(idempotencyKey: makeKey())
                async let parcelSnapshot = parcelClient.partnerSnapshot(idempotencyKey: makeKey())
                async let earningsSnapshot = earningsClient.deliveryPartnerSnapshot(idempotencyKey: makeKey())
                let snapshots = try await (partnerSnapshot, courierSnapshot, parcelSnapshot, earningsSnapshot)
                partner = snapshots.0
                courierDispatch = snapshots.1
                parcelDispatch = snapshots.2
                earnings = snapshots.3
                errorMessage = nil
            } catch {
                errorMessage = message(for: error, fallback: "The delivery queue could not be refreshed.")
            }
        }
    }

    func setAvailability(online: Bool, location: DastakDeliveryLocation?) async {
        guard !isBusy else { return }
        guard !online || location != nil else {
            errorMessage = "Allow location access to go online."
            return
        }
        busyOperation = "availability"
        defer { busyOperation = nil }

        do {
            _ = try await partnerClient.setAvailability(
                online: online,
                location: online ? location?.point : nil,
                idempotencyKey: makeKey()
            )
            lastLocationPublishedAt = online ? .now : nil
            await refresh()
        } catch {
            errorMessage = message(for: error, fallback: "Availability could not be changed.")
        }
    }

    func publishLocation(_ location: DastakDeliveryLocation) async {
        guard isOnline, busyOperation == nil else { return }
        if let lastLocationPublishedAt,
           Date.now.timeIntervalSince(lastLocationPublishedAt) < 10 {
            return
        }
        do {
            _ = try await partnerClient.publishLocation(
                location: location.point,
                idempotencyKey: makeKey()
            )
            lastLocationPublishedAt = .now
        } catch let FunctionClientError.api(_, code, _) where code == "partner_offline" {
            lastLocationPublishedAt = nil
            await refresh()
        } catch {
            // Polling and the next location update recover transient publication failures.
        }
    }

    func perform(
        _ action: DastakCourierAction,
        assignment: CourierAssignment,
        verificationCode: String? = nil
    ) async {
        let identity = [
            "courier",
            action.rawValue,
            assignment.assignmentID.uuidString,
            assignment.orderStatus.rawValue,
            verificationCode ?? ""
        ].joined(separator: ":")
        guard busyOperation == nil else { return }
        busyOperation = identity
        let key = actionKey(for: identity)
        defer { busyOperation = nil }

        do {
            let snapshot: CourierDispatchSnapshot
            switch action {
            case .accept:
                snapshot = try await courierClient.acceptOffer(
                    assignmentID: assignment.assignmentID,
                    idempotencyKey: key
                )
            case .decline:
                snapshot = try await courierClient.declineOffer(
                    assignmentID: assignment.assignmentID,
                    reason: "Partner declined",
                    idempotencyKey: key
                )
            case .startToStore:
                snapshot = try await courierClient.startToStore(
                    assignmentID: assignment.assignmentID,
                    idempotencyKey: key
                )
            case .arriveAtStore:
                snapshot = try await courierClient.arriveAtStore(
                    assignmentID: assignment.assignmentID,
                    idempotencyKey: key
                )
            case .confirmPickup:
                guard let verificationCode else { return }
                snapshot = try await courierClient.confirmPickup(
                    assignmentID: assignment.assignmentID,
                    verificationCode: verificationCode,
                    idempotencyKey: key
                )
            case .startDelivery:
                snapshot = try await courierClient.startDelivery(
                    assignmentID: assignment.assignmentID,
                    idempotencyKey: key
                )
            case .completeDelivery:
                guard let verificationCode else { return }
                snapshot = try await courierClient.completeDelivery(
                    assignmentID: assignment.assignmentID,
                    verificationCode: verificationCode,
                    idempotencyKey: key
                )
            }
            courierDispatch = snapshot
            actionKeys[identity] = nil
            errorMessage = nil
            noticeMessage = successMessage(for: action)
            await refresh()
        } catch {
            errorMessage = message(for: error, fallback: "The delivery could not be updated.")
        }
    }

    func perform(
        _ action: DastakParcelPartnerAction,
        assignment: ParcelAssignment,
        verificationCode: String? = nil
    ) async {
        let identity = [
            "parcel",
            action.rawValue,
            assignment.assignmentID.uuidString,
            assignment.parcel.status.rawValue,
            verificationCode ?? ""
        ].joined(separator: ":")
        guard busyOperation == nil else { return }
        busyOperation = identity
        let key = actionKey(for: identity)
        defer { busyOperation = nil }

        do {
            let snapshot: ParcelPartnerSnapshot
            switch action {
            case .accept:
                snapshot = try await parcelClient.acknowledgeAssignment(
                    assignmentID: assignment.assignmentID,
                    idempotencyKey: key
                )
            case .decline:
                snapshot = try await parcelClient.declineAssignment(
                    assignmentID: assignment.assignmentID,
                    reason: "Partner declined",
                    idempotencyKey: key
                )
            case .startToPickup:
                snapshot = try await parcelClient.startToPickup(
                    assignmentID: assignment.assignmentID,
                    idempotencyKey: key
                )
            case .confirmPickup:
                guard let verificationCode else { return }
                snapshot = try await parcelClient.confirmPickup(
                    assignmentID: assignment.assignmentID,
                    verificationCode: verificationCode,
                    idempotencyKey: key
                )
            case .startDelivery:
                snapshot = try await parcelClient.startDelivery(
                    assignmentID: assignment.assignmentID,
                    idempotencyKey: key
                )
            case .completeDelivery:
                guard let verificationCode else { return }
                snapshot = try await parcelClient.completeDelivery(
                    assignmentID: assignment.assignmentID,
                    verificationCode: verificationCode,
                    idempotencyKey: key
                )
            }
            parcelDispatch = snapshot
            actionKeys[identity] = nil
            errorMessage = nil
            noticeMessage = successMessage(for: action)
            await refresh()
        } catch {
            errorMessage = message(for: error, fallback: "The parcel delivery could not be updated.")
        }
    }

    private func actionKey(for identity: String) -> IdempotencyKey {
        if let key = actionKeys[identity] {
            return key
        }
        let key = makeKey()
        actionKeys[identity] = key
        return key
    }

    private func makeKey() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }

    private func message(for error: Error, fallback: String) -> String {
        guard case let FunctionClientError.api(_, _, message) = error else {
            return fallback
        }
        return message
    }

    private func successMessage(for action: DastakCourierAction) -> String? {
        switch action {
        case .confirmPickup: "Pickup verified. The order is now in your care."
        case .completeDelivery: "Delivery verified and completed."
        default: nil
        }
    }

    private func successMessage(for action: DastakParcelPartnerAction) -> String? {
        switch action {
        case .confirmPickup: "Pickup verified. The parcel is now in your care."
        case .completeDelivery: "Parcel delivery verified and completed."
        default: nil
        }
    }
}
