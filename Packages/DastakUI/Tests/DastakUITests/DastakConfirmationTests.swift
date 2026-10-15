import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakConfirmationTests: XCTestCase {
    @MainActor
    func testLostReplyRelaunchReadsCommittedOrderWithoutAnotherWrite() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let account = UUID()
        let first = model(functions, storage, account)
        await first.restoreCartStorage()
        await functions.configure(loseReply: true, commitOnFailure: true)
        let result = await first.retryPayment(for: try confirmationOrder())
        XCTAssertFalse(result)
        let pending = try XCTUnwrap(first.pendingConfirmations.values.first)
        let relaunched = model(functions, storage, account)
        await relaunched.restoreCartStorage()
        XCTAssertEqual(relaunched.pendingConfirmations.values.first, pending)
        await relaunched.recoverConfirmation(orderID: pending.orderID)
        XCTAssertTrue(relaunched.pendingConfirmations.isEmpty)
        XCTAssertEqual(relaunched.activeV1Order?.status, .preparing)
        let keys = await functions.keys
        XCTAssertEqual(keys, [pending.key])
        XCTAssertNil(relaunched.activeV1Order?.paidAt)
    }

    @MainActor
    func testUncertainAttemptReplaysOriginalVersionAndKeyNotEditedSnapshot() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let account = UUID()
        let first = model(functions, storage, account)
        await first.restoreCartStorage()
        await functions.configure(loseReply: true)
        _ = await first.retryPayment(for: try confirmationOrder())
        let pending = try XCTUnwrap(first.pendingConfirmations.values.first)
        let second = model(functions, storage, account)
        await second.restoreCartStorage()
        await functions.configure()
        let result = await second.retryPayment(for: try confirmationOrder(version: 99))
        XCTAssertTrue(result)
        let keys = await functions.keys
        let versions = await functions.versions
        XCTAssertEqual(keys, [pending.key, pending.key])
        XCTAssertEqual(versions, [1, 1])
        XCTAssertTrue(second.pendingConfirmations.isEmpty)
    }

    @MainActor
    func testCancelledReservationOnlyReadNoConfirmation() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let customer = model(functions, storage, UUID())
        await customer.restoreCartStorage()
        await functions.configure(loseReply: true)
        _ = await customer.retryPayment(for: try confirmationOrder())
        await functions.configure(status: "CANCELLED_PREPAYMENT")
        let result = await customer.retryPayment(for: try confirmationOrder())
        XCTAssertFalse(result)
        XCTAssertTrue(customer.pendingConfirmations.isEmpty)
        XCTAssertEqual(customer.activeV1Order?.status, .cancelledPrepayment)
        XCTAssertNotNil(customer.v1OrderErrorMessage)
        let keys = await functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    @MainActor
    func testStorageFailureBeforeWriteBlocksConfirmation() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let customer = model(functions, storage, UUID())
        await customer.restoreCartStorage()
        storage.failOnWrite = 2
        let result = await customer.retryPayment(for: try confirmationOrder())
        XCTAssertFalse(result)
        XCTAssertFalse(customer.isCartStorageReady)
        let keys = await functions.keys
        XCTAssertTrue(keys.isEmpty)
    }

    @MainActor
    func testAcknowledgementFailureRetainsRecordAndRecoversAfterReload() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let customer = model(functions, storage, UUID())
        await customer.restoreCartStorage()
        storage.failOnWrite = 3
        let result = await customer.retryPayment(for: try confirmationOrder())
        XCTAssertFalse(result)
        XCTAssertEqual(customer.pendingConfirmations.count, 1)
        XCTAssertNil(customer.activeV1Order)
        XCTAssertFalse(customer.isCartStorageReady)
        await customer.restoreCartStorage(force: true)
        await customer.recoverConfirmation(orderID: confirmationID)
        XCTAssertTrue(customer.pendingConfirmations.isEmpty)
        let keys = await functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    @MainActor
    func testReadFailureAfterCommitKeepsRecoveryAndNeverPublishesOldReply() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let customer = model(functions, storage, UUID())
        await customer.restoreCartStorage()
        await functions.configure(failReads: true)
        let result = await customer.retryPayment(for: try confirmationOrder())
        XCTAssertFalse(result)
        XCTAssertEqual(customer.pendingConfirmations.count, 1)
        XCTAssertNil(customer.activeV1Order)
        await functions.configure(status: "PREPARING")
        await customer.recoverConfirmation(orderID: confirmationID)
        XCTAssertEqual(customer.activeV1Order?.status, .preparing)
        XCTAssertTrue(customer.pendingConfirmations.isEmpty)
    }

    @MainActor
    func testAccountIsolationAndBasketWritesPreservePendingConfirmation() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let account = UUID()
        let customer = model(functions, storage, account)
        await customer.restoreCartStorage()
        await functions.configure(loseReply: true)
        _ = await customer.retryPayment(for: try confirmationOrder())
        customer.clearCart() // Journal write must not erase a pending confirmation.
        let other = model(functions, storage, UUID())
        await other.restoreCartStorage()
        XCTAssertTrue(other.pendingConfirmations.isEmpty)
        let same = model(functions, storage, account)
        await same.restoreCartStorage()
        XCTAssertEqual(same.pendingConfirmations.count, 1)
        let keys = await functions.keys
        XCTAssertEqual(keys.count, 1) // Restoring never auto-confirms.
    }

    func testVersionOneJournalCompatibilityAndInvalidConfirmationRejection() throws {
        let old = DastakCheckoutJournal(accountID: UUID(), baskets: .init(), pending: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "confirmations")
        let decoded = try JSONDecoder().decode(DastakCheckoutJournal.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.isValid)
        XCTAssertNil(decoded.confirmations)
        let invalid = DastakPendingConfirmation(orderID: confirmationID, expectedVersion: 0, key: IdempotencyKey(rawValue: UUID().uuidString)!)
        var journal = old
        journal.confirmations = [invalid]
        XCTAssertFalse(journal.isValid)
        let valid = DastakPendingConfirmation(orderID: confirmationID, expectedVersion: 1, key: IdempotencyKey(rawValue: UUID().uuidString)!)
        journal.confirmations = [valid, valid]
        XCTAssertFalse(journal.isValid)
    }

    @MainActor
    func testDefinitiveVersionRejectionRequiresReviewNotAutomaticNewCommand() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let customer = model(functions, storage, UUID())
        await customer.restoreCartStorage()
        await functions.rejectVersion()
        let result = await customer.retryPayment(for: try confirmationOrder())
        XCTAssertFalse(result)
        XCTAssertTrue(customer.pendingConfirmations.isEmpty)
        XCTAssertEqual(customer.activeV1Order?.version, 2)
        XCTAssertTrue(customer.v1OrderErrorMessage?.contains("Review") == true)
        let keys = await functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    @MainActor
    func testInFlightDuplicateAndAccountSwitchCannotPublishAnotherAccountOrder() async throws {
        let functions = ConfirmationFunctions()
        let storage = ConfirmationStorage()
        let account = ConfirmationAccount()
        let original = account.id
        let customer = DastakCustomerModel(functions: functions, accountIDProvider: { await account.id }, checkoutJournalStorage: storage, enforcesAreaChecks: false)
        await customer.restoreCartStorage()
        await functions.holdCommit()
        let first = Task { await customer.retryPayment(for: try confirmationOrder()) }
        await functions.waitForCommit()
        let second = await customer.retryPayment(for: try confirmationOrder())
        XCTAssertFalse(second)
        account.id = UUID()
        await customer.restoreCartStorage(force: true) // In-flight operations must not swap journals.
        await functions.finishCommit()
        let result = try await first.value
        XCTAssertFalse(result)
        XCTAssertNil(customer.activeV1Order)
        XCTAssertTrue(customer.v1Orders.isEmpty)
        XCTAssertEqual(try storage.load(accountID: original)?.confirmations?.count, 1)
        await customer.restoreCartStorage(force: true)
        XCTAssertTrue(customer.pendingConfirmations.isEmpty)
        let keys = await functions.keys
        XCTAssertEqual(keys.count, 1)
    }

    func testPresentationDoesNotTreatConfirmationOrWorkflowPaidAsCollection() throws {
        let committed = try confirmationOrder(status: "PAID", committed: true)
        XCTAssertEqual(DastakPaymentActivity.title(committed), "Confirmed — pay at delivery")
        let collected = try confirmationOrder(status: "DELIVERED", committed: true, collected: true, method: "CASH")
        XCTAssertEqual(DastakPaymentActivity.title(collected), "Collected by cash")
        let upi = try confirmationOrder(status: "DELIVERED", committed: true, collected: true, method: "UPI")
        XCTAssertEqual(DastakPaymentActivity.title(upi), "Collected by UPI")
        let cancelled = try confirmationOrder(status: "CANCELLED", committed: true)
        XCTAssertEqual(DastakPaymentActivity.title(cancelled), "No payment collection recorded")
        let legacy = try confirmationOrder(status: "PAID", launch: false)
        XCTAssertNil(DastakPaymentActivity.title(legacy))
        XCTAssertEqual(DastakPaymentActivity.title(try confirmationOrder(launch: false, paid: true)), "Payment recorded")
    }

    @MainActor
    private func model(_ functions: ConfirmationFunctions, _ storage: ConfirmationStorage, _ account: UUID) -> DastakCustomerModel {
        DastakCustomerModel(functions: functions, accountIDProvider: { account }, checkoutJournalStorage: storage, enforcesAreaChecks: false)
    }
}

