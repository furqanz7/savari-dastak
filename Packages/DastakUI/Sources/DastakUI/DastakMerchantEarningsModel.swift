import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

@MainActor
final class DastakMerchantEarningsModel: ObservableObject {
    @Published private(set) var snapshot: DastakMerchantRoyalty?
    @Published private(set) var loading = false
    @Published private(set) var current = false
    @Published private(set) var checkedAt: Date?
    @Published private(set) var failure: String?
    @Published var selectedOrganizationID: UUID?
    @Published private(set) var pending: DastakMerchantPayoutCommand?
    @Published private(set) var restored = false
    @Published private(set) var busy = false
    @Published private(set) var payoutMessage: String?
    private let services: MarketplaceAuthenticatedServices
    private let client: DastakMerchantRoyaltyClient
    private let timeout: Duration
    private var generation = UUID()
    private var owner: UUID?
    private let storage: any DastakMerchantPayoutStorage

    init(services: MarketplaceAuthenticatedServices, timeout: Duration = .seconds(12),storage: any DastakMerchantPayoutStorage = DastakMerchantMemoryPayoutStore()) {
        self.services = services; self.timeout = timeout
        self.storage = storage
        client = .init(functions: DastakMerchantFunctionClient(base: services.functions, timeout: timeout))
    }
    var visibleSubjects: [DastakMerchantRoyalty.Subject] {
        guard let subjects = snapshot?.subjects else { return [] }
        return selectedOrganizationID.map { id in subjects.filter { $0.id == id } } ?? subjects
    }
    func invalidate() {
        generation = UUID(); loading = false; current = false
    }
    func load() async {
        guard !loading,!busy else { return }
        let token = UUID(); generation = token; loading = true; current = false
        defer { if token == generation { loading = false } }
        do {
            if !restored {
                let services = services,storage = storage,expectedOwner = owner
                do {
                  let restoredValue = try await MarketplaceRequestDeadline.run(after:timeout) {
                    let account = try await services.accountID()
                    guard expectedOwner == nil || expectedOwner == account else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                    let saved = try await storage.load(account)
                    guard saved == nil || (saved?.accountID==account && saved?.valid==true) else { throw DastakAdminExecutionError.invalid }
                    guard account == (try await services.accountID()) else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                    return (account,saved)
                  }
                  guard token==generation,!Task.isCancelled else { return }
                  owner = restoredValue.0; pending = restoredValue.1; restored = true
                  if pending != nil { payoutMessage = "A saved financial action needs manual recovery. No payout or destination request is sent by opening or refreshing this screen." }
                } catch {
                    if error is MarketplaceAuthenticatedServicesError { throw error }
                    guard token==generation,!Task.isCancelled else { return }
                    payoutMessage = "Secure payout recovery storage is unavailable. Unlock this device and refresh. Earnings may still be read, but financial changes remain locked."
                }
            }
            let services = services, client = client, expectedOwner = owner
            let result = try await MarketplaceRequestDeadline.run(after: timeout) {
                let account = try await services.accountID()
                guard expectedOwner == nil || expectedOwner == account else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                let snapshot = try await client.snapshot()
                guard try await services.accountID() == account else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                return (account, snapshot)
            }
            guard token == generation, !Task.isCancelled else { return }
            owner = result.0; snapshot = result.1; current = true; checkedAt = .now; failure = nil
            if let selectedOrganizationID, !result.1.subjects.contains(where: { $0.id == selectedOrganizationID }) { self.selectedOrganizationID = nil }
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            var denied = error is MarketplaceAuthenticatedServicesError
            if case FunctionClientError.authenticationRequired = error { denied = true }
            if case let FunctionClientError.api(status, _, _) = error, [401,403,404].contains(status) { denied = true }
            if denied {
                snapshot = nil; checkedAt = nil; selectedOrganizationID = nil
                pending = nil; restored = false
                failure = "Earnings access could not be verified. Return to Account and check your Merchant session."
            } else {
                failure = "Earnings could not update. Any displayed amounts are from the last successful check, not a current balance."
            }
        }
    }
    var blocksFinancialActions: Bool { busy || !restored || pending != nil }
    var fresh: Bool { current && !loading && checkedAt.map { (0..<60).contains(Date.now.timeIntervalSince($0)) } == true }
    func canManage(_ organization: UUID) -> Bool {
        fresh && !blocksFinancialActions && snapshot?.payoutAvailability?.merchantControlsAvailable == true
            && snapshot?.subjects.first(where:{$0.id==organization})?.canManagePayouts == true
    }
    func canWithdraw(_ subject: DastakMerchantRoyalty.Subject,amount: Int) -> Bool {
        canManage(subject.id) && snapshot?.payoutAvailability?.withdrawalExecutionAvailable == true
            && subject.canWithdraw && subject.payoutDestination != nil && amount>0 && amount<=subject.availablePaise && amount<=9_007_199_254_740_991
            && snapshot?.subjects.contains(where:{$0.id==subject.id && $0.availablePaise==subject.availablePaise && $0.payoutDestination==subject.payoutDestination && $0.canWithdraw}) == true
    }
    func canRetry(_ withdrawal: DastakMerchantRoyalty.Withdrawal,organization: UUID) -> Bool {
        canManage(organization) && snapshot?.payoutAvailability?.withdrawalExecutionAvailable == true
            && Self.retryable(withdrawal)
            && snapshot?.subjects.first(where:{$0.id==organization})?.withdrawals.contains(where:{$0.id==withdrawal.id && $0.version==withdrawal.version && $0.amountPaise==withdrawal.amountPaise && $0.status==withdrawal.status && $0.reconciliationState==withdrawal.reconciliationState}) == true
    }
    private static func retryable(_ value: DastakMerchantRoyalty.Withdrawal) -> Bool {
        value.status == "REQUESTED" || value.status == "FAILED_RETRYABLE" || (value.status == "PROCESSING" && value.reconciliationState == "PENDING")
    }
    @discardableResult func withdraw(subject: DastakMerchantRoyalty.Subject,amount: Int) async -> Bool {
        guard canWithdraw(subject,amount:amount),let destination = subject.payoutDestination,let owner else {
            payoutMessage = "Refresh and review this business balance and payout destination before requesting a withdrawal."; return false
        }
        return await secureAndSend(.init(accountID:owner,organizationID:subject.id,key:key(),operation:.withdraw(amount:amount,destination:destination.id,destinationVersion:destination.version)))
    }
    @discardableResult func retry(_ withdrawal: DastakMerchantRoyalty.Withdrawal,organization: UUID) async -> Bool {
        guard canRetry(withdrawal,organization:organization),let owner else {
            payoutMessage = "This payout is not currently eligible for a retry. Refresh its recorded status first."; return false
        }
        return await secureAndSend(.init(accountID:owner,organizationID:organization,key:key(),operation:.retry(withdrawal:withdrawal.id,version:withdrawal.version,amount:withdrawal.amountPaise)))
    }
    @discardableResult func register(_ request: DastakMerchantDestinationRequest,reviewed: DastakMerchantRoyalty.Destination?) async -> Bool {
        guard canManage(request.subjectId),request.valid,let owner,
              snapshot?.payoutAvailability?.destinationRegistrationAvailable == true,
              snapshot?.subjects.first(where:{$0.id==request.subjectId})?.payoutDestination == reviewed else {
            payoutMessage = "Refresh and review the business and destination details before submitting setup."; return false
        }
        return await secureAndSend(.init(accountID:owner,organizationID:request.subjectId,key:key(),operation:.destination(request)))
    }
    private func key() -> IdempotencyKey { IdempotencyKey(rawValue:UUID().uuidString)! }
    private func account(_ expected: UUID) async throws {
        guard try await MarketplaceRequestDeadline.run(after:timeout,operation:{ [services] in try await services.accountID() }) == expected else {
            snapshot = nil; checkedAt = nil; current = false; pending = nil; restored = false
            throw MarketplaceAuthenticatedServicesError.identityMismatch
        }
    }
    private func stored(_ account: UUID) async throws -> DastakMerchantPayoutCommand? {
        try await MarketplaceRequestDeadline.run(after:timeout) { [storage] in try await storage.load(account) }
    }
    private func replace(_ value: DastakMerchantPayoutCommand?,account: UUID,expected: UUID?) async throws {
        try await MarketplaceRequestDeadline.run(after:timeout) { [storage] in try await storage.replace(value,account:account,expectedRevision:expected) }
    }
    private func secureAndSend(_ command: DastakMerchantPayoutCommand) async -> Bool {
        guard !blocksFinancialActions,command.valid else { return false }
        busy = true; generation = UUID(); loading = false; current = false
        var result = false
        do {
            try await account(command.accountID)
            try await replace(command,account:command.accountID,expected:nil)
            pending = command
            result = await sendPending()
        } catch {
            restored = false
            payoutMessage = "The action could not be secured or its local result is uncertain. No replacement request was made. Refresh recovery storage before continuing."
        }
        busy = false; await load(); return result
    }
    /// Explicit user action only: no timer, appearance or foreground callback
    /// invokes a financial mutation or resubmits bank/UPI details.
    @discardableResult func recover() async -> Bool {
        guard !busy,restored,let pending else { return false }
        if !pending.acknowledged {
            await load()
            guard fresh,snapshot?.payoutAvailability?.merchantControlsAvailable == true,
                  let subject = snapshot?.subjects.first(where:{$0.id==pending.organizationID}),subject.canManagePayouts == true else {
                payoutMessage = "Recovery requires a fresh authorized business read. The original secure record is retained."; return false
            }
            let available: Bool
            if case .destination = pending.operation { available = snapshot?.payoutAvailability?.destinationRegistrationAvailable == true }
            else { available = snapshot?.payoutAvailability?.withdrawalExecutionAvailable == true }
            guard available else { payoutMessage = "The payout service is unavailable. The original action is retained; no new request was sent."; return false }
        }
        busy = true; generation = UUID(); loading = false; current = false
        let result = await sendPending(); busy = false; await load(); return result
    }
    private func sendPending() async -> Bool {
        guard var command = pending else { return false }
        do {
            try await account(command.accountID)
            let saved = try await stored(command.accountID)
            guard saved == command else {
                pending = saved; restored = saved != nil
                throw DastakAdminExecutionError.changed
            }
            if !command.acknowledged {
                let old = command.revision; command.revision = UUID(); command.attempts += 1
                try await replace(command,account:command.accountID,expected:old); pending = command
                try await account(command.accountID)
                let client = client,operation = command.operation,key = command.key,organization = command.organizationID
                // A retry's version may already have advanced while the prior
                // response was lost. A fresh exact organization/record read
                // resolves that recorded transition without another write.
                var resolvedRetry = false
                if case let .retry(id,version,amount) = operation,
                   let row = snapshot?.subjects.first(where:{$0.id==organization})?.withdrawals.first(where:{$0.id==id}),
                   row.version>version,row.amountPaise==amount { resolvedRetry = true }
                if !resolvedRetry {
                    try await MarketplaceRequestDeadline.run(after:timeout) {
                        switch operation {
                        case let .withdraw(amount,destination,version):
                            let reply = try await client.withdraw(organization:organization,amount:amount,destination:destination,version:version,key:key)
                            guard reply.amountPaise==amount,Self.validStatus(reply.status) else { throw FunctionClientError.invalidResponse }
                        case let .retry(id,version,_):
                            let reply = try await client.retry(withdrawal:id,version:version,key:key)
                            guard reply.withdrawalId==id,Self.validStatus(reply.status) else { throw FunctionClientError.invalidResponse }
                        case let .destination(request): _ = try await client.register(request,key:key)
                        }
                    }
                }
                try await account(command.accountID)
                let oldRevision = command.revision; command.revision = UUID(); command.acknowledged = true
                try await replace(command,account:command.accountID,expected:oldRevision); pending = command
            }
            try await account(command.accountID)
            try await replace(nil,account:command.accountID,expected:command.revision)
            pending = nil; payoutMessage = "Financial action recorded. Check the refreshed masked destination and payout history. A request or processing state is not confirmation that money has arrived."
            return true
        } catch {
            if case MarketplaceAuthenticatedServicesError.identityMismatch = error {
                payoutMessage = "The signed-in account changed. The secure action remains with its original account and business."; return false
            }
            if !command.acknowledged,case let FunctionClientError.api(status,code,_) = error,
               ((command.attempts==1 && (400..<500).contains(status) && ![408,429].contains(status)) || (status==409 && code=="payout_destination_changed")) {
                do {
                    try await account(command.accountID)
                    try await replace(nil,account:command.accountID,expected:command.revision)
                    pending = nil; payoutMessage = "The action was rejected. Refresh and review the current business balance and destination before making a new request."; return false
                } catch { /* An unconfirmed cleanup keeps recovery locked. */ }
            }
            payoutMessage = command.acknowledged ? "The server acknowledged this action, but secure local cleanup is pending. Recover it to finish cleanup without another submission."
                : "The financial result is uncertain. The original account, business and request are retained securely. Use manual recovery; do not create a replacement withdrawal or change destination details."
            return false
        }
    }
    nonisolated private static func validStatus(_ value: String) -> Bool { ["REQUESTED","PROCESSING","PAID","FAILED_RETRYABLE","FAILED","REVERSED"].contains(value) }
}

