import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakAdminCustomerRecoveryIntent: Identifiable {
    let id = UUID()
    let row: DastakAdminCustomerRecoveryRow
    let action: DastakAdminCustomerRecoveryCommand.Action
    let sessionID: UUID?
    let replacementPhone: String?
    var scope: String { sessionID == nil ? "ALL" : "SINGLE" }
    var title: String { action == .phone ? "Correct contact phone" : sessionID == nil ? "Revoke all account sessions" : "Revoke reviewed session" }
    var confirmationValue: String { action == .phone ? replacementPhone ?? "" : row.id.uuidString }
    func valid(reason: String, confirmation: String, acknowledged: Bool) -> Bool {
        guard acknowledged, row.valid, row.account.accountState == "ACTIVE", row.account.customerState == "ACTIVE",
              confirmation == confirmationValue, (3...(action == .phone ? 500 : 200)).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count) else { return false }
        if action == .phone { return row.phoneClaim.version > 0 && row.phoneClaim.version < 9_007_199_254_740_991 && replacementPhone.map(DastakAdminCustomerRecoveryContract.phone) == true && replacementPhone != row.account.currentPhoneNumber }
        return replacementPhone == nil && (sessionID.map { id in row.sessions.contains { $0.id == id } } ?? (row.activeSessionCount > 0))
    }
}

