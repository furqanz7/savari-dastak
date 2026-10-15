import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

@MainActor
final class DastakDeliveryOperations: ObservableObject {
    @Published private(set) var returnMission: DastakV1ReturnMission?
    @Published private(set) var returnsCurrent = false
    @Published private(set) var readAt: Date?
    @Published private(set) var pending: DastakDeliveryCommand?
    @Published private(set) var restored = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var heartbeatFailure: String?
    @Published private(set) var confirmedSnapshot: DastakV1DeliveryDispatchSnapshot?
    @Published private(set) var history: [DastakDeliveryWorkHistory.Item] = []
    @Published private(set) var historyCurrent = false
    @Published private(set) var historyLoading = false
    private let services: MarketplaceAuthenticatedServices
    private let functions: any FunctionClient
    private let requestTimeout: Duration
    private let storage: any DastakDeliveryCommandStorage
    private var accountID: UUID?
    private var normalSnapshot: DastakV1DeliveryDispatchSnapshot?
    private var normalReadAt: Date?
    private let heartbeatMonitor: DastakDeliveryHeartbeat
    private(set) var readRevision = UUID()
    private var lastAutomaticRecovery: Date?
    var blocksActions: Bool { !restored || busy || pending != nil }

    func takeConfirmedSnapshot() -> DastakV1DeliveryDispatchSnapshot? {
        let snapshot = confirmedSnapshot
        confirmedSnapshot = nil
        return snapshot
    }

