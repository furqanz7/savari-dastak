import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantEarningsTests: XCTestCase {
    func testMerchantOrganizationsAreNotRiderAccountIDsAndAggregateSeparately() throws {
        let snapshot = try decode(royaltyFixture())
        XCTAssertTrue(snapshot.isValid)
        XCTAssertNotEqual(snapshot.subjects.first?.id, royaltyActor)
        let multiple = try decode(multiOrganizationFixture())
        XCTAssertTrue(multiple.isValid)
        XCTAssertEqual(multiple.balancePaise, 7_000)
        XCTAssertEqual(multiple.availablePaise, 10_000)
        XCTAssertEqual(multiple.negativeBalancePaise, 3_000)
    }
    func testRejectsRiderDuplicateOrganizationBadMoneyAndMismatchedAggregates() throws {
        for patch in ["rider", "duplicate", "negative", "currency", "aggregate", "min", "destination", "withdrawal", "entry"] {
            var object = royaltyFixture()
            var subjects = object["subjects"] as! [[String: Any]]
            switch patch {
            case "rider": subjects[0]["subjectType"] = "RIDER"
            case "duplicate": subjects.append(subjects[0])
            case "negative": subjects[0]["availablePaise"] = -1
            case "currency": subjects[0]["currency"] = "USD"
            case "aggregate": object["balancePaise"] = 123
            case "min": subjects[0]["balancePaise"] = Int.min
            case "destination": var destination = subjects[0]["payoutDestination"] as! [String: Any]; destination["version"] = 0; subjects[0]["payoutDestination"] = destination
            case "withdrawal": var withdrawals = subjects[0]["withdrawals"] as! [[String: Any]]; withdrawals[0]["status"] = "UNKNOWN"; subjects[0]["withdrawals"] = withdrawals
            default: var entries = subjects[0]["entries"] as! [[String: Any]]; entries.append(entries[0]); subjects[0]["entries"] = entries
            }
            object["subjects"] = subjects
            XCTAssertFalse(try decode(object).isValid, patch)
        }
    }
    func testRejectsEmptyOrOverflowedSnapshotsWithoutTrapping() throws {
        var empty = royaltyFixture(); empty["subjects"] = []
        XCTAssertFalse(try decode(empty).isValid)
        var object = multiOrganizationFixture()
        var subjects = object["subjects"] as! [[String: Any]]
        for index in subjects.indices {
            subjects[index]["balancePaise"] = Int.max; subjects[index]["availablePaise"] = Int.max; subjects[index]["negativeBalancePaise"] = 0
        }
        object["subjects"] = subjects
        XCTAssertFalse(try decode(object).isValid)
    }
    func testDTOIgnoresRawBankProviderAndCustomerExtras() throws {
        var object = royaltyFixture(); object["customerAddress"] = "PRIVATE_SECRET"
        var subjects = object["subjects"] as! [[String: Any]]
        var destination = subjects[0]["payoutDestination"] as! [String: Any]
        destination["accountNumber"] = "PRIVATE_SECRET"; destination["provider"] = "PRIVATE_SECRET"
        subjects[0]["payoutDestination"] = destination; object["subjects"] = subjects
        let snapshot = try decode(object)
        XCTAssertFalse(String(reflecting: snapshot).contains("PRIVATE_SECRET"))
    }
    func testMissingAvailabilityIsUnknownNotActive() throws {
        var object = royaltyFixture(); object.removeValue(forKey: "payoutAvailability")
        let snapshot = try decode(object)
        XCTAssertNil(snapshot.payoutAvailability)
        XCTAssertEqual(DastakMerchantEarningsPresentation.payoutStatus(snapshot, subject: snapshot.subjects[0]), "Payout availability could not be verified.")
    }
    func testUsesOnlyMerchantReadOperationWithoutActorOrganizationOrPayoutPayload() async throws {
        let functions = RoyaltyFunctions(), model = makeModel(functions)
        await model.load()
        XCTAssertTrue(model.current); XCTAssertNotNil(model.snapshot)
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].endpoint, "earnings")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[0].body) as? [String: String])
        XCTAssertEqual(body, ["operation": "merchantRoyaltyControlsSnapshot"])
    }
    func testOfflineRetainsExplicitlyStaleSnapshotAndSuccessfulRefreshClearsFailure() async {
        let functions = RoyaltyFunctions(), model = makeModel(functions)
        await model.load(); let checked = model.checkedAt
        await functions.enqueue(.offline); await model.load()
        XCTAssertNotNil(model.snapshot); XCTAssertFalse(model.current); XCTAssertNotNil(model.failure)
        XCTAssertEqual(model.checkedAt, checked); XCTAssertFalse(model.loading)
        await model.load()
        XCTAssertTrue(model.current); XCTAssertNil(model.failure)
    }
    func testDenialClearsAmountsTimestampAndOrganizationSelection() async {
        let functions = RoyaltyFunctions(), model = makeModel(functions)
        await model.load(); model.selectedOrganizationID = royaltyOrganization
        await functions.enqueue(.denied); await model.load()
        XCTAssertNil(model.snapshot); XCTAssertNil(model.checkedAt); XCTAssertNil(model.selectedOrganizationID)
        XCTAssertFalse(model.current); XCTAssertFalse(model.loading)
    }
    func testInvalidReplyNeverReplacesPreviouslyValidatedSnapshot() async throws {
        let functions = RoyaltyFunctions(), model = makeModel(functions)
        await model.load()
        var bad = royaltyFixture(); bad["availablePaise"] = -1
        await functions.enqueue(.data(try JSONSerialization.data(withJSONObject: bad))); await model.load()
        XCTAssertEqual(model.snapshot?.availablePaise, 10_000); XCTAssertFalse(model.current); XCTAssertNotNil(model.failure)
    }
    func testConcurrentRefreshIsCoalesced() async {
        let functions = RoyaltyFunctions(), model = makeModel(functions)
        await functions.holdNext()
        let read = Task { await model.load() }
        await functions.waitForStart(); await model.load(); await functions.release(); await read.value
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 1); XCTAssertTrue(model.current)
    }
    func testIdentityChangeDuringReadCannotPublishFinancialData() async {
        let functions = RoyaltyFunctions(), identity = MerchantJournalTestIdentity()
        let model = DastakMerchantEarningsModel(services: .init(functions: functions, accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }))
        await functions.holdNext()
        let read = Task { await model.load() }
        await functions.waitForStart(); await identity.change(); await functions.release(); await read.value
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.current); XCTAssertNotNil(model.failure)
    }
    func testChangedAccountCannotReuseCachedOrganizationBalances() async {
        let functions = RoyaltyFunctions(), identity = MerchantJournalTestIdentity()
        let model = DastakMerchantEarningsModel(services: .init(functions: functions, accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }))
        await model.load(); await identity.change(); await model.load()
        XCTAssertNil(model.snapshot); XCTAssertNil(model.checkedAt)
        let calls = await functions.calls; XCTAssertEqual(calls.count, 1)
    }
    func testInvalidationReleasesLoadingAndLateReadCannotOverwriteNewerState() async {
        let functions = RoyaltyFunctions(), model = makeModel(functions)
        await functions.holdNext()
        let old = Task { await model.load() }
        await functions.waitForStart(); model.invalidate()
        XCTAssertFalse(model.loading)
        await functions.enqueue(.denied); await model.load()
        await functions.release(); await old.value
        XCTAssertNil(model.snapshot); XCTAssertNotNil(model.failure); XCTAssertFalse(model.current)
    }
    func testUncooperativeReadTimesOutAndCanRefreshAgain() async {
        let functions = RoyaltyFunctions(), model = makeModel(functions, timeout: .milliseconds(60))
        await functions.holdNext()
        await model.load()
        XCTAssertFalse(model.loading); XCTAssertFalse(model.current); XCTAssertNotNil(model.failure)
        await model.load(); XCTAssertTrue(model.current)
        await functions.release()
    }
    func testOrganizationSelectionIsPresentationOnlyAndRemovedOrganizationResetsSelection() async throws {
        let functions = RoyaltyFunctions(), model = makeModel(functions)
        await functions.enqueue(.data(try JSONSerialization.data(withJSONObject: multiOrganizationFixture())))
        await model.load(); XCTAssertEqual(model.visibleSubjects.count, 2)
        let secondID = model.snapshot!.subjects[1].id; model.selectedOrganizationID = secondID
        XCTAssertEqual(model.visibleSubjects.map(\.id), [secondID])
        XCTAssertEqual(model.snapshot?.availablePaise, 10_000)
        await model.load(); XCTAssertNil(model.selectedOrganizationID); XCTAssertEqual(model.visibleSubjects.count, 1)
    }
    func testLedgerFiltersDoNotDoubleCountAdjustmentSubsetAndSearchOrderReferences() throws {
        let subject = try decode(royaltyFixture()).subjects[0]
        let all = DastakMerchantEarningsPresentation.entries(subject, filter: .all, query: "")
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(DastakMerchantEarningsPresentation.entries(subject, filter: .credits, query: "").count, 1)
        XCTAssertEqual(DastakMerchantEarningsPresentation.entries(subject, filter: .adjustments, query: "").count, 1)
        XCTAssertEqual(DastakMerchantEarningsPresentation.entries(subject, filter: .all, query: royaltyOrder.uuidString.lowercased()).count, 1)
        XCTAssertTrue(DastakMerchantEarningsPresentation.entries(subject, filter: .all, query: "no match").isEmpty)
    }
    func testPayoutAvailabilityAndEligibilityAreNotInferredFromPositiveBalance() throws {
        var object = royaltyFixture(); object["payoutAvailability"] = ["destinationRegistrationAvailable": false, "withdrawalExecutionAvailable": false]
        var snapshot = try decode(object)
        XCTAssertTrue(DastakMerchantEarningsPresentation.payoutStatus(snapshot, subject: snapshot.subjects[0]).contains("not available"))
        object["payoutAvailability"] = ["destinationRegistrationAvailable": true, "withdrawalExecutionAvailable": true]
        var subjects = object["subjects"] as! [[String: Any]]; subjects[0]["canWithdraw"] = false; object["subjects"] = subjects
        snapshot = try decode(object)
        XCTAssertTrue(DastakMerchantEarningsPresentation.payoutStatus(snapshot, subject: snapshot.subjects[0]).contains("not currently eligible"))
    }
    private func decode(_ object: [String: Any]) throws -> DastakMerchantRoyalty { try JSONDecoder().decode(DastakMerchantRoyalty.self, from: JSONSerialization.data(withJSONObject: object)) }
    private func makeModel(_ functions: RoyaltyFunctions, timeout: Duration = .seconds(12)) -> DastakMerchantEarningsModel {
        .init(services: .init(functions: functions, accountIDProvider: { royaltyActor }, objectUploader: { _, _, _, _, _ in }), timeout: timeout)
    }
}

