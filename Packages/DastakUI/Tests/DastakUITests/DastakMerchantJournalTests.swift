import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

actor MerchantJournalTestStore: DastakMerchantJournalStorage {
    private var value: DastakMerchantJournalRecord?
    private var saveFails = false; private var removalFails = false; private var loadFails = false
    func failSave() { saveFails = true }; func failRemoval() { removalFails = true }; func failLoad() { loadFails = true }
    func load(_ accountID: UUID) throws -> DastakMerchantJournalRecord? {
        if loadFails { loadFails = false; throw URLError(.cannotOpenFile) }
        return value?.accountID == accountID ? value : nil
    }
    func replace(_ record: DastakMerchantJournalRecord?, accountID: UUID, expectedRevision: UUID?) throws {
        guard value?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        if record != nil && saveFails { saveFails = false; throw URLError(.cannotWriteToFile) }
        if record == nil && removalFails { removalFails = false; throw URLError(.cannotWriteToFile) }
        value = record
    }
}
actor MerchantJournalTestIdentity { var id = UUID(); func change() { id = UUID() } }

final class DastakMerchantJournalTests: XCTestCase {
    func testProtectedFileJournalIsAccountScopedAndCASChecked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DastakMerchantFileJournal(directory: directory); let accountID = UUID()
        let command = DastakMerchantRestaurantCommand(branchID: UUID(), key: IdempotencyKey(rawValue: UUID().uuidString)!, operation: .operating(isOpen: false, acceptingOrders: false, expectedVersion: 1))
        let record = DastakMerchantJournalRecord(accountID: accountID, command: .restaurant(command))
        try await store.replace(record, accountID: accountID, expectedRevision: nil)
        let loaded = try await store.load(accountID); XCTAssertEqual(loaded, record)
        let other = try await store.load(UUID()); XCTAssertNil(other)
        do { try await store.replace(nil, accountID: accountID, expectedRevision: nil); XCTFail("Stale clear accepted") } catch {}
        let file = directory.appendingPathComponent(accountID.uuidString.lowercased() + ".json")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        try await store.replace(nil, accountID: accountID, expectedRevision: record.revision)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testCorruptJournalIsPreservedInsteadOfSilentlyCleared() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let accountID = UUID(); let file = directory.appendingPathComponent(accountID.uuidString.lowercased() + ".json")
        try Data("corrupt fixture".utf8).write(to: file)
        let store = DastakMerchantFileJournal(directory: directory)
        do { _ = try await store.load(accountID); XCTFail("Corrupt journal accepted") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testInvalidMediaMetadataCannotBeSaved() {
        let command = DastakMerchantRestaurantCommand(branchID: UUID(), key: IdempotencyKey(rawValue: UUID().uuidString)!, operation: .media(entityType: "RESTAURANT_BRANCH_BANNER", entityID: UUID(), expectedVersion: 1, data: Data([1]), contentType: "image/jpeg", fileName: "bad\r\nname.jpg"))
        XCTAssertFalse(command.valid)
        XCTAssertFalse(DastakAdminCustomerRecoveryContract.phone("+919876543210\r\n"), "Combined CRLF must not bypass the shared contact validator")
    }
}
