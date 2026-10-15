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
    @Published private(set) var v1Current = false
    let operations: DastakDeliveryOperations?
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
    private var fullRefreshQueued = false
    private var merchantOrderRefreshQueued = false
    private var parcelRefreshQueued = false
    private var lastLocationPublishedAt: Date?
    private var publishingAvailability = false
    @Published private(set) var criticalReadRunning = false
    private var criticalReadID = UUID()
    private var criticalRequest: Task<DastakV1DeliveryDispatchSnapshot?, Never>?
    private var lastMerchantEventAt: Date?

    init(
        partnerClient: any DeliveryPartnerClient,
        courierClient: any CourierDispatchClient,
        parcelClient: any ParcelDeliveryClient,
        v1Client: any DastakV1DeliveryClient,
        earningsClient: any DastakEarningsClient,
        operations: DastakDeliveryOperations? = nil
    ) {
        self.partnerClient = partnerClient
        self.courierClient = courierClient
        self.parcelClient = parcelClient
        self.v1Client = v1Client
        self.earningsClient = earningsClient
        self.operations = operations
    }

    convenience init(functions: any FunctionClient, operations: DastakDeliveryOperations? = nil,
                     requestTimeout: Duration = .seconds(12)) {
        let functions = DastakDeliveryFunctionClient(base: functions, timeout: requestTimeout)
        self.init(
            partnerClient: SupabaseDeliveryPartnerClient(functions: functions),
            courierClient: SupabaseCourierDispatchClient(functions: functions),
            parcelClient: SupabaseParcelDeliveryClient(functions: functions),
            v1Client: SupabaseDastakV1DeliveryClient(functions: functions),
            earningsClient: SupabaseDastakEarningsClient(functions: functions), operations: operations
        )
    }

    var isOnline: Bool {
        isOnline(at: .now)
    }

    func isOnline(at date: Date) -> Bool {
        guard partner?.availability?.status == .online,
              let until = partner?.availability?.availableUntil else { return false }
        return DastakDeliveryPresentation.secondsRemaining(until: until, now: date) > 0
    }

    var hasActiveJob: Bool {
        courierDispatch?.currentJob != nil || parcelDispatch?.currentJob != nil ||
            v1Dispatch?.currentMission != nil || v1Dispatch?.returnMission != nil || operations?.returnMission != nil
    }

    var isBusy: Bool {
        busyOperation != nil || operations?.blocksActions == true
    }

    var canShowEmptyDesk: Bool {
        !isLoading && refreshFailure == nil && v1Current && partner != nil && courierDispatch != nil && parcelDispatch != nil
    }

    func bootstrap() async {
        await operations?.reconcilePending()
        await refresh()
        isLoading = false
    }

    func refresh() async {
        fullRefreshQueued = true
        await drainRefreshQueue()
    }

    /// Realtime order events arrive much more frequently than the recovery poll,
    /// especially while a rider is publishing live location. Refresh only the
    /// projections affected by the event instead of invoking every partner
    /// service for every GPS sample.
    func refreshOrderChange(_ entityKind: OrderChangeEvent.EntityKind) async {
        if entityKind == .merchantOrder, hasActiveJob {
            // GPS events can arrive continuously. One active-lane read is enough
            // for a burst, without refreshing earnings or legacy dispatch.
            guard lastMerchantEventAt.map({ Date.now.timeIntervalSince($0) >= 2 }) ?? true else { return }
            lastMerchantEventAt = .now
            await refreshActiveDelivery()
            return
        }
        switch entityKind {
        case .merchantOrder:
            merchantOrderRefreshQueued = true
        case .parcel:
            parcelRefreshQueued = true
        }
        await drainRefreshQueue()
    }

    private func drainRefreshQueue() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        while (fullRefreshQueued || merchantOrderRefreshQueued || parcelRefreshQueued),
              !Task.isCancelled {
            if fullRefreshQueued {
                fullRefreshQueued = false
                merchantOrderRefreshQueued = false
                parcelRefreshQueued = false
                await performFullRefresh()
                continue
            }

            let refreshMerchantOrders = merchantOrderRefreshQueued
            let refreshParcels = parcelRefreshQueued
            merchantOrderRefreshQueued = false
            parcelRefreshQueued = false

            var succeeded = true
            if refreshMerchantOrders {
                succeeded = await performMerchantOrderRefresh() && succeeded
            }
            if refreshParcels {
                succeeded = await performParcelRefresh() && succeeded
            }
            recordRefreshResult(succeeded: succeeded)
        }
    }

    private func performFullRefresh() async {
        let operationsRevision = operations?.readRevision
        // An earnings or legacy-service outage must not hide a new V1 job.
        async let partnerSnapshot = try? partnerClient.selfSnapshot(idempotencyKey: makeKey())
        async let courierSnapshot = try? courierClient.partnerSnapshot(idempotencyKey: makeKey())
        async let parcelSnapshot = try? parcelClient.partnerSnapshot(idempotencyKey: makeKey())
        async let v1Snapshot = try? v1Client.snapshot(idempotencyKey: makeKey())
        async let earningsSnapshot = try? earningsClient.deliveryPartnerSnapshot(idempotencyKey: makeKey())
        let criticalSnapshot = await v1Snapshot
        if !Task.isCancelled, operationsRevision == operations?.readRevision, operations?.busy != true {
            if let value = criticalSnapshot { adoptV1(value); isLoading = false }
            else { v1Current = false; operations?.invalidate() }
        }
        let snapshots = await (partnerSnapshot, courierSnapshot, parcelSnapshot, earningsSnapshot)
        guard !Task.isCancelled else { return }
        if let value = snapshots.0 { partner = value }
        if let value = snapshots.1 { courierDispatch = value }
        if let value = snapshots.2 { parcelDispatch = value }
        if operationsRevision != operations?.readRevision {
            // A read started before an action cannot replace its receipt. Queue
            // another read instead of leaving every delivery control stale.
            if operations?.busy != true { await refreshActiveDelivery() }
        }
        if let value = snapshots.3 { earnings = value }
        recordRefreshResult(
            succeeded: snapshots.0 != nil && snapshots.1 != nil && snapshots.2 != nil &&
                criticalSnapshot != nil && v1Current && snapshots.3 != nil
        )
    }

    /// Actions and active-work polling never queue behind a full desk refresh.
    func refreshActiveDelivery(force: Bool = false) async {
        guard !criticalReadRunning || force else { return }
        if force { criticalRequest?.cancel() }
        let requestID = UUID()
        criticalReadID = requestID
        criticalReadRunning = true
        defer {
            if criticalReadID == requestID { criticalReadRunning = false; criticalRequest = nil }
        }
        if !Task.isCancelled {
            let revision = operations?.readRevision
            let key = makeKey()
            let request = Task { [v1Client] in try? await v1Client.snapshot(idempotencyKey: key) }
            criticalRequest = request
            let value = await request.value
            guard !Task.isCancelled, criticalReadID == requestID else { return }
            guard revision == operations?.readRevision, operations?.busy != true else { return }
            if let value {
                await operations?.reconcileObserved(value)
                guard criticalReadID == requestID, !Task.isCancelled else { return }
                adoptV1(value)
                if v1Current { lastRefreshedAt = .now; refreshFailure = nil }
            } else {
                v1Current = false; operations?.invalidate()
                recordRefreshResult(succeeded: false)
            }
        }
    }

    /// User refresh has its own bounded read and cannot be trapped behind a
    /// stale queue. Read proof first; replay only if that did not resolve work.
    func recoverDesk(force: Bool = true) async {
        // Routine polling/foreground events must not cancel a slower read on
        // every tick. Explicit user refresh alone replaces a stalled read.
        guard force || !criticalReadRunning else { return }
        await refreshActiveDelivery(force: force)
        guard !Task.isCancelled else { return }
        let revision = operations?.readRevision
        await operations?.recoverAutomatically()
        if revision != operations?.readRevision { await refreshActiveDelivery() }
    }

    func actionFinished() async {
        if let snapshot = operations?.takeConfirmedSnapshot(),
           snapshot.deliveryLaneCurrent, snapshot.returnLaneCurrent {
            // Successful mutations already return the authoritative dispatch.
            // Do not add another round trip before the next rider action.
            adoptV1(snapshot)
            return
        }
        await refreshActiveDelivery()
    }

    func applyConfirmedAction(_ snapshot: DastakV1DeliveryDispatchSnapshot?) {
        guard let snapshot else { return }
        adoptV1(snapshot)
    }

    private func performMerchantOrderRefresh() async -> Bool {
        let operationsRevision = operations?.readRevision
        async let courierSnapshot = try? courierClient.partnerSnapshot(idempotencyKey: makeKey())
        async let v1Snapshot = try? v1Client.snapshot(idempotencyKey: makeKey())
        let snapshots = await (courierSnapshot, v1Snapshot)
        guard !Task.isCancelled else { return false }
        if let value = snapshots.0 { courierDispatch = value }
        if operationsRevision == operations?.readRevision && operations?.busy != true {
            if let value = snapshots.1 { adoptV1(value) } else { v1Current = false; operations?.invalidate() }
        } else if operations?.busy != true { merchantOrderRefreshQueued = true }
        return snapshots.0 != nil && snapshots.1 != nil && v1Current
    }

    private func performParcelRefresh() async -> Bool {
        let snapshot = try? await parcelClient.partnerSnapshot(idempotencyKey: makeKey())
        guard !Task.isCancelled else { return false }
        if let snapshot { parcelDispatch = snapshot }
        return snapshot != nil
    }

    private func recordRefreshResult(succeeded: Bool) {
        if succeeded {
            refreshFailure = nil
            lastRefreshedAt = .now
        } else {
            refreshFailure = "Some updates are unavailable. Last-known details are kept while Dastak reconnects automatically."
        }
    }

    private func adoptV1(_ value: DastakV1DeliveryDispatchSnapshot) {
        var merged = value
        merged.currentMission = value.currentMission?.retainingConfirmedProgress(from: v1Dispatch?.currentMission)
        if !value.deliveryLaneCurrent { merged.offer = v1Dispatch?.offer; merged.currentMission = v1Dispatch?.currentMission }
        if let current = v1Dispatch?.currentMission, let incoming = merged.currentMission,
           incoming.id == current.id, incoming.version < current.version {
            // A tracking response may arrive while a desk read is in flight.
            // An older read must never take the rider back to pickup.
            merged.currentMission = current
        }
        if !value.returnLaneCurrent { merged.returnMission = v1Dispatch?.returnMission }
        if !value.completedLaneCurrent { merged.completedMission = v1Dispatch?.completedMission }
        v1Current = value.deliveryLaneCurrent && value.returnLaneCurrent
        operations?.adopt(merged)
        v1Dispatch = merged
    }

    /// GPS and heartbeat reconciliation belong to the authenticated root. Keep
    /// the action desk on that same mission, without changing assignments from
    /// an incomplete tracking envelope or overriding an in-flight command.
    func adoptTrackedMission(_ mission: DastakV1DeliveryMissionSnapshot?) {
        guard let mission, let current = v1Dispatch?.currentMission,
              mission.id == current.id, mission.version >= current.version,
              v1Current, operations?.blocksActions != true,
              var snapshot = v1Dispatch, snapshot.returnMission == nil,
              mission != current else { return }
        snapshot.currentMission = mission
        adoptV1(snapshot)
    }

    func setAvailability(online: Bool, location: DastakDeliveryLocation?) async {
        guard !isBusy else { return }
        guard !online || location != nil else {
            errorMessage = "Allow location access to go online."
            return
        }
        let operationID = "availability:\(UUID())"
        busyOperation = operationID
        defer { if busyOperation == operationID { busyOperation = nil } }

        do {
            _ = try await partnerClient.setAvailability(
                online: online,
                location: online ? location?.point : nil,
                idempotencyKey: makeKey()
            )
            lastLocationPublishedAt = online ? .now : nil
            // Background desk reads must not retain the availability action's
            // lock. Each read has its own loading/failure state.
            busyOperation = nil
            await refresh()
        } catch {
            errorMessage = message(for: error, fallback: "Availability could not be changed.")
        }
    }

    func publishLocation(_ location: DastakDeliveryLocation) async {
        guard isOnline, !publishingAvailability else { return }
        if let lastLocationPublishedAt,
           Date.now.timeIntervalSince(lastLocationPublishedAt) < 10 {
            return
        }
        publishingAvailability = true
        defer { publishingAvailability = false }
        do {
            if hasActiveJob, let until = partner?.availability?.availableUntil,
               DastakDeliveryPresentation.secondsRemaining(until: until, now: .now) < 120 {
                // Renew only an existing online session while actively working.
                // A previously offline rider is never switched online implicitly.
                _ = try await partnerClient.setAvailability(online: true, location: location.point, idempotencyKey: makeKey())
                if let value = try? await partnerClient.selfSnapshot(idempotencyKey: makeKey()) { partner = value }
            } else {
                _ = try await partnerClient.publishLocation(location: location.point, idempotencyKey: makeKey())
            }
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
        guard !isBusy, action != .accept || !hasActiveJob else { return }
        if let operations {
            guard (courierDispatch?.currentJob ?? courierDispatch?.offer) == assignment else { return }
            if [.accept, .decline].contains(action), DastakDeliveryPresentation.secondsRemaining(until: assignment.respondBy, now: .now) == 0 { await refresh(); return }
            let names: [DastakCourierAction: String] = [.accept: "acceptOffer", .decline: "declineOffer", .startToStore: "startToStore", .arriveAtStore: "arriveAtStore", .confirmPickup: "confirmPickup", .startDelivery: "startDelivery", .completeDelivery: "completeDelivery"]
            await operations.submitAssignment(parcel: false, action: names[action]!, assignmentID: assignment.assignmentID, code: verificationCode)
            await refresh(); return
        }
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
        guard v1Current, !hasActiveJob, !isBusy else { return }
        guard DastakDeliveryPresentation.secondsRemaining(until: offer.respondBy, now: .now) > 0 else {
            await refresh()
            return
        }
        if let operations {
            await operations.submitOffer(offer, accept: accept)
            await actionFinished()
            return
        }
        let identity = "v1-offer:\(accept):\(offer.id)"
        guard busyOperation == nil else { return }
        busyOperation = identity
        let key = actionKey(for: identity)
        defer { busyOperation = nil }
        do {
            let response = accept
                ? try await v1Client.accept(offerID: offer.id, idempotencyKey: key)
                : try await v1Client.decline(
                    offerID: offer.id,
                    reason: "Partner declined",
                    idempotencyKey: key
                )
            adoptV1(response)
            actionKeys[identity] = nil
            errorMessage = nil
            if accept { noticeMessage = "Delivery accepted. Continue to your pickup stops." }
        } catch {
            errorMessage = message(for: error, fallback: "The delivery offer could not be updated.")
        }
    }

    /// A stale screen offers a bounded recheck, not a permanently disabled
    /// button. Never send custody/money commands from an unverified snapshot.
    private func prepareV1Action(for shown: DastakV1DeliveryMissionSnapshot) async -> DastakV1DeliveryMissionSnapshot? {
        guard !isBusy else { return nil }
        if !v1Current || operations?.normalFresh == false {
            let identity = "checking-delivery:\(UUID())"
            busyOperation = identity
            await refreshActiveDelivery(force: true)
            if busyOperation == identity { busyOperation = nil }
        }
        guard !Task.isCancelled else { return nil }
        guard !isBusy, v1Current else {
            errorMessage = "The delivery could not be checked. Your action was not sent. Tap again to reconnect, or use Refresh."
            return nil
        }
        guard v1Dispatch?.returnMission == nil, operations?.returnMission == nil,
              let current = v1Dispatch?.currentMission, current.id == shown.id,
              current.status == shown.status else {
            noticeMessage = "This delivery changed. Review the latest step before continuing."
            return nil
        }
        return current
    }

    func submitV1Evidence(mission: DastakV1DeliveryMissionSnapshot, data: Data, contentType: String) async {
        guard let mission = await prepareV1Action(for: mission), let operations else { return }
        await operations.submitDelivery(.deliveryEvidence, mission: mission, photo: data, contentType: contentType)
        await actionFinished()
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
        guard let mission = await prepareV1Action(for: mission) else { return }
        if let operations {
            guard let action = DastakDeliveryCommand.Operation(rawValue: operation) else { return }
            await operations.submitDelivery(action, mission: mission, stopID: stopID, packageCount: packageCount,
                code: verificationCode, reason: reason)
            await actionFinished()
            return
        }
        let identity = ["v1", operation, mission.id.uuidString, stopID?.uuidString ?? "", verificationCode ?? ""]
            .joined(separator: ":")
        guard busyOperation == nil else { return }
        busyOperation = identity
        let key = actionKey(for: identity)
        defer { busyOperation = nil }
        do {
            let response = try await v1Client.advance(
                operation: operation,
                missionID: mission.id,
                stopID: stopID,
                accountedPackageCount: packageCount,
                verificationCode: verificationCode,
                objectPath: objectPath,
                reason: reason,
                idempotencyKey: key
            )
            adoptV1(response)
            actionKeys[identity] = nil
            errorMessage = nil
            if operation == "v1VerifyPickup" {
                noticeMessage = "Pickup verified. The declared packages are now in your custody."
            } else if operation == "v1ArriveAtCustomer" {
                noticeMessage = "Arrival confirmed. Ask the customer for the delivery PIN."
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
        guard let mission = await prepareV1Action(for: mission) else { return }
        if let operations {
            let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines)
            let failureReason = failureReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            await operations.submitDelivery(.collection, mission: mission, outcome: outcome, method: method,
                reference: reference?.isEmpty == false ? reference : nil,
                failureReason: failureReason?.isEmpty == false ? failureReason : nil)
            await actionFinished()
            return
        }
        let identity = "v1-collection:\(mission.id):\(outcome.rawValue):\(method.rawValue)"
        guard busyOperation == nil else { return }
        busyOperation = identity
        let key = actionKey(for: identity)
        defer { busyOperation = nil }
        do {
            let normalizedReference = reference?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedFailureReason = failureReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await v1Client.recordCollection(
                missionID: mission.id,
                outcome: outcome,
                method: method,
                reference: normalizedReference?.isEmpty == false ? normalizedReference : nil,
                failureReason: normalizedFailureReason?.isEmpty == false ? normalizedFailureReason : nil,
                expectedMissionVersion: mission.version,
                idempotencyKey: key
            )
            adoptV1(response)
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
        guard !isBusy, action != .accept || !hasActiveJob else { return }
        if let operations {
            guard (parcelDispatch?.currentJob ?? parcelDispatch?.offer) == assignment else { return }
            if [.accept, .decline].contains(action), DastakDeliveryPresentation.secondsRemaining(until: assignment.respondBy, now: .now) == 0 { await refresh(); return }
            let names: [DastakParcelPartnerAction: String] = [.accept: "acknowledgeAssignment", .decline: "declineAssignment", .startToPickup: "startToPickup", .confirmPickup: "confirmPickup", .startDelivery: "startDelivery", .completeDelivery: "completeDelivery"]
            await operations.submitAssignment(parcel: true, action: names[action]!, assignmentID: assignment.assignmentID, code: verificationCode)
            await refresh(); return
        }
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
