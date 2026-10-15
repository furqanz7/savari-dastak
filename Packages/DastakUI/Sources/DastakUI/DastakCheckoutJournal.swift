import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakPendingCheckout: Codable, Equatable, Sendable {
    let service: DastakBasketService
    let key: IdempotencyKey
    let submission: DastakV1OrderSubmission
    var orderID: UUID?
}

struct DastakPendingConfirmation: Codable, Equatable, Sendable {
    let orderID: UUID
    let expectedVersion: Int
    let key: IdempotencyKey
}

struct DastakCheckoutJournal: Codable, Equatable, Sendable {
    var version = 1
    let accountID: UUID
    var revision = UUID()
    let baskets: DastakCustomerBaskets
    let pending: [DastakPendingCheckout]
    // Optional for compatibility with existing version-1 basket journals.
    var confirmations: [DastakPendingConfirmation]? = nil

    var isValid: Bool {
        version == 1 && baskets.isValid && pending.count <= 2
            && (confirmations ?? []).count <= 64
            && Set((confirmations ?? []).map(\.orderID)).count == (confirmations ?? []).count
            && (confirmations ?? []).allSatisfy { $0.expectedVersion > 0 && UUID(uuidString: $0.key.rawValue) != nil }
            && Set(pending.map(\.service)).count == pending.count
            && pending.allSatisfy {
                let basket = baskets[$0.service]
                return !basket.isEmpty && basket.orderLines == $0.submission.lines
                    && basket.restaurantBranchID == $0.submission.restaurantBranchID
                    && UUID(uuidString: $0.key.rawValue) != nil
            }
    }
}

enum DastakCheckoutStorageError: Error {
    case invalidJournal, changedJournal, unavailable, customerDeleted
}

enum DastakCustomerDeletionError: LocalizedError {
    case busy, identityUnavailable, unresolvedCheckout, outcomeUnknown, cleanupRequired

    var errorDescription: String? {
        switch self {
        case .busy: "Wait for the current checkout or account action to finish, then try again."
        case .identityUnavailable: "Sign in and load your saved baskets before deleting your Customer profile."
        case .unresolvedCheckout: "Recover your pending checkout in Orders before deleting your Customer profile. No recovery records have been removed."
        case .outcomeUnknown: "We could not confirm whether your Customer profile was deleted. Your local data has been kept. Retry to check the same deletion request."
        case .cleanupRequired: "Your Customer profile was deleted, but this device could not finish clearing its local data. Retry to finish local cleanup; your profile will not be deleted again."
        }
    }
}

@MainActor
protocol DastakCheckoutJournalStorage {
    func load(accountID: UUID) throws -> DastakCheckoutJournal?
    func save(_ journal: DastakCheckoutJournal, replacing revision: UUID?) throws
    func hasAcknowledgedCustomerDeletion(accountID: UUID) throws -> Bool
    func acknowledgeCustomerDeletion(accountID: UUID) throws
    func removeAfterAcknowledgedCustomerDeletion(accountID: UUID) throws
}

extension DastakCheckoutJournalStorage {
    func hasAcknowledgedCustomerDeletion(accountID: UUID) throws -> Bool { false }
    // Storage without explicit deletion support must not pretend cleanup succeeded.
    func acknowledgeCustomerDeletion(accountID: UUID) throws { throw DastakCheckoutStorageError.unavailable }
    func removeAfterAcknowledgedCustomerDeletion(accountID: UUID) throws { throw DastakCheckoutStorageError.unavailable }
}

/// One atomic record includes both basket consumption and pending attempts.
/// A corrupt/unreadable record is an error, never a reason to start a new order.
@MainActor
struct DastakFileCheckoutJournalStorage: DastakCheckoutJournalStorage {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Dastak", isDirectory: true)
            .appendingPathComponent("CheckoutRecovery", isDirectory: true)
    }

    func load(accountID: UUID) throws -> DastakCheckoutJournal? {
        guard try !hasAcknowledgedCustomerDeletion(accountID: accountID) else {
            throw DastakCheckoutStorageError.customerDeleted
        }
        let url = file(accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 4_000_000 else { throw DastakCheckoutStorageError.invalidJournal }
        let journal = try JSONDecoder().decode(DastakCheckoutJournal.self, from: data)
        guard journal.accountID == accountID, journal.isValid else {
            throw DastakCheckoutStorageError.invalidJournal
        }
        return journal
    }

    func save(_ journal: DastakCheckoutJournal, replacing revision: UUID?) throws {
        guard journal.isValid else { throw DastakCheckoutStorageError.invalidJournal }
        guard try load(accountID: journal.accountID)?.revision == revision else {
            throw DastakCheckoutStorageError.changedJournal
        }
        let data = try JSONEncoder().encode(journal)
        guard data.count <= 4_000_000 else { throw DastakCheckoutStorageError.invalidJournal }
        try writeProtected(data, to: file(journal.accountID))
    }

    func hasAcknowledgedCustomerDeletion(accountID: UUID) throws -> Bool {
        let url = deletionMarker(accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url)
        guard data == Data(accountID.uuidString.lowercased().utf8) else {
            throw DastakCheckoutStorageError.invalidJournal
        }
        return true
    }

    func acknowledgeCustomerDeletion(accountID: UUID) throws {
        try writeProtected(Data(accountID.uuidString.lowercased().utf8), to: deletionMarker(accountID))
    }

    func removeAfterAcknowledgedCustomerDeletion(accountID: UUID) throws {
        guard try hasAcknowledgedCustomerDeletion(accountID: accountID) else {
            throw DastakCheckoutStorageError.unavailable
        }
        let url = file(accountID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        // Remove the receipt last. A failed cleanup can be resumed after relaunch.
        try FileManager.default.removeItem(at: deletionMarker(accountID))
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func deletionMarker(_ accountID: UUID) -> URL {
        directory.appendingPathComponent(accountID.uuidString.lowercased() + ".customer-deleted")
    }

    private func file(_ accountID: UUID) -> URL {
        directory.appendingPathComponent(accountID.uuidString.lowercased() + ".json")
    }
}
