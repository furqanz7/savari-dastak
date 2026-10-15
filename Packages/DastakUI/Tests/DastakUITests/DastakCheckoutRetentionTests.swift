import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakCheckoutRetentionTests: XCTestCase {
    func testMigrationRemovesOnlyOwnLegacyCacheAfterJournalIsSaved() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let other = UUID()
        let legacy = DastakBasketStore(defaults: fixture.defaults)
        let baskets = try fixture.baskets()
        legacy.save(baskets, accountID: fixture.account)
        legacy.save(baskets, accountID: other)
        let model = fixture.model()
        await model.restoreCartStorage()
        XCTAssertEqual(model.baskets, baskets)
        XCTAssertEqual(try fixture.storage.load(accountID: fixture.account)?.baskets, baskets)
        XCTAssertTrue(legacy.load(accountID: fixture.account)[.grocery].isEmpty)
        XCTAssertEqual(legacy.load(accountID: other), baskets)
    }

    func testFailedMigrationKeepsLegacyBasketForRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let baskets = try fixture.baskets()
        let legacy = DastakBasketStore(defaults: fixture.defaults)
        legacy.save(baskets, accountID: fixture.account)
        fixture.storage.failSave = true
        let model = fixture.model()
        await model.restoreCartStorage()
        XCTAssertFalse(model.isCartStorageReady)
        XCTAssertEqual(legacy.load(accountID: fixture.account), baskets)
        fixture.storage.failSave = false
        await model.restoreCartStorage(force: true)
        XCTAssertEqual(model.baskets, baskets)
        XCTAssertTrue(legacy.load(accountID: fixture.account)[.grocery].isEmpty)
    }

    func testConfirmedDeletionClearsOnlyCustomerFilesAndPreferences() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        model.addToCart(try fixture.product())
        let other = UUID()
        let otherRecord = DastakCheckoutJournal(accountID: other, baskets: try fixture.baskets(), pending: [])
        try fixture.storage.save(otherRecord, replacing: nil)
        let prefix = "dastak.customer.\(fixture.account.uuidString.lowercased())."
        UserDefaults.standard.set("sample", forKey: prefix + "discoveryLocation")
        UserDefaults.standard.set("retain", forKey: prefix + "unrelated")
        defer {
            UserDefaults.standard.removeObject(forKey: prefix + "discoveryLocation")
            UserDefaults.standard.removeObject(forKey: prefix + "unrelated")
        }
        try await model.deleteAccount()
        XCTAssertNil(try fixture.storage.load(accountID: fixture.account))
        XCTAssertEqual(try fixture.storage.load(accountID: other), otherRecord)
        XCTAssertNil(UserDefaults.standard.object(forKey: prefix + "discoveryLocation"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: prefix + "unrelated"), "retain")
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        XCTAssertFalse(model.isCartStorageReady)
        model.addToCart(try fixture.product())
        await model.restoreCartStorage(force: true)
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        let keys = await fixture.functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    func testUnknownDeletionOutcomeKeepsJournalAndSameKeyForRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        model.addToCart(try fixture.product())
        let original = try fixture.storage.load(accountID: fixture.account)
        await fixture.functions.setOffline(true)
        do { try await model.deleteAccount(); XCTFail("Expected unknown outcome") }
        catch let error as DastakCustomerDeletionError {
            XCTAssertTrue(error.localizedDescription.contains("could not confirm"))
        }
        XCTAssertEqual(try fixture.storage.load(accountID: fixture.account), original)
        XCTAssertFalse(try fixture.storage.hasAcknowledgedCustomerDeletion(accountID: fixture.account))
        XCTAssertTrue(model.isCartStorageReady)
        await fixture.functions.setOffline(false)
        try await model.deleteAccount()
        let keys = await fixture.functions.keys
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1])
    }

    func testCleanupFailureRetainsReceiptAndRetriesWithoutDeletingAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        model.addToCart(try fixture.product())
        fixture.storage.failCleanup = true
        do { try await model.deleteAccount(); XCTFail("Expected cleanup failure") }
        catch let error as DastakCustomerDeletionError {
            XCTAssertTrue(error.localizedDescription.contains("was deleted"))
        }
        XCTAssertTrue(try fixture.storage.hasAcknowledgedCustomerDeletion(accountID: fixture.account))
        XCTAssertThrowsError(try fixture.storage.load(accountID: fixture.account))
        XCTAssertFalse(model.isCartStorageReady)
        fixture.storage.failCleanup = false
        try await model.deleteAccount()
        XCTAssertFalse(try fixture.storage.hasAcknowledgedCustomerDeletion(accountID: fixture.account))
        XCTAssertNil(try fixture.storage.load(accountID: fixture.account))
        let keys = await fixture.functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    func testRelaunchResumesAcknowledgedCleanupInsteadOfRestoringOldBaskets() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        model.addToCart(try fixture.product())
        fixture.storage.failCleanup = true
        do { try await model.deleteAccount(); XCTFail("Expected cleanup failure") } catch {}
        DastakBasketStore(defaults: fixture.defaults).save(try fixture.baskets(), accountID: fixture.account)
        fixture.storage.failCleanup = false
        let relaunched = fixture.model()
        await relaunched.restoreCartStorage()
        XCTAssertFalse(relaunched.isCartStorageReady)
        XCTAssertTrue(relaunched.baskets[.grocery].isEmpty)
        XCTAssertNil(try fixture.storage.load(accountID: fixture.account))
        XCTAssertTrue(DastakBasketStore(defaults: fixture.defaults).load(accountID: fixture.account)[.grocery].isEmpty)
        let keys = await fixture.functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    func testReceiptWriteFailureCanRetryCleanupWithoutAnotherServerCommand() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        model.addToCart(try fixture.product())
        fixture.storage.failAcknowledgement = true
        do { try await model.deleteAccount(); XCTFail("Expected receipt failure") } catch {}
        XCTAssertFalse(model.isCartStorageReady)
        fixture.storage.failAcknowledgement = false
        try await model.deleteAccount()
        XCTAssertNil(try fixture.storage.load(accountID: fixture.account))
        let keys = await fixture.functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    func testPendingSubmissionOrConfirmationBlocksDeletionWithoutDiscardingRecords() async throws {
        for confirmation in [false, true] {
            let fixture = try Fixture()
            defer { fixture.clean() }
            let baskets = try fixture.baskets()
            let submission = DastakV1OrderSubmission(
                deliveryAddress: .init(label: "Sample", line1: "Sample address", line2: nil, landmark: nil,
                                       city: nil, state: nil, postalCode: nil, latitude: 12, longitude: 78, instructions: nil),
                recipient: .init(name: "Sample", phoneNumber: "+919999999999"), lines: baskets[.grocery].orderLines
            )
            let record = DastakCheckoutJournal(accountID: fixture.account, baskets: baskets,
                pending: confirmation ? [] : [.init(service: .grocery, key: .init(rawValue: UUID().uuidString)!, submission: submission)],
                confirmations: confirmation ? [.init(orderID: UUID(), expectedVersion: 1, key: .init(rawValue: UUID().uuidString)!)] : [])
            try fixture.storage.save(record, replacing: nil)
            let model = fixture.model()
            await model.restoreCartStorage()
            do { try await model.deleteAccount(); XCTFail("Expected recovery blocker") }
            catch let error as DastakCustomerDeletionError {
                XCTAssertTrue(error.localizedDescription.contains("Recover"))
            }
            XCTAssertEqual(try fixture.storage.load(accountID: fixture.account), record)
            let keys = await fixture.functions.keys
            XCTAssertTrue(keys.isEmpty)
        }
    }

    func testRelaunchAfterReceiptWriteFailureReusesOriginalDeletionKey() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        model.addToCart(try fixture.product())
        fixture.storage.failAcknowledgement = true
        do { try await model.deleteAccount(); XCTFail("Expected receipt failure") } catch {}
        fixture.storage.failAcknowledgement = false
        let relaunched = fixture.model()
        await relaunched.restoreCartStorage()
        try await relaunched.deleteAccount()
        let keys = await fixture.functions.keys
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertNil(try fixture.storage.load(accountID: fixture.account))
    }

    func testPendingRecordAddedAfterRestoreStillBlocksDeletion() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        let old = try XCTUnwrap(fixture.storage.load(accountID: fixture.account))
        let newer = DastakCheckoutJournal(accountID: fixture.account, baskets: old.baskets, pending: [],
            confirmations: [.init(orderID: UUID(), expectedVersion: 1, key: .init(rawValue: UUID().uuidString)!)])
        try fixture.storage.save(newer, replacing: old.revision)
        do { try await model.deleteAccount(); XCTFail("Expected stored recovery blocker") } catch {}
        XCTAssertEqual(try fixture.storage.load(accountID: fixture.account), newer)
        let keys = await fixture.functions.keys
        XCTAssertTrue(keys.isEmpty)
    }

    func testKnownServerRejectionKeepsRecoveryAndReauthenticationError() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        model.addToCart(try fixture.product())
        let original = try fixture.storage.load(accountID: fixture.account)
        await fixture.functions.reject()
        do { try await model.deleteAccount(); XCTFail("Expected reauthentication rejection") }
        catch let FunctionClientError.api(status, code, _) {
            XCTAssertEqual(status, 403)
            XCTAssertEqual(code, "reauthentication_required")
        }
        XCTAssertEqual(try fixture.storage.load(accountID: fixture.account), original)
        XCTAssertTrue(model.isCartStorageReady)
        XCTAssertFalse(try fixture.storage.hasAcknowledgedCustomerDeletion(accountID: fixture.account))
    }

    func testDeletionInFlightBlocksBasketEditsDuplicateDeletionAndCheckout() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        await model.restoreCartStorage()
        model.addToCart(try fixture.product())
        await fixture.functions.hold()
        let deletion = Task { try await model.deleteAccount() }
        await fixture.functions.waitUntilHeld()
        XCTAssertFalse(model.isCartStorageReady)
        model.addToCart(try fixture.product())
        XCTAssertEqual(model.cart.itemCount, 1)
        let submitted = await model.submitV1Order()
        XCTAssertFalse(submitted)
        do { try await model.deleteAccount(); XCTFail("Expected busy blocker") } catch {}
        await fixture.functions.release()
        try await deletion.value
        let keys = await fixture.functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    func testFileCleanupRequiresAcknowledgementAndCanRemoveCorruptDeletedJournal() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let record = DastakCheckoutJournal(accountID: fixture.account, baskets: try fixture.baskets(), pending: [])
        try fixture.storage.save(record, replacing: nil)
        XCTAssertThrowsError(try fixture.storage.removeAfterAcknowledgedCustomerDeletion(accountID: fixture.account))
        let file = fixture.directory.appendingPathComponent(fixture.account.uuidString.lowercased() + ".json")
        try Data("corrupt".utf8).write(to: file)
        try fixture.storage.acknowledgeCustomerDeletion(accountID: fixture.account)
        XCTAssertThrowsError(try fixture.storage.save(record, replacing: record.revision))
        try fixture.storage.removeAfterAcknowledgedCustomerDeletion(accountID: fixture.account)
        XCTAssertNil(try fixture.storage.load(accountID: fixture.account))
    }

    @MainActor
    private struct Fixture {
        let account = UUID()
        let directory: URL
        let defaults: UserDefaults
        let suite: String
        let storage: RetentionStorage
        let functions = DeletionFunctions()

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("dastak-retention-\(UUID())", isDirectory: true)
            suite = "dastak-retention-\(UUID())"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            storage = RetentionStorage(directory: directory)
        }

        func clean() {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
            UserDefaults.standard.removeObject(forKey: "dastak.customer.\(account.uuidString.lowercased()).accountDeletionIdempotencyKey")
        }

        func model() -> DastakCustomerModel {
            let id = account
            return DastakCustomerModel(functions: functions, accountIDProvider: { id }, basketDefaults: defaults,
                                       checkoutJournalStorage: storage, enforcesAreaChecks: false)
        }

        func baskets() throws -> DastakCustomerBaskets {
            var value = DastakCustomerBaskets()
            value[.grocery].add(try product())
            return value
        }

        func product() throws -> DastakV1CatalogueSKU {
            try JSONDecoder().decode(DastakV1CatalogueSKU.self, from: Data("""
            {"id":"11111111-1111-4111-8111-111111111111","categoryId":"22222222-2222-4222-8222-222222222222",
             "subcategoryId":"33333333-3333-4333-8333-333333333333","name":"Sample","slug":"sample",
             "packSize":"1 unit","listPricePaise":100,"sellingPricePaise":100,"currencyCode":"INR","logisticsAttributes":{}}
            """.utf8))
        }
    }
}