    init(services: MarketplaceAuthenticatedServices, storage: any DastakDeliveryCommandStorage = DastakDeliveryCommandFileStore.shared,
         requestTimeout: Duration = .seconds(12)) {
        self.services = services; self.storage = storage
        self.requestTimeout = requestTimeout
        functions = DastakDeliveryFunctionClient(base: services.functions, timeout: requestTimeout)
        heartbeatMonitor = DastakDeliveryHeartbeat(functions: functions)
    }
    private func currentAccountID() async throws -> UUID {
        try await DastakDeliveryDeadline.run(after: requestTimeout) { [services] in try await services.accountID() }
    }
    func restore() async {
        guard !restored, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let id = try await currentAccountID()
            pending = try await storage.load(id); accountID = id; restored = true
            if pending != nil { message = "A saved delivery action needs recovery. Retry the original action before starting another." }
        } catch { message = "Delivery recovery storage could not be read. Actions stay locked; no saved record was removed." }
    }
    func adopt(_ snapshot: DastakV1DeliveryDispatchSnapshot, authoritative: Bool = false) {
        guard !busy || authoritative else { return }
        if snapshot.deliveryLaneCurrent && snapshot.returnLaneCurrent {
            normalSnapshot = snapshot; normalReadAt = .now
        } else { normalReadAt = nil }
        returnsCurrent = snapshot.returnLaneCurrent
        if returnsCurrent {
            if let value = snapshot.returnMission, let current = returnMission,
               value.id == current.id, value.version < current.version { return }
            returnMission = snapshot.returnMission; readAt = .now
        }
    }
    func adoptTracked(_ mission: DastakV1ReturnMission?) {
        guard let mission, mission.isValid, let current = returnMission,
              mission.id == current.id, mission.version >= current.version else { return }
        if mission.version == current.version {
            // Evidence and individual stops can advance without incrementing the mission version.
            guard mission.status == current.status,
                  mission.stops.map(\.status) == current.stops.map(\.status),
                  Set(mission.evidence.map(\.id)).isSuperset(of: Set(current.evidence.map(\.id))) else { return }
        }
        returnMission = mission; returnsCurrent = true; readAt = .now
    }
    func invalidate() { returnsCurrent = false; normalReadAt = nil }

    /// A fresh dispatch can prove that an uncertain command already took
    /// effect. Do not keep replaying a lost/malformed receipt after arrival,
    /// PIN, photo, pickup or payment is independently confirmed by the server.
    func reconcileObserved(_ snapshot: DastakV1DeliveryDispatchSnapshot) async {
        guard restored, !busy, let command = pending, !command.operation.isAssignment,
              !command.operation.isOffer, let accountID else { return }
        busy = true; defer { busy = false }
        do {
            let delivered = snapshot.completedLaneCurrent && snapshot.completedMission?.id == command.missionID
                && snapshot.completedMission?.status == "DELIVERED" && !command.operation.isReturn
            guard try await currentAccountID() == accountID,
                  try await storage.load(accountID) == command else { return }
            let confirmed = delivered ? true : await acknowledges(command, snapshot: snapshot)
            guard confirmed,
                  try await currentAccountID() == accountID,
                  try await storage.load(accountID) == command else { return }
            try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
            pending = nil; readRevision = UUID(); message = nil
            adopt(snapshot, authoritative: true)
        } catch { /* Preserve the durable action if independent proof fails. */ }
    }
    func fresh(at date: Date = .now) -> Bool {
        returnsCurrent && readAt.map { (0..<60).contains(date.timeIntervalSince($0)) } == true
    }

    func canReturn(_ operation: DastakDeliveryCommand.Operation, mission: DastakV1ReturnMission,
        stopID: UUID? = nil, confirmed: Bool = false, code: String? = nil, now: Date = .now) -> Bool {
        guard !blocksActions, fresh(at: now), returnMission == mission, mission.isValid, mission.completedAt == nil else { return false }
        switch operation {
        case .arriveCustomer:
            return mission.status == "ASSIGNED" && mission.canArriveCustomer && mission.customerArrival?.canArrive(at: now) == true
        case .evidence:
            return mission.status == "AT_CUSTOMER" && mission.canCaptureEvidence && mission.pickupVerification.status == "ACTIVE"
        case .pickup:
            return mission.status == "AT_CUSTOMER" && mission.canVerifyPickup && mission.pickupVerification.status == "ACTIVE"
                && !mission.evidence.isEmpty && confirmed && Self.validCode(code)
        case .arriveStop, .receipt:
            guard mission.status == "RETURNING_TO_MERCHANTS", mission.canCompleteReturnStops,
                  mission.pickupVerification.status == "CONSUMED", mission.pickupCompletedAt != nil,
                  let next = mission.stops.sorted(by: { $0.sequence < $1.sequence }).first(where: { $0.status != "COMPLETED" }),
                  next.id == stopID else { return false }
            return operation == .arriveStop
                ? next.status == "PENDING" && next.canArrive == true && next.arrival?.canArrive(at: now) == true
                : next.status == "ARRIVED" && next.verificationStatus == "ACTIVE" && confirmed && Self.validCode(code)
        default: return false
        }
    }

    func submitReturn(_ operation: DastakDeliveryCommand.Operation, mission: DastakV1ReturnMission,
        stopID: UUID? = nil, confirmed: Bool = false, code: String? = nil,
        photo: Data? = nil, contentType: String? = nil) async {
        guard canReturn(operation, mission: mission, stopID: stopID, confirmed: confirmed, code: code), let accountID else {
            message = "Refresh the return and complete the required arrival, package, photo and PIN checks first."; return
        }
        let extensions = ["image/jpeg": "jpg", "image/png": "png", "image/heic": "heic"]
        let path = operation == .evidence ? extensions[contentType ?? ""].map {
            "return-pickup/\(accountID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\($0)"
        } : nil
        let command = DastakDeliveryCommand(accountID: accountID, key: key(), operation: operation,
            missionID: mission.id, expectedVersion: mission.version, stopID: stopID, code: code, reason: nil,
            objectPath: path, photo: photo, contentType: contentType)
        await saveAndSend(command)
    }

    func report(_ operation: DastakDeliveryCommand.Operation, mission: DastakV1DeliveryMissionSnapshot,
        current: DastakV1DeliveryMissionSnapshot?, reason: String, fresh: Bool) async {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !blocksActions, returnMission == nil, fresh, current == mission, mission.version > 0, mission.mustUseDeliveryRecovery,
              operation == .problem || operation == .unreachable, (3...500).contains(reason.count), let accountID else {
            message = "Refresh the assigned mission and enter a reason of 3–500 characters."; return
        }
        await saveAndSend(DastakDeliveryCommand(accountID: accountID, key: key(), operation: operation,
            missionID: mission.id, expectedVersion: mission.version, stopID: nil, code: nil, reason: reason,
            objectPath: nil, photo: nil, contentType: nil))
    }

    func submitOffer(_ offer: DastakV1RiderOffer, accept: Bool) async {
        guard !blocksActions, normalFresh, normalSnapshot?.currentMission == nil,
              normalSnapshot?.returnMission == nil, normalSnapshot?.offer == offer,
              offer.orderLoad != nil, offer.pickupStops?.count == offer.pickupCount,
              DastakDeliveryPresentation.secondsRemaining(until: offer.respondBy, now: .now) > 0,
              let accountID else { message = "Refresh the offer before responding."; return }
        var command = DastakDeliveryCommand(accountID: accountID, key: key(), operation: accept ? .accept : .decline,
            missionID: offer.missionID, expectedVersion: 1, stopID: nil, code: nil,
            reason: accept ? nil : "Partner declined", objectPath: nil, photo: nil, contentType: nil)
        command.offerID = offer.id
        await saveAndSend(command)
    }

    var normalFresh: Bool {
        normalReadAt.map { (0..<60).contains(Date.now.timeIntervalSince($0)) } == true
    }

    func submitAssignment(parcel: Bool, action: String, assignmentID: UUID, code: String?) async {
        guard !blocksActions, let accountID else { return }
        var command = DastakDeliveryCommand(accountID: accountID, key: key(), operation: parcel ? .parcelDelivery : .legacyDelivery,
            missionID: assignmentID, expectedVersion: 1, stopID: nil, code: code,
            reason: ["declineOffer", "declineAssignment"].contains(action) ? "Partner declined" : nil,
            objectPath: nil, photo: nil, contentType: nil)
        command.assignmentAction = action
        await saveAndSend(command)
    }

    func submitDelivery(_ operation: DastakDeliveryCommand.Operation, mission: DastakV1DeliveryMissionSnapshot,
        stopID: UUID? = nil, packageCount: Int? = nil, code: String? = nil, reason: String? = nil,
        photo: Data? = nil, contentType: String? = nil,
        outcome: DastakV1CollectionOutcome? = nil, method: DastakV1CollectionMethod? = nil,
        reference: String? = nil, failureReason: String? = nil) async {
        guard !blocksActions, normalFresh, normalSnapshot?.returnMission == nil,
              normalSnapshot?.currentMission == mission, let accountID,
              !operation.isReturn, !operation.isProblem, !operation.isOffer else {
            message = "Refresh the current delivery before taking an action."; return
        }
        // Arrival, PIN, photo and money gates are checked again by the server.
        // Local checks prevent stale or edited screens from initiating a new command.
        let next = mission.pickupStops.sorted { $0.sequence < $1.sequence }.first { $0.status != .completed }
        let allowed: Bool
        switch operation {
        case .start: allowed = mission.status == .assigned
        case .arrivePickup: allowed = next?.id == stopID && next?.status == .pending && mission.status != .assigned
        case .verifyPickup: allowed = next?.id == stopID && next?.status == .arrived && next?.ready == true && next?.packageCount == packageCount
        case .startFinal: allowed = mission.canStartFinalDelivery
        case .arriveDelivery: allowed = mission.canArriveCustomer
        case .verifyPIN: allowed = mission.canVerifyCustomerPIN == true
        case .deliveryEvidence: allowed = mission.canCaptureDeliveryEvidence && mission.finalVerification?.evidencePresent != true
        case .complete: allowed = mission.canCompleteDelivery == true
        case .verifyDelivery: allowed = mission.canVerifyDelivery
        case .cancel: allowed = mission.canCancelBeforePickup
        case .collection: allowed = mission.launchCollection?.canRecord == true && method.map { mission.launchCollection?.methods.contains($0) == true } == true
        default: allowed = false
        }
        guard allowed else { message = "Complete the current arrival, package, PIN, photo and payment checks first."; return }
        let path = operation == .deliveryEvidence ? ["image/jpeg": "jpg", "image/png": "png", "image/heic": "heic"][contentType ?? ""].map {
            "rider-delivery/\(accountID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\($0)"
        } : nil
        var command = DastakDeliveryCommand(accountID: accountID, key: key(), operation: operation,
            missionID: mission.id, expectedVersion: mission.version, stopID: stopID, code: code, reason: reason,
            objectPath: path, photo: photo, contentType: contentType)
        command.packageCount = packageCount; command.outcome = outcome; command.method = method
        command.collectionReference = reference; command.failureReason = failureReason
        await saveAndSend(command)
    }

    private func saveAndSend(_ command: DastakDeliveryCommand) async {
        guard !blocksActions, command.isValid else { message = "The action could not be secured. No request was sent."; return }
        busy = true; defer { busy = false }
        readRevision = UUID()
        confirmedSnapshot = nil
        do {
            try await storage.replace(command, accountID: command.accountID, expectedRevision: nil)
            pending = command
            await sendPending()
        } catch { message = "The action could not be saved. No request was sent. Reopen the workspace to recover any existing record."; restored = false }
    }
    func retry() async {
        guard restored, !busy, pending != nil else { return }
        // A delivery finished on another device must never replay a money or
        // custody write just to remove this device's recovery record.
        if pending?.operation == .collection { await reconcilePending() }
        guard pending != nil, !busy else { return }
        busy = true; defer { busy = false }
        readRevision = UUID()
        confirmedSnapshot = nil
        await sendPending(replaying: true)
    }
    /// Automatic recovery reuses the exact persisted intent/key. It never invents
    /// another action or changes PIN, evidence, payment details or assignment.
    func recoverAutomatically(now: Date = .now) async {
        guard !busy, lastAutomaticRecovery.map({ now.timeIntervalSince($0) >= 5 }) ?? true else { return }
        lastAutomaticRecovery = now
        if !restored { await restore() }
        guard restored, !busy, pending != nil else { return }
        if pending?.operation != .collection { await reconcilePending() }
        await retry()
    }
    private func sendPending(replaying: Bool = false) async {
        guard var command = pending, let accountID, command.accountID == accountID else { return }
        do {
            guard try await currentAccountID() == accountID else { throw DastakDeliveryJournalError.changed }
            // Another scene may have recovered this action; never replay a superseded disk record.
            let stored = try await storage.load(accountID)
            if stored == nil {
                pending = nil; readRevision = UUID(); message = "Saved action resolved. Refreshing delivery."; return
            }
            guard stored == command else { throw DastakDeliveryJournalError.changed }
            if command.acknowledged {
                try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
                pending = nil; message = "Action was already acknowledged. Local recovery finished; refresh the mission."; return
            }
            if command.operation.hasPhoto && !command.uploaded {
                guard let photo = command.photo, let path = command.objectPath, let type = command.contentType else { throw DastakDeliveryJournalError.invalid }
                do {
                    try await DastakDeliveryDeadline.run(after: .seconds(25)) { [services] in
                        try await services.uploadObject(bucket: "dastak-evidence", path: path, data: photo, contentType: type)
                    }
                }
                catch where DastakEvidenceUpload.isDuplicate(error) {
                    // Same immutable owned path/bytes; an upload may have completed before the timeout.
                }
                let old = command.revision
                command.uploaded = true; command.photo = nil; command.revision = UUID()
                try await storage.replace(command, accountID: accountID, expectedRevision: old)
                pending = command
            }
            guard try await currentAccountID() == accountID,
                  try await storage.load(accountID) == command else { throw DastakDeliveryJournalError.changed }
            let confirmed: Bool
            if command.operation.isAssignment {
                confirmed = try await sendAssignment(command)
            } else {
                let snapshot: DastakV1DeliveryDispatchSnapshot = try await functions.invoke("courier-dispatch",
                    request: request(command), idempotencyKey: command.key)
                confirmed = await acknowledges(command, snapshot: snapshot)
                if confirmed && !replaying {
                    adopt(snapshot, authoritative: true)
                    confirmedSnapshot = snapshot
                }
                if confirmed && replaying && command.operation.isReturn && snapshot.returnMission == nil {
                    // Final return receipt was corroborated by this rider's
                    // completed history; remove its obsolete active card.
                    adopt(snapshot, authoritative: true)
                }
            }
            guard confirmed else {
                message = "The response did not confirm this action. Keep custody unchanged and retry the saved action."; return
            }
            guard try await currentAccountID() == accountID else { throw DastakDeliveryJournalError.changed }
            let old = command.revision
            command.acknowledged = true; command.revision = UUID()
            try await storage.replace(command, accountID: accountID, expectedRevision: old)
            pending = command
            try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
            pending = nil; message = nil
        } catch {
            guard (try? await currentAccountID()) == accountID else {
                message = "The signed-in account changed. The saved action is retained for its original rider."; return
            }
            if case let FunctionClientError.api(status, _, reason) = error,
               (400..<500).contains(status), ![408, 429].contains(status) {
                do {
                    try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
                    pending = nil; invalidate(); message = reason + " Refresh before trying a new action."
                } catch { message = "The server rejected the action, but its recovery record could not be cleared. Actions remain locked." }
            } else {
                message = "The action has not been confirmed. Checking the delivery again is safe; your original action is saved."
            }
        }
    }

    /// Read-only resolution also runs after relaunch and polling. An empty desk
    /// is never proof that a write succeeded. Only this rider's matching terminal
    /// delivery, or matching collected payment, can retire a saved command.
    func reconcilePending() async {
        guard restored, !busy, let command = pending,
              !command.operation.isReturn, !command.operation.isAssignment,
              !command.operation.isOffer, let accountID else { return }
        busy = true; defer { busy = false }
        struct Request: Encodable, Sendable, SingleAttemptFunctionRequest {
            let operation = "partnerOrderDetail"
            let kind = "V1_DELIVERY"
            let workId: UUID
        }
        struct Receipt: Decodable, Sendable {
            let kind: String
            let workId: UUID
            let terminal: Bool
            let missionStatus: String
            let collection: DastakV1LaunchCollection?
        }
        do {
            guard try await currentAccountID() == accountID,
                  try await storage.load(accountID) == command else { return }
            let receipt: Receipt = try await functions.invoke("courier-dispatch",
                request: Request(workId: command.missionID), idempotencyKey: key())
            guard receipt.kind == "V1_DELIVERY", receipt.workId == command.missionID else { return }
            let delivered = receipt.terminal && receipt.missionStatus == "DELIVERED"
            let collected = command.operation == .collection && command.outcome == .collected
                && receipt.collection?.state == .collected
                && receipt.collection?.lastOutcome == .collected
                && receipt.collection?.lastMethod == command.method
            guard delivered || collected,
                  try await currentAccountID() == accountID,
                  try await storage.load(accountID) == command else { return }
            try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
            pending = nil; readRevision = UUID()
            message = delivered ? "This delivery is already completed. Saved action resolved." : "Payment collection is confirmed. Continue your delivery."
        } catch { /* An unavailable or ambiguous read never discards the saved action. */ }
    }
    private func sendAssignment(_ command: DastakDeliveryCommand) async throws -> Bool {
        let action = command.assignmentAction ?? ""
        let request = DastakDeliveryActionRequest(operation: action, verificationCode: command.code,
            reason: command.reason, assignmentId: command.missionID)
        if command.operation == .legacyDelivery {
            let reply: CourierDispatchSnapshot = try await functions.invoke("courier-dispatch", request: request, idempotencyKey: command.key)
            if action == "declineOffer" { return reply.offer?.assignmentID != command.missionID }
            if let job = reply.currentJob, job.assignmentID == command.missionID {
                switch action {
                case "acceptOffer": return job.assignmentStatus == .accepted
                case "startToStore": return job.orderStatus.rawValue == "en_route_to_pickup"
                case "arriveAtStore": return job.orderStatus == .atStore
                case "confirmPickup": return job.orderStatus.rawValue == "picked_up"
                case "startDelivery": return job.orderStatus.rawValue == "in_transit"
                default: break
                }
            }
        } else {
            let reply: ParcelPartnerSnapshot = try await functions.invoke("parcel-deliveries", request: request, idempotencyKey: command.key)
            if action == "declineAssignment" { return reply.offer?.assignmentID != command.missionID }
            if let job = reply.currentJob, job.assignmentID == command.missionID {
                switch action {
                case "acknowledgeAssignment": return job.assignmentStatus.rawValue == "acknowledged"
                case "startToPickup": return job.parcel.status.rawValue == "en_route_to_pickup"
                case "confirmPickup": return job.parcel.status.rawValue == "picked_up"
                case "startDelivery": return job.parcel.status.rawValue == "in_transit"
                default: break
                }
            }
        }
        guard action == "completeDelivery" else { return false }
        await refreshHistory()
        return historyCurrent && history.contains { $0.kind == (command.operation == .legacyDelivery ? "LEGACY_DELIVERY" : "PARCEL") && $0.workId == command.missionID && $0.outcome == "COMPLETED" }
    }
    private func acknowledges(_ command: DastakDeliveryCommand, snapshot: DastakV1DeliveryDispatchSnapshot) async -> Bool {
        if command.operation.isProblem {
            return snapshot.deliveryLaneCurrent && snapshot.currentMission?.id == command.missionID
                && snapshot.currentMission?.status == .deliveryRecovery
                && (snapshot.currentMission?.version ?? 0) > command.expectedVersion
        }
        if !command.operation.isReturn { return await acknowledgesDelivery(command, snapshot: snapshot) }
        guard snapshot.returnLaneCurrent else { return false }
        guard let mission = snapshot.returnMission else {
            guard command.operation == .receipt else { return false }
            await refreshHistory()
            return historyCurrent && history.contains { $0.kind == "RETURN" && $0.workId == command.missionID && $0.status == "COMPLETED" && $0.outcome == "RETURNED" }
        }
        guard mission.id == command.missionID, mission.version >= command.expectedVersion else { return false }
        switch command.operation {
        case .arriveCustomer: return mission.status == "AT_CUSTOMER" && mission.arrivedCustomerAt != nil
        case .evidence: return mission.evidence.contains { $0.objectPath == command.objectPath }
        case .pickup: return mission.status == "RETURNING_TO_MERCHANTS" && mission.pickupCompletedAt != nil && mission.pickupVerification.status == "CONSUMED"
        case .arriveStop: return mission.stops.contains { $0.id == command.stopID && $0.status == "ARRIVED" && $0.arrivedAt != nil }
        case .receipt: return mission.stops.contains { $0.id == command.stopID && $0.status == "COMPLETED" && $0.completedAt != nil && $0.verificationStatus == "CONSUMED" }
        default: return false
        }
    }
    private func acknowledgesDelivery(_ command: DastakDeliveryCommand, snapshot: DastakV1DeliveryDispatchSnapshot) async -> Bool {
        guard snapshot.deliveryLaneCurrent else { return false }
        if command.operation == .decline { return snapshot.offer?.id != command.offerID }
        if [.complete, .verifyDelivery].contains(command.operation) {
            return snapshot.completedLaneCurrent && snapshot.completedMission?.id == command.missionID && snapshot.completedMission?.status == "DELIVERED"
        }
        if command.operation == .cancel {
            // Release reuses the mission for the next rider, so it never becomes
            // this rider's CANCELLED history row. Require the explicit mutation receipt.
            return snapshot.reassignmentStarted == true && snapshot.currentMission == nil
        }
        guard let mission = snapshot.currentMission, mission.id == command.missionID, mission.version >= command.expectedVersion else { return false }
        switch command.operation {
        case .accept: return mission.status == .assigned
        case .start: return mission.status == .enRouteToPickups
        case .arrivePickup: return mission.pickupStops.contains { $0.id == command.stopID && $0.status == .arrived }
        case .verifyPickup: return mission.pickupStops.contains { $0.id == command.stopID && $0.status == .completed && $0.packageCount == command.packageCount }
        case .startFinal: return mission.status == .outForDelivery
        case .arriveDelivery: return mission.status == .arrived
        case .verifyPIN: return mission.finalVerification?.pinVerified == true
        case .deliveryEvidence: return mission.finalVerification?.evidencePresent == true
        case .collection:
            return mission.launchCollection?.lastOutcome == command.outcome
                && mission.launchCollection?.lastMethod == command.method
                && mission.launchCollection?.state == (command.outcome == .collected ? .collected : .retryNeeded)
        default: return false
        }
    }
    func heartbeat(_ mission: DastakV1DeliveryMissionSnapshot?, now: Date = .now) async {
        await heartbeatMonitor.send(mission, now: now)
        heartbeatFailure = heartbeatMonitor.failure
    }
    func refreshHistory() async {
        guard !historyLoading else { return }
        historyLoading = true; historyCurrent = false; defer { historyLoading = false }
        struct History: Encodable, Sendable { let operation = "partnerHistory"; let limit = 30 }
        do {
            let reply: DastakDeliveryWorkHistory = try await functions.invoke("courier-dispatch", request: History(), idempotencyKey: key())
            guard reply.items.count <= 30, Set(reply.items.map(\.id)).count == reply.items.count else { return }
            history = reply.items; historyCurrent = true
        } catch { /* Keep prior history visible and explicitly stale. */ }
    }
    private static func validCode(_ code: String?) -> Bool { code?.count == 6 && code?.allSatisfy { $0.isASCII && $0.isNumber } == true }
    private func key() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
    private func request(_ command: DastakDeliveryCommand) -> DastakDeliveryActionRequest {
        .init(operation: command.operation.rawValue,
            missionId: command.operation.isReturn || command.operation.isOffer ? nil : command.missionID,
            offerId: command.offerID, stopId: command.operation.isReturn ? nil : command.stopID,
            returnMissionId: command.operation.isReturn ? command.missionID : nil,
            returnStopId: command.operation.isReturn ? command.stopID : nil,
            verificationCode: command.code, accountedPackageCount: command.packageCount, objectPath: command.objectPath,
            reason: command.reason, outcome: command.outcome, method: command.method,
            collectionReference: command.collectionReference, failureReason: command.failureReason,
            expectedMissionVersion: command.operation == .collection ? command.expectedVersion : nil)
    }
}