@MainActor
final class DastakAdminCustomerRecoveryModel: ObservableObject {
    @Published private(set) var rows: [DastakAdminCustomerRecoveryRow] = []
    @Published private(set) var loading = false
    @Published private(set) var busy = false
    @Published private(set) var restored = false
    @Published private(set) var pending: DastakAdminCustomerRecoveryCommand?
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var current = false
    @Published private(set) var cursor: DastakAdminCustomerRecoveryCursor?
    @Published private(set) var query = ""
    private let services: MarketplaceAuthenticatedServices
    private let client: any DastakAdminCustomerRecoveryClient
    private let storage: any DastakAdminCustomerRecoveryStorage
    private var actorID: UUID?
    private var generation = UUID()
    private var mutationEpoch = UUID()
    private var readAt: [UUID: Date] = [:]
    private var seenCursors: Set<String> = []
    var blocksActions: Bool { !restored || busy || loading || pending != nil }
    init(services: MarketplaceAuthenticatedServices, storage: any DastakAdminCustomerRecoveryStorage = DastakAdminCustomerRecoveryFileStore.shared) {
        self.services = services; self.client = SupabaseDastakV1AdminClient(functions: services.functions); self.storage = storage
    }
    func restore() async {
        guard !restored, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let actor = try await services.accountID()
            let saved = try await storage.load(actor)
            guard try await services.accountID() == actor else { throw DastakAdminExecutionError.changed }
            actorID = actor; pending = saved; restored = true
            if saved != nil { notice = "A saved customer-recovery action needs resolution. Retry its original request before starting another." }
        } catch { clearAfterIdentityMismatch(error); self.error = "Customer recovery storage is unavailable. Actions remain locked; no saved command was removed." }
    }
    func load(query: String? = nil, append: Bool = false) async {
        await restore()
        guard restored, !busy, let actorID else { return }
        let nextQuery = (query ?? self.query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard nextQuery.count <= 100 else { error = "Search must be 100 characters or fewer."; return }
        guard !append || (current && !loading && cursor != nil && nextQuery == self.query) else { return }
        if nextQuery != self.query { rows = []; readAt = [:]; cursor = nil }
        self.query = nextQuery
        let priorCursor = append ? cursor : nil
        let ticket = UUID(); generation = ticket
        let epoch = mutationEpoch
        loading = true; current = false
        if !append { readAt = [:]; cursor = nil; seenCursors = [] }
        defer { if generation == ticket { loading = false } }
        do {
            guard try await services.accountID() == actorID else { throw DastakAdminExecutionError.changed }
            let page = try await client.customerRecoveryPage(query: nextQuery.isEmpty ? nil : nextQuery, accountId: nil, limit: 40, cursor: priorCursor, idempotencyKey: key())
            guard generation == ticket, mutationEpoch == epoch, try await services.accountID() == actorID else { return }
            if let cursor = page.nextCursor, seenCursors.contains(cursorKey(cursor)) { throw FunctionClientError.invalidResponse }
            var merged = append ? rows : []
            for row in page.customers {
                if let index = merged.firstIndex(where: { $0.id == row.id }) {
                    guard row.phoneClaim.version >= merged[index].phoneClaim.version,
                          DastakAdminCustomerRecoveryContract.date(row.updatedAt)! >= DastakAdminCustomerRecoveryContract.date(merged[index].updatedAt)! else { throw FunctionClientError.invalidResponse }
                    merged[index] = row
                } else { merged.append(row) }
            }
            rows = merged
            for row in page.customers { readAt[row.id] = .now }
            cursor = page.hasMore ? page.nextCursor : nil
            if let cursor { seenCursors.insert(cursorKey(cursor)) }
            current = true; error = nil
        } catch {
            guard generation == ticket, mutationEpoch == epoch else { return }
            clearAfterIdentityMismatch(error)
            readAt = [:]; current = false
            if Self.authorizationError(error) { rows = []; cursor = nil }
            self.error = "Customer records could not be refreshed with current authorization. Existing records are read-only until a successful refresh."
        }
    }
    func fresh(_ row: DastakAdminCustomerRecoveryRow, now: Date = .now) -> Bool {
        current && row.valid && rows.first(where: { $0.id == row.id }) == row && readAt[row.id].map { (0..<60).contains(now.timeIntervalSince($0)) } == true
    }
    func canConfirm(_ intent: DastakAdminCustomerRecoveryIntent, reason: String, confirmation: String, acknowledged: Bool, now: Date = .now) -> Bool {
        !blocksActions && fresh(intent.row, now: now) && intent.valid(reason: reason, confirmation: confirmation, acknowledged: acknowledged)
    }
    @discardableResult
    func submit(_ intent: DastakAdminCustomerRecoveryIntent, reason: String, confirmation: String, acknowledged: Bool) async -> Bool {
        guard canConfirm(intent, reason: reason, confirmation: confirmation, acknowledged: acknowledged), let actorID else { error = "This review is incomplete, changed or expired. Refresh the customer and review again."; return false }
        let command = DastakAdminCustomerRecoveryCommand(actorID: actorID, accountID: intent.row.id, action: intent.action,
            scope: intent.action == .sessions ? intent.scope : nil, sessionID: intent.action == .sessions ? intent.sessionID : nil,
            currentPhone: intent.action == .phone ? intent.row.account.currentPhoneNumber : nil,
            replacementPhone: intent.action == .phone ? intent.replacementPhone : nil,
            claimVersion: intent.action == .phone ? intent.row.phoneClaim.version : nil,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), key: key())
        guard command.valid else { return false }
        busy = true; invalidateReads(); error = nil; notice = nil
        var result = false
        do {
            guard try await services.accountID() == actorID else { throw DastakAdminExecutionError.changed }
            try await storage.replace(command, actorID: actorID, expectedRevision: nil)
            pending = command; result = await sendPending()
        } catch { clearAfterIdentityMismatch(error); restored = false; self.error = "The action could not be saved safely. No write was sent. Reopen recovery to inspect existing saved state." }
        busy = false
        if pending == nil && restored { await refreshAfterAction() }
        return result
    }
    @discardableResult
    func retry() async -> Bool {
        guard restored, !busy, pending != nil else { return false }
        busy = true; invalidateReads(); error = nil
        let result = await sendPending()
        busy = false
        if pending == nil { await refreshAfterAction() }
        return result
    }
    private func refreshAfterAction() async {
        let actionError = error
        await load()
        if let actionError { error = actionError + (error.map { " " + $0 } ?? "") }
    }
    private func sendPending() async -> Bool {
        guard var command = pending, let actorID, command.actorID == actorID else { return false }
        do {
            guard command.valid, try await services.accountID() == actorID, try await storage.load(actorID) == command else { throw DastakAdminExecutionError.changed }
            if !command.acknowledged {
                // Persist the attempt BEFORE sending. A rejection on a later retry does not prove
                // the earlier uncertain request never succeeded, particularly after permissions change.
                let old = command.revision; command.attempts += 1; command.revision = UUID()
                try await storage.replace(command, actorID: actorID, expectedRevision: old); pending = command
                guard try await services.accountID() == actorID, try await storage.load(actorID) == command else { throw DastakAdminExecutionError.changed }
                let summary: String
                switch command.action {
                case .sessions:
                    let result = try await client.revokeCustomerSessions(accountId: command.accountID, scope: command.scope!, sessionId: command.sessionID, reason: command.reason, idempotencyKey: command.key)
                    guard Self.acknowledges(command, result) else { throw FunctionClientError.invalidResponse }
                    summary = "Session action acknowledged: \(result.revokedSessionCount) revoked; \(result.activeSessionCount) active at the response time. Refresh shows the current sessions."
                case .phone:
                    let result = try await client.correctCustomerPhone(accountId: command.accountID, reviewedCurrentPhone: command.currentPhone!, replacementPhone: command.replacementPhone!, expectedPhoneClaimVersion: command.claimVersion!, reason: command.reason, idempotencyKey: command.key)
                    guard Self.acknowledges(command, result) else { throw FunctionClientError.invalidResponse }
                    summary = "Dastak contact phone corrected to an unverified claim. OAuth sign-in identity, email and existing order-recipient snapshots are unchanged."
                }
                guard try await services.accountID() == actorID else { throw DastakAdminExecutionError.changed }
                let acknowledgementRevision = command.revision; command.acknowledged = true; command.revision = UUID()
                try await storage.replace(command, actorID: actorID, expectedRevision: acknowledgementRevision); pending = command
                notice = summary
            } else { notice = "The saved action was already acknowledged. Finishing local cleanup does not repeat the server write." }
            try await storage.replace(nil, actorID: actorID, expectedRevision: command.revision)
            pending = nil
            return true
        } catch {
            clearAfterIdentityMismatch(error)
            if command.attempts == 1, case let FunctionClientError.api(status, _, serverMessage) = error, (400..<500).contains(status), ![408, 429].contains(status) {
                do {
                    try await storage.replace(nil, actorID: actorID, expectedRevision: command.revision); pending = nil
                    self.error = serverMessage.contains("PHONE_NUMBER_ALREADY_CLAIMED")
                        ? "That phone is already claimed by another account. No accounts were merged. Review another number before retrying."
                        : "The server rejected this first request. Review refreshed permission, session state or phone-claim ownership before a new action."
                } catch { self.error = "The rejected action could not be cleared locally. Recovery remains locked." }
            } else { self.error = "The action outcome or local storage is uncertain. Its original request is retained. Retry without editing the customer, phone, session, reason or scope." }
            return false
        }
    }
    static func acknowledges(_ command: DastakAdminCustomerRecoveryCommand, _ result: DastakAdminCustomerSessionResult) -> Bool {
        guard command.action == .sessions, result.accountId == command.accountID, result.scope == command.scope,
              result.revokedSessionCount >= 0, result.activeSessionCount >= 0, DastakAdminCustomerRecoveryContract.date(result.updatedAt) != nil else { return false }
        return command.scope == "SINGLE" ? result.revokedSessionId == command.sessionID && result.revokedSessionCount == 1 : result.revokedSessionId == nil
    }
    static func acknowledges(_ command: DastakAdminCustomerRecoveryCommand, _ result: DastakAdminCustomerPhoneResult) -> Bool {
        command.action == .phone && result.accountId == command.accountID && result.phoneClaimVersion == (command.claimVersion ?? 0) + 1 && result.phoneVerificationState == "unverified" && result.maskedPhoneNumber == command.replacementPhone.map(DastakAdminCustomerRecoveryContract.mask) && DastakAdminCustomerRecoveryContract.date(result.updatedAt) != nil
    }
    private func invalidateReads() { mutationEpoch = UUID(); current = false; readAt = [:] }
    private func clearAfterIdentityMismatch(_ error: Error) {
        switch error {
        case DastakAdminExecutionError.changed, MarketplaceAuthenticatedServicesError.identityMismatch:
            // Clear presentation only. The old actor's protected journal is not deleted.
            rows = []; readAt = [:]; cursor = nil; current = false; notice = nil
            pending = nil; actorID = nil; restored = false
        default: break
        }
    }
    func markStale() { invalidateReads() }
    private func key() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
    private func cursorKey(_ cursor: DastakAdminCustomerRecoveryCursor) -> String { cursor.updatedAt + cursor.accountId.uuidString }
    private static func authorizationError(_ error: Error) -> Bool {
        if case FunctionClientError.authenticationRequired = error { return true }
        if case MarketplaceAuthenticatedServicesError.authenticationRequired = error { return true }
        if case let FunctionClientError.api(status, _, _) = error { return [401, 403].contains(status) }
        return false
    }
}