enum DastakMerchantEarningsPresentation {
    enum LedgerFilter: String, CaseIterable { case all = "All", credits = "Credits", adjustments = "Adjustments" }
    static func label(_ value: String) -> String {
        switch value {
        case "MERCHANT_ROYALTY_EARNING": "Order earnings"
        case "ROYALTY_FAULT_ADJUSTMENT": "Fault adjustment"
        case "ROYALTY_CREDIT_ADJUSTMENT": "Credit adjustment"
        case "ROYALTY_WITHDRAWAL_RESERVED": "Withdrawal reserved"
        case "ROYALTY_WITHDRAWAL_RELEASED": "Withdrawal released"
        case "FAILED_RETRYABLE": "Retry available"
        case "REQUESTED": "Requested"
        case "PROCESSING": "Processing"
        case "PAID": "Paid"
        case "FAILED": "Failed"
        case "REVERSED": "Reversed"
        default: value.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
        }
    }
    static func entries(_ subject: DastakMerchantRoyalty.Subject, filter: LedgerFilter, query: String) -> [DastakMerchantRoyalty.Entry] {
        let adjustmentIDs = Set(subject.adjustments.map(\.id))
        // Adjustments are a subset of the ledger, not another balance to add.
        let source = filter == .adjustments ? subject.adjustments : subject.entries
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.filter { entry in
            (filter != .credits || (entry.amountPaise > 0 && !adjustmentIDs.contains(entry.id)))
                && (needle.isEmpty || [label(entry.type), entry.reason, entry.orderId?.uuidString ?? "", entry.id.uuidString]
                    .contains { $0.localizedCaseInsensitiveContains(needle) })
        }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
    }
    static func payoutStatus(_ snapshot: DastakMerchantRoyalty, subject: DastakMerchantRoyalty.Subject) -> String {
        guard let availability = snapshot.payoutAvailability else { return "Payout availability could not be verified." }
        if !availability.withdrawalExecutionAvailable { return "Withdrawals are not available right now. Ledger records remain visible." }
        if subject.payoutDestination == nil { return "No payout destination is registered for this business." }
        return subject.canWithdraw ? "The server reports this business eligible to request a withdrawal." : "This business is not currently eligible to request a withdrawal."
    }
}