private let confirmationID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

private func confirmationOrder(status: String = "AWAITING_PAYMENT", version: Int = 1,
                               committed: Bool = false, collected: Bool = false,
                               method: String = "UPI", launch: Bool = true, paid: Bool = false) throws -> DastakV1OrderSnapshot {
    var object: [String: Any] = [
        "id": confirmationID.uuidString, "displayOrderNumber": "TEST-1", "orderType": "RETAIL_ONLY",
        "status": status, "version": version, "createdAt": "2026-10-10T00:00:00Z", "updatedAt": "2026-10-10T00:00:01Z",
        "price": ["snapshotKind": "SECURED", "subtotalPaise": 10000, "deliveryFeePaise": 1500,
                  "platformFeePaise": 230, "discountPaise": 0, "taxPaise": 0, "totalPaise": 11730, "currencyCode": "INR"], "lines": []
    ]
    if launch {
        var payment: [String: Any] = ["optionLabel": "Pay via UPI/Cash on Delivery", "state": collected ? "PAYMENT_COLLECTED" : committed ? "PAYMENT_DUE_AT_DELIVERY" : "READY_TO_CONFIRM",
            "amountPaise": 11730, "currencyCode": "INR", "reservationSecondsRemaining": 600,
            "reservationState": committed ? "COMMITTED" : "ACTIVE", "canCommit": !committed,
            "noChargeNow": true, "payAtDoorstep": true]
        if committed { payment["committedAt"] = "2026-10-10T00:00:02Z" }
        if collected { payment["collectedAt"] = "2026-10-10T01:00:00Z"; payment["collectionMethod"] = method }
        object["launchPayment"] = payment
    }
    if paid { object["paidAt"] = "2026-10-10T01:00:00Z" }
    return try JSONDecoder().decode(DastakV1OrderSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
}

private actor ConfirmationFunctions: FunctionClient {
    var keys: [IdempotencyKey] = []
    var versions: [Int] = []
    private var loseReply = false
    private var commitOnFailure = false
    private var failReads = false
    private var committed = false
    private var status = "AWAITING_PAYMENT"
    private var reject = false
    private var hold = false
    private var started: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func rejectVersion() { reject = true }
    func holdCommit() { hold = true }
    func waitForCommit() async {
        if release != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishCommit() { release?.resume(); release = nil }

    func configure(loseReply: Bool = false, commitOnFailure: Bool = false, failReads: Bool = false, status: String? = nil) {
        self.loseReply = loseReply; self.commitOnFailure = commitOnFailure; self.failReads = failReads
        if let status { self.status = status }
    }

    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Input, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        guard name == "dastak-v1-orders" else { throw FunctionClientError.invalidResponse }
        switch body["operation"] as? String {
        case "commitLaunchPayment":
            keys.append(idempotencyKey)
            versions.append(try XCTUnwrap(body["expectedVersion"] as? Int))
            if reject { throw FunctionClientError.api(statusCode: 409, code: "stale_version", message: "Changed") }
            if hold {
                await withCheckedContinuation {
                    release = $0
                    started?.resume(); started = nil
                }
            }
            if !loseReply || commitOnFailure { committed = true; status = "PREPARING" }
            if loseReply { throw URLError(.timedOut) }
        case "get":
            if failReads { throw URLError(.notConnectedToInternet) }
        default: throw FunctionClientError.invalidResponse
        }
        let order = try confirmationOrder(status: status, version: committed ? 3 : reject ? 2 : 1, committed: committed)
        return try JSONDecoder().decode(Result.self, from: JSONEncoder().encode(order))
    }
}

@MainActor
private final class ConfirmationAccount { var id = UUID() }

@MainActor
private final class ConfirmationStorage: DastakCheckoutJournalStorage {
    var failOnWrite: Int?
    private var writes = 0
    private var records: [UUID: DastakCheckoutJournal] = [:]
    func load(accountID: UUID) throws -> DastakCheckoutJournal? { records[accountID] }
    func save(_ journal: DastakCheckoutJournal, replacing revision: UUID?) throws {
        writes += 1
        guard writes != failOnWrite, records[journal.accountID]?.revision == revision, journal.isValid else {
            throw DastakCheckoutStorageError.unavailable
        }
        records[journal.accountID] = journal
    }
}