private let royaltyActor = UUID(uuidString: "98000000-0000-4000-8000-000000000001")!
private let royaltyOrganization = UUID(uuidString: "98000000-0000-4000-8000-000000000002")!
private let royaltyOrder = UUID(uuidString: "98000000-0000-4000-8000-000000000003")!
private func royaltyFixture() -> [String: Any] {
    let entry: [String: Any] = ["id": "98000000-0000-4000-8000-000000000004", "type": "MERCHANT_ROYALTY_EARNING", "amountPaise": 12_000, "reason": "Order credit", "createdAt": "2026-10-17T10:00:00Z", "orderId": royaltyOrder.uuidString]
    let adjustment: [String: Any] = ["id": "98000000-0000-4000-8000-000000000005", "type": "ROYALTY_FAULT_ADJUSTMENT", "amountPaise": -2_000, "reason": "Returned goods", "createdAt": "2026-10-18T10:00:00Z"]
    let subject: [String: Any] = ["subjectType": "MERCHANT_ORGANIZATION", "subjectId": royaltyOrganization.uuidString, "currency": "INR", "balancePaise": 10_000, "availablePaise": 10_000, "negativeBalancePaise": 0, "lifetimeEarnedPaise": 20_000, "canWithdraw": true,
        "payoutDestination": ["id": "98000000-0000-4000-8000-000000000006", "type": "UPI", "displayLabel": "UPI • me***@bank", "status": "ACTIVE", "version": 1],
        "entries": [entry, adjustment], "adjustments": [adjustment],
        "withdrawals": [["id": "98000000-0000-4000-8000-000000000007", "amountPaise": 5_000, "currency": "INR", "status": "PROCESSING", "destination": ["type": "UPI", "displayLabel": "UPI • me***@bank"], "requestedAt": "2026-10-18T00:00:00Z", "version": 1]]]
    return ["currency": "INR", "balancePaise": 10_000, "availablePaise": 10_000, "negativeBalancePaise": 0, "lifetimeEarnedPaise": 20_000,
        "payoutAvailability": ["destinationRegistrationAvailable": false, "withdrawalExecutionAvailable": false], "subjects": [subject]]
}
private func multiOrganizationFixture() -> [String: Any] {
    var object = royaltyFixture(), subjects = object["subjects"] as! [[String: Any]]
    var other = subjects[0]; other["subjectId"] = "98000000-0000-4000-8000-000000000008"
    other["balancePaise"] = -3_000; other["availablePaise"] = 0; other["negativeBalancePaise"] = 3_000; other["lifetimeEarnedPaise"] = 5_000
    other["canWithdraw"] = false; other["entries"] = []; other["adjustments"] = []; other["withdrawals"] = []
    subjects.append(other); object["subjects"] = subjects
    object["balancePaise"] = 7_000; object["availablePaise"] = 10_000; object["negativeBalancePaise"] = 3_000; object["lifetimeEarnedPaise"] = 25_000
    return object
}
private actor RoyaltyFunctions: FunctionClient {
    struct Call: Sendable { let endpoint: String; let body: Data }
    enum Reply: Sendable { case data(Data), offline, denied }
    var calls: [Call] = []
    private var queue: [Reply] = []
    private var holding = false
    private var held: CheckedContinuation<Data, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func enqueue(_ reply: Reply) { queue.append(reply) }
    func holdNext() { holding = true }
    func waitForStart() async { if held == nil { await withCheckedContinuation { started = $0 } } }
    func release() { held?.resume(returning: try! JSONSerialization.data(withJSONObject: royaltyFixture())); held = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        calls.append(.init(endpoint: name, body: try JSONEncoder().encode(request)))
        let data: Data
        if holding {
            holding = false
            data = await withCheckedContinuation { held = $0; started?.resume(); started = nil }
        } else if !queue.isEmpty {
            switch queue.removeFirst() {
            case let .data(value): data = value
            case .offline: throw URLError(.notConnectedToInternet)
            case .denied: throw FunctionClientError.api(statusCode: 403, code: "access_denied", message: "Denied")
            }
        } else { data = try JSONSerialization.data(withJSONObject: royaltyFixture()) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
