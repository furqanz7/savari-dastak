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
    @Published private(set) var v1Dispatch: DastakV1DeliveryDispatchSnapshot?
    @Published private(set) var earnings: DastakEarningsSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshFailure: String?
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var busyOperation: String?
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let partnerClient: any DeliveryPartnerClient
    private let courierClient: any CourierDispatchClient
    private let parcelClient: any ParcelDeliveryClient
    private let v1Client: any DastakV1DeliveryClient
    private let earningsClient: any DastakEarningsClient
    private var actionKeys: [String: IdempotencyKey] = [:]
    private var refreshQueued = false
    private var lastLocationPublishedAt: Date?

    init(
        partnerClient: any DeliveryPartnerClient,
        courierClient: any CourierDispatchClient,
        parcelClient: any ParcelDeliveryClient,
        v1Client: any DastakV1DeliveryClient,
        earningsClient: any DastakEarningsClient
    ) {
        self.partnerClient = partnerClient
        self.courierClient = courierClient
        self.parcelClient = parcelClient
        self.v1Client = v1Client
        self.earningsClient = earningsClient
    }

    convenience init(functions: any FunctionClient) {
        self.init(
            partnerClient: SupabaseDeliveryPartnerClient(functions: functions),
            courierClient: SupabaseCourierDispatchClient(functions: functions),
            parcelClient: SupabaseParcelDeliveryClient(functions: functions),
            v1Client: SupabaseDastakV1DeliveryClient(functions: functions),
            earningsClient: SupabaseDastakEarningsClient(functions: functions)
        )
    }

    var isOnline: Bool {
        partner?.availability?.status == .online
    }

    var hasActiveJob: Bool {
        courierDispatch?.currentJob != nil || parcelDispatch?.currentJob != nil ||
            v1Dispatch?.currentMission != nil
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
            // An earnings or legacy-service outage must not hide a new V1 job.
            async let partnerSnapshot = try? partnerClient.selfSnapshot(idempotencyKey: makeKey())
            async let courierSnapshot = try? courierClient.partnerSnapshot(idempotencyKey: makeKey())
            async let parcelSnapshot = try? parcelClient.partnerSnapshot(idempotencyKey: makeKey())
            async let v1Snapshot = try? v1Client.snapshot(idempotencyKey: makeKey())
            async let earningsSnapshot = try? earningsClient.deliveryPartnerSnapshot(idempotencyKey: makeKey())
            let snapshots = await (partnerSnapshot, courierSnapshot, parcelSnapshot, v1Snapshot, earningsSnapshot)
            guard !Task.isCancelled else { return }
            if let value = snapshots.0 { partner = value }
            if let value = snapshots.1 { courierDispatch = value }
            if let value = snapshots.2 { parcelDispatch = value }
            if let value = snapshots.3 { v1Dispatch = value }
            if let value = snapshots.4 { earnings = value }
            if snapshots.0 != nil, snapshots.1 != nil, snapshots.2 != nil, snapshots.3 != nil, snapshots.4 != nil {
                refreshFailure = nil
                lastRefreshedAt = .now
            } else {
                refreshFailure = "Some updates are unavailable. Last-known details are kept while we reconnect. Pull to refresh."
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

    func respondToV1Offer(_ offer: DastakV1RiderOffer, accept: Bool) async {
        guard DastakDeliveryPresentation.secondsRemaining(until: offer.respondBy, now: .now) > 0 else {
            await refresh()
            return
        }
        let identity = "v1-offer:\(accept):\(offer.id)"
        guard busyOperation == nil else { return }
        busyOperation = identity
        let key = actionKey(for: identity)
        defer { busyOperation = nil }
        do {
            v1Dispatch = accept
                ? try await v1Client.accept(offerID: offer.id, idempotencyKey: key)
                : try await v1Client.decline(
                    offerID: offer.id,
                    reason: "Partner declined",
                    idempotencyKey: key
                )
            actionKeys[identity] = nil
            errorMessage = nil
            if accept { noticeMessage = "Delivery accepted. Continue to your pickup stops." }
        } catch {
            errorMessage = message(for: error, fallback: "The delivery offer could not be updated.")
        }
    }

    func advanceV1Mission(
        _ operation: String,
        mission: DastakV1DeliveryMissionSnapshot,
        stopID: UUID? = nil,
        packageCount: Int? = nil,
        verificationCode: String? = nil,
        objectPath: String? = nil,
        reason: String? = nil
    ) async {
        let identity = ["v1", operation, mission.id.uuidString, stopID?.uuidString ?? "", verificationCode ?? ""]
            .joined(separator: ":")
        guard busyOperation == nil else { return }
        busyOperation = identity
        let key = actionKey(for: identity)
        defer { busyOperation = nil }
        do {
            v1Dispatch = try await v1Client.advance(
                operation: operation,
                missionID: mission.id,
                stopID: stopID,
                accountedPackageCount: packageCount,
                verificationCode: verificationCode,
                objectPath: objectPath,
                reason: reason,
                idempotencyKey: key
            )
            actionKeys[identity] = nil
            errorMessage = nil
            if operation == "v1VerifyPickup" {
                noticeMessage = "Pickup verified. The declared packages are now in your custody."
            } else if operation == "v1VerifyCustomerPIN" {
                noticeMessage = "Customer PIN verified. Take the package photo next."
            } else if operation == "v1CompleteDelivery" || operation == "v1VerifyDelivery" {
                noticeMessage = "Delivery verified and completed."
            }
        } catch {
            errorMessage = message(for: error, fallback: "The Dastak mission could not be updated.")
            if case let FunctionClientError.api(status, _, _) = error,
               (400..<500).contains(status), status != 408, status != 429 {
                // Definitive rejections are safe to retry after location/state
                // changes. Keep the same key only for uncertain network outcomes.
                actionKeys[identity] = nil
                await refresh()
            }
        }
    }

    func recordV1Collection(
        mission: DastakV1DeliveryMissionSnapshot,
        outcome: DastakV1CollectionOutcome,
        method: DastakV1CollectionMethod,
        reference: String?,
        failureReason: String?
    ) async {
        let identity = "v1-collection:\(mission.id):\(outcome.rawValue):\(method.rawValue)"
        guard busyOperation == nil else { return }
        busyOperation = identity
        let key = actionKey(for: identity)
        defer { busyOperation = nil }
        do {
            let normalizedReference = reference?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedFailureReason = failureReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            v1Dispatch = try await v1Client.recordCollection(
                missionID: mission.id,
                outcome: outcome,
                method: method,
                reference: normalizedReference?.isEmpty == false ? normalizedReference : nil,
                failureReason: normalizedFailureReason?.isEmpty == false ? normalizedFailureReason : nil,
                expectedMissionVersion: mission.version,
                idempotencyKey: key
            )
            actionKeys[identity] = nil
            errorMessage = nil
            noticeMessage = outcome == .collected
                ? "Payment collected. You can now complete delivery."
                : "Failed collection recorded. Keep the packages secure and retry before delivery."
        } catch {
            errorMessage = message(for: error, fallback: "The doorstep collection result could not be recorded.")
            if case let FunctionClientError.api(status, _, _) = error,
               (400..<500).contains(status), status != 408, status != 429 {
                actionKeys[identity] = nil
                await refresh()
            }
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
