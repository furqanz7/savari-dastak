import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor final class DastakDeliveryEarningsTests: XCTestCase {
    func testAmountParsingDoesNotRoundExtraDecimalsOrAcceptNegativeValues() {
        XCTAssertEqual(DastakDeliveryEarningsView.paise("125.50"), 12_550)
        XCTAssertEqual(DastakDeliveryEarningsView.paise(" 1.2 "), 120)
        for invalid in ["-1", "0", "1.001", "1e4", "NaN", "", "₹100"] { XCTAssertNil(DastakDeliveryEarningsView.paise(invalid)) }
    }
    func testSnapshotRejectsOtherActorAndNegativeAvailableBalance() throws {
        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(DastakDeliveryEarnings.self, from: earningsFixture())
        XCTAssertTrue(snapshot.isValid(for: earningsActor))
        XCTAssertFalse(snapshot.isValid(for: UUID()))
        let negative = earningsFixture().replacingForEarnings("\"availablePaise\":10000", "\"availablePaise\":-1")
        XCTAssertFalse(try decoder.decode(DastakDeliveryEarnings.self, from: negative).isValid(for: earningsActor))
    }
    func testWithdrawalRetainsExactPayloadAndKeyAfterTimeoutAndRelaunch() async throws {
        let functions = EarningsFunctions(); let store = EarningsStore()
        let services = MarketplaceAuthenticatedServices(functions: functions, accountIDProvider: { earningsActor }, objectUploader: { _, _, _, _, _ in })
        let model = DastakDeliveryEarningsModel(services: services, storage: store)
        await model.load()
        await model.withdraw(subject: try XCTUnwrap(model.snapshot?.subjects.first), amountPaise: 5_000)
        XCTAssertEqual(model.pending?.request.amountPaise, 5_000)
        let restored = DastakDeliveryEarningsModel(services: services, storage: store); await restored.load()
        await restored.withdraw(subject: try XCTUnwrap(restored.snapshot?.subjects.first), amountPaise: 9_000)
        await functions.allowPayout()
        await restored.recover()
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].0, writes[1].0)
        XCTAssertEqual(writes[0].1, writes[1].1)
        XCTAssertNil(restored.pending)
    }
    func testOverBalanceAndUnavailableWithdrawalsNeverReachTransport() async throws {
        let functions = EarningsFunctions(); let model = DastakDeliveryEarningsModel(services: .init(functions: functions, accountIDProvider: { earningsActor }, objectUploader: { _, _, _, _, _ in }), storage: EarningsStore())
        await model.load()
        await model.withdraw(subject: try XCTUnwrap(model.snapshot?.subjects.first), amountPaise: 10_001)
        await model.withdraw(subject: try XCTUnwrap(model.snapshot?.subjects.first), amountPaise: 0)
        let writes = await functions.writes
        XCTAssertTrue(writes.isEmpty)
    }
}
private let earningsActor = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private actor EarningsStore: DastakDeliveryPayoutStorage {
    var value: DastakDeliveryPayoutCommand?
    func load(_ accountID: UUID) -> DastakDeliveryPayoutCommand? { value?.accountID == accountID ? value : nil }
    func replace(_ command: DastakDeliveryPayoutCommand?, accountID: UUID, expectedRevision: UUID?) throws {
        guard value?.revision == expectedRevision else { throw DastakDeliveryJournalError.changed }
        value = command
    }
}
private actor EarningsFunctions: FunctionClient {
    var writes: [(Data, IdempotencyKey)] = []
    var successful = false
    func allowPayout() { successful = true }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        if object["operation"] as? String == "deliveryRoyaltySnapshot" { return try JSONDecoder().decode(Response.self, from: earningsFixture()) }
        writes.append((body, idempotencyKey))
        guard successful else { throw URLError(.timedOut) }
        return try JSONDecoder().decode(Response.self, from: Data(#"{"withdrawalId":"22222222-2222-4222-8222-222222222222","amountPaise":5000,"status":"PROCESSING"}"#.utf8))
    }
}
private func earningsFixture() -> Data {
    Data("""
    {"currency":"INR","balancePaise":10000,"availablePaise":10000,"negativeBalancePaise":0,"lifetimeEarnedPaise":20000,
    "payoutAvailability":{"destinationRegistrationAvailable":true,"withdrawalExecutionAvailable":true},
    "subjects":[{"subjectType":"RIDER","subjectId":"\(earningsActor)","currency":"INR","balancePaise":10000,"availablePaise":10000,"negativeBalancePaise":0,"lifetimeEarnedPaise":20000,"canWithdraw":true,
    "payoutDestination":{"id":"33333333-3333-4333-8333-333333333333","type":"UPI","displayLabel":"UPI • ri***@bank","status":"ACTIVE","version":1},"entries":[],"adjustments":[],"withdrawals":[]}]}
    """.utf8)
}
private extension Data {
    func replacingForEarnings(_ old: String, _ new: String) -> Data { Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8) }
}