/// Independent of GPS samples and delivery-card lifetime. Does not advance custody.
@MainActor
final class DastakDeliveryHeartbeat {
    private let functions: any FunctionClient
    private var lastSent: Date?
    private var sending = false
    private var missionID: UUID?
    private var generation = UUID()
    private(set) var failure: String?
    init(functions: any FunctionClient) { self.functions = functions }
    func reset(for id: UUID?) {
        guard missionID != id else { return }
        missionID = id; generation = UUID(); lastSent = nil; failure = nil
    }

    @discardableResult
    func send(_ mission: DastakV1DeliveryMissionSnapshot?, now: Date = .now) async -> Bool {
        reset(for: mission?.id)
        guard let mission, mission.version > 0, !sending,
              lastSent.map({ now.timeIntervalSince($0) >= 25 }) ?? true else { return false }
        let revision = generation
        sending = true; lastSent = now; defer { sending = false }
        struct Request: Encodable, Sendable, SingleAttemptFunctionRequest { let operation = "v1Heartbeat"; let missionId: UUID; let expectedVersion: Int }
        // This operation acknowledges liveness, not a dispatch snapshot. The
        // version it advances must be reconciled with a fresh mission read.
        struct Receipt: Decodable, Sendable {
            let missionId: UUID
            let version: Int
            let lastContactAt: String
            let escalationState: String
        }
        do {
            let reply: Receipt = try await functions.invoke("courier-dispatch",
                request: Request(missionId: mission.id, expectedVersion: mission.version),
                idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!)
            guard generation == revision else { return true }
            guard reply.missionId == mission.id, reply.version > mission.version,
                  DastakDeliveryTracking.date(reply.lastContactAt) != nil,
                  !reply.escalationState.isEmpty else { throw DastakDeliveryJournalError.changed }
            failure = nil
        } catch {
            if generation == revision { failure = "Delivery connection is delayed. Reconnecting automatically; keep packages secure." }
        }
        return true
    }
}