@MainActor
private final class RetentionStorage: DastakCheckoutJournalStorage {
    let base: DastakFileCheckoutJournalStorage
    var failSave = false, failAcknowledgement = false, failCleanup = false
    init(directory: URL) { base = .init(directory: directory) }
    func load(accountID: UUID) throws -> DastakCheckoutJournal? { try base.load(accountID: accountID) }
    func save(_ journal: DastakCheckoutJournal, replacing revision: UUID?) throws {
        if failSave { throw DastakCheckoutStorageError.unavailable }
        try base.save(journal, replacing: revision)
    }
    func hasAcknowledgedCustomerDeletion(accountID: UUID) throws -> Bool {
        try base.hasAcknowledgedCustomerDeletion(accountID: accountID)
    }
    func acknowledgeCustomerDeletion(accountID: UUID) throws {
        if failAcknowledgement { throw DastakCheckoutStorageError.unavailable }
        try base.acknowledgeCustomerDeletion(accountID: accountID)
    }
    func removeAfterAcknowledgedCustomerDeletion(accountID: UUID) throws {
        if failCleanup { throw DastakCheckoutStorageError.unavailable }
        try base.removeAfterAcknowledgedCustomerDeletion(accountID: accountID)
    }
}

private actor DeletionFunctions: FunctionClient {
    private(set) var keys: [String] = []
    private var offline = false, shouldHold = false, rejection = false
    private var blocked: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func setOffline(_ value: Bool) { offline = value }
    func reject() { rejection = true }
    func hold() { shouldHold = true }
    func waitUntilHeld() async {
        if blocked != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { blocked?.resume(); blocked = nil }
    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Input, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        guard name == "account-profile", body["operation"] as? String == "delete" else {
            throw FunctionClientError.invalidResponse
        }
        XCTAssertEqual(body["persona"] as? String, "CUSTOMER")
        keys.append(idempotencyKey.rawValue)
        if shouldHold {
            shouldHold = false
            await withCheckedContinuation { blocked = $0; started?.resume(); started = nil }
        }
        if offline { throw URLError(.timedOut) }
        if rejection { throw FunctionClientError.api(statusCode: 403, code: "reauthentication_required", message: "Verify again") }
        return try JSONDecoder().decode(Result.self, from: Data("{\"deleted\":true}".utf8))
    }
}
