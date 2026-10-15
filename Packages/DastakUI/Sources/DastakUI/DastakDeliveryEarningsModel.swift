import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakDeliveryPayoutCommand: Codable, Equatable, Sendable {
    let accountID: UUID
    var revision = UUID()
    let key: IdempotencyKey
    let request: DastakDeliveryPayoutRequest
    var acknowledged = false
    var valid: Bool {
        UUID(uuidString: key.rawValue) != nil && request.subjectType == "RIDER" &&
        ((request.operation == "requestRoyaltyWithdrawal" && request.subjectId == accountID && (request.amountPaise ?? 0) > 0)
         || (request.operation == "retryRoyaltyWithdrawal" && request.withdrawalId != nil && (request.expectedVersion ?? 0) > 0))
    }
}
protocol DastakDeliveryPayoutStorage: Sendable {
    func load(_ accountID: UUID) async throws -> DastakDeliveryPayoutCommand?
    func replace(_ command: DastakDeliveryPayoutCommand?, accountID: UUID, expectedRevision: UUID?) async throws
}
actor DastakDeliveryPayoutFileStore: DastakDeliveryPayoutStorage {
    static let shared = DastakDeliveryPayoutFileStore()
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("DastakDeliveryPayouts", isDirectory: true)) { self.directory = directory }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    func load(_ id: UUID) throws -> DastakDeliveryPayoutCommand? {
        let url = file(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 16_384 else { throw DastakDeliveryJournalError.invalid }
        let command = try JSONDecoder().decode(DastakDeliveryPayoutCommand.self, from: Data(contentsOf: url))
        guard command.accountID == id, command.valid else { throw DastakDeliveryJournalError.invalid }
        return command
    }
    func replace(_ command: DastakDeliveryPayoutCommand?, accountID: UUID, expectedRevision: UUID?) throws {
        guard try load(accountID)?.revision == expectedRevision else { throw DastakDeliveryJournalError.changed }
        let url = file(accountID)
        guard let command else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        guard command.accountID == accountID, command.valid else { throw DastakDeliveryJournalError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var folder = directory; var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try folder.setResourceValues(attributes)
        let data = try JSONEncoder().encode(command)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

@MainActor final class DastakDeliveryEarningsModel: ObservableObject {
    @Published private(set) var snapshot: DastakDeliveryEarnings?
    @Published private(set) var current = false
    @Published private(set) var loading = false
    @Published private(set) var busy = false
    @Published private(set) var restored = false
    @Published private(set) var pending: DastakDeliveryPayoutCommand?
    @Published private(set) var message: String?
    private let services: MarketplaceAuthenticatedServices
    private let client: DastakDeliveryEarningsClient
    private let storage: any DastakDeliveryPayoutStorage
    private var readAt: Date?
    private var accountID: UUID?
    var blocksActions: Bool { !restored || busy || pending != nil }
    var fresh: Bool { current && readAt.map { (0..<60).contains(Date.now.timeIntervalSince($0)) } == true }
    init(services: MarketplaceAuthenticatedServices, storage: any DastakDeliveryPayoutStorage = DastakDeliveryPayoutFileStore.shared) {
        self.services = services; client = .init(functions: services.functions); self.storage = storage
    }
    func load() async {
        guard !loading, !busy else { return }
        loading = true; current = false; defer { loading = false }
        do {
            let id = try await services.accountID()
            if !restored {
                pending = try await storage.load(id); accountID = id; restored = true
                if pending != nil { message = "A saved payout needs recovery. Retry its unchanged request before making another." }
            }
            guard id == accountID else { throw DastakDeliveryJournalError.changed }
            let value = try await client.snapshot(accountID: id)
            guard try await services.accountID() == id else { throw DastakDeliveryJournalError.changed }
            snapshot = value; current = true; readAt = .now
        } catch { message = "Earnings could not update. Last-known records are retained; payout controls remain locked until refreshed." }
    }
    func withdraw(subject: DastakDeliveryEarnings.Subject, amountPaise: Int) async {
        guard fresh, !blocksActions, let accountID, subject.subjectId == accountID,
              snapshot?.subjects.contains(where: { $0.id == subject.id && $0.availablePaise == subject.availablePaise }) == true,
              snapshot?.payoutAvailability?.withdrawalExecutionAvailable == true,
              subject.canWithdraw, subject.payoutDestination != nil, amountPaise > 0, amountPaise <= subject.availablePaise else { return }
        await saveAndSend(.init(accountID: accountID, key: key(), request: .init(subjectID: subject.id, amountPaise: amountPaise)))
    }
    func retryWithdrawal(_ withdrawal: DastakDeliveryEarnings.Withdrawal) async {
        guard fresh, !blocksActions, let accountID,
              snapshot?.payoutAvailability?.withdrawalExecutionAvailable == true,
              snapshot?.subjects.flatMap(\.withdrawals).contains(where: { $0.id == withdrawal.id && $0.version == withdrawal.version && $0.status == "FAILED_RETRYABLE" }) == true else { return }
        await saveAndSend(.init(accountID: accountID, key: key(), request: .init(withdrawalID: withdrawal.id, version: withdrawal.version)))
    }
    private func saveAndSend(_ command: DastakDeliveryPayoutCommand) async {
        guard !blocksActions, command.valid else { return }
        busy = true
        do {
            try await storage.replace(command, accountID: command.accountID, expectedRevision: nil)
            pending = command; await sendPending()
        } catch { restored = false; message = "The payout request could not be secured. No new request was sent." }
        busy = false; await load()
    }
    func recover() async {
        guard restored, !busy, pending != nil else { return }
        busy = true; await sendPending(); busy = false; await load()
    }
    private func sendPending() async {
        guard var command = pending, let accountID else { return }
        do {
            guard try await services.accountID() == accountID, command.accountID == accountID,
                  try await storage.load(accountID) == command else { throw DastakDeliveryJournalError.changed }
            if !command.acknowledged {
                let reply = try await client.payout(command.request, key: command.key)
                guard try await services.accountID() == accountID else { throw DastakDeliveryJournalError.changed }
                guard ["REQUESTED", "PROCESSING", "PAID", "FAILED_RETRYABLE", "FAILED", "REVERSED"].contains(reply.status ?? "") else { throw FunctionClientError.invalidResponse }
                guard command.request.withdrawalId.map({ $0 == reply.withdrawalId }) ?? (reply.amountPaise == command.request.amountPaise) else { throw FunctionClientError.invalidResponse }
                let old = command.revision; command.acknowledged = true; command.revision = UUID()
                try await storage.replace(command, accountID: accountID, expectedRevision: old); pending = command
            }
            try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
            pending = nil; message = "Payout request recorded. The ledger below shows processing or settlement; a request does not mean the money has arrived."
        } catch {
            guard (try? await services.accountID()) == accountID else {
                current = false; message = "The signed-in account changed. The saved payout remains with its original rider."; return
            }
            if !command.acknowledged, case let FunctionClientError.api(status, _, _) = error,
               (400..<500).contains(status), ![408, 429].contains(status) {
                do {
                    try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
                    pending = nil; current = false
                    message = "The payout request was rejected. Refresh the ledger and review your available balance and destination before starting a new request."
                    return
                } catch { /* Keep the record locked if local cleanup cannot be confirmed. */ }
            }
            // A failure can follow reservation/provider execution. Never discard or mint a replacement key.
            current = false; message = "Payout outcome is uncertain. Retry the saved request; its original amount and key are retained."
        }
    }
    func register(_ request: DastakDeliveryDestinationRequest) async {
        guard !blocksActions, fresh, let accountID, request.subjectId == accountID,
              snapshot?.payoutAvailability?.destinationRegistrationAvailable == true else { return }
        busy = true; current = false
        do {
            guard try await services.accountID() == accountID else { throw DastakDeliveryJournalError.changed }
            try await client.destination(request)
            message = "Destination submitted. Check the masked payout destination after refresh."
        } catch { message = "Destination result could not be confirmed. Refresh and check the masked destination before submitting it again." }
        busy = false; await load()
    }
    private func key() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
}
