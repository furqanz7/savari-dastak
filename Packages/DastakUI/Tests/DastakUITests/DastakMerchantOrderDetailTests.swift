import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantOrderDetailTests: XCTestCase {
    private let target = DastakMerchantDetailTarget(kind: .fulfilment, id: detailFixtureID, branchID: detailFixtureBranch)
    func testClientUsesMerchantEndpointWithExactScopeAndNoActorOverride() async throws {
        let functions = DetailFunctions(), client = SupabaseDastakMerchantOrderDetailClient(functions: functions)
        let result = try await client.get(target, key: IdempotencyKey(rawValue: UUID().uuidString)!)
        XCTAssertTrue(result.validates(target)); XCTAssertEqual(result.records.first?.lines.first?.selection?.options.first?.name, "Less sugar")
        let calls = await functions.calls
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(calls.first)) as? [String: Any])
        XCTAssertEqual(body["operation"] as? String, "merchantOrderDetail")
        XCTAssertEqual(body["branchId"] as? String, target.branchID.uuidString)
        XCTAssertEqual(body["targetId"] as? String, target.id.uuidString)
        XCTAssertNil(body["actorId"]); XCTAssertNil(body["customerId"])
    }
    func testMismatchedTargetBranchMissingRecordAndNegativeValueFailClosed() async throws {
        for patch in ["branch", "target", "missing", "negative"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: detailFixture()) as? [String: Any])
            switch patch {
            case "branch": object["branch"] = ["id": UUID().uuidString, "displayName": "Another Store"]
            case "target": object["target"] = ["id": UUID().uuidString, "branchId": target.branchID.uuidString, "kind": target.kind.rawValue]
            case "missing": object["records"] = []
            default:
                var records = object["records"] as! [[String: Any]]; records[0]["productSubtotalPaise"] = -1; object["records"] = records
            }
            let functions = DetailFunctions(); await functions.enqueue(.data(try JSONSerialization.data(withJSONObject: object)))
            do { _ = try await SupabaseDastakMerchantOrderDetailClient(functions: functions).get(target, key: IdempotencyKey(rawValue: UUID().uuidString)!); XCTFail("Accepted \(patch)") } catch {}
        }
    }
    func testReadOnlyDTOIgnoresUnexpectedCodesContactsAndCustomerLocation() async throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: detailFixture()) as? [String: Any])
        object["customerAddress"] = "PRIVATE_SECRET"; object["pickupCode"] = "PRIVATE_SECRET"
        var records = object["records"] as! [[String: Any]]
        records[0]["delivery"] = ["riderName": "Rider", "pickupCode": "PRIVATE_SECRET", "riderPhone": "PRIVATE_SECRET"]
        object["records"] = records
        let value = try JSONDecoder().decode(DastakMerchantOrderDetail.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(String(reflecting: value).contains("PRIVATE_SECRET"))
    }
    func testNetworkFailureRetainsReadOnlySnapshotButAuthorizationFailureClearsIt() async {
        let functions = DetailFunctions(), model = makeModel(functions)
        await model.refresh(); XCTAssertNotNil(model.detail)
        await functions.enqueue(.offline); await model.refresh()
        XCTAssertNotNil(model.detail); XCTAssertNotNil(model.failure); XCTAssertFalse(model.loading)
        await functions.enqueue(.denied); await model.refresh()
        XCTAssertNil(model.detail); XCTAssertNil(model.checkedAt); XCTAssertFalse(model.loading)
    }
    func testIdentityChangeDuringReadCannotPublishPreviousActorsDetails() async {
        let functions = DetailFunctions(), identity = MerchantJournalTestIdentity()
        let model = DastakMerchantOrderDetailModel(target: target, services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }))
        await functions.holdNext()
        let read = Task { await model.refresh() }
        await functions.waitForStart(); await identity.change(); await functions.release(); await read.value
        XCTAssertNil(model.detail); XCTAssertNotNil(model.failure); XCTAssertFalse(model.loading)
    }
    func testConcurrentRefreshDoesNotDuplicateRequest() async {
        let functions = DetailFunctions(), model = makeModel(functions)
        await functions.holdNext()
        let read = Task { await model.refresh() }
        await functions.waitForStart(); await model.refresh(); await functions.release(); await read.value
        let calls = await functions.calls; XCTAssertEqual(calls.count, 1); XCTAssertNotNil(model.detail)
    }
    private func makeModel(_ functions: DetailFunctions) -> DastakMerchantOrderDetailModel {
        let account = UUID()
        return .init(target: target, services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { account }, objectUploader: { _, _, _, _, _ in }))
    }
}
private actor DetailFunctions: FunctionClient {
    enum Reply: Sendable { case data(Data), offline, denied }
    var calls: [Data] = []
    private var results: [Reply] = [], holding = false
    private var continuation: CheckedContinuation<Data, Never>?, started: CheckedContinuation<Void, Never>?
    func enqueue(_ reply: Reply) { results.append(reply) }
    func holdNext() { holding = true }
    func waitForStart() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func release() { continuation?.resume(returning: detailFixture()); continuation = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        guard name == "dastak-v1-orders" else { throw URLError(.badURL) }
        calls.append(try JSONEncoder().encode(request))
        let data: Data
        if holding {
            holding = false; data = await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
        } else if !results.isEmpty {
            switch results.removeFirst() {
            case let .data(value): data = value
            case .offline: throw URLError(.notConnectedToInternet)
            case .denied: throw FunctionClientError.api(statusCode: 403, code: "access_denied", message: "Denied")
            }
        } else { data = detailFixture() }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
private let detailFixtureID = UUID(uuidString: "97000000-0000-4000-8000-000000000001")!
private let detailFixtureBranch = UUID(uuidString: "97000000-0000-4000-8000-000000000002")!
private func detailFixture() -> Data {
    let data = Data("""
    {"target":{"kind":"FULFILMENT","id":"\(detailFixtureID)","branchId":"\(detailFixtureBranch)"},"branch":{"id":"\(detailFixtureBranch)","displayName":"Store A"},"order":{"id":"97000000-0000-4000-8000-000000000003","displayOrderNumber":"DSK-OLD-001","status":"DELIVERED","orderType":"RETAIL_ONLY","createdAt":"2026-10-18T00:00:00Z"},"records":[{"id":"\(detailFixtureID)","kind":"FULFILMENT","status":"COMPLETED","version":3,"productSubtotalPaise":1000,"lines":[{"orderLineId":"97000000-0000-4000-8000-000000000004","name":"Tea","quantity":2,"selection":{"options":[{"id":"97000000-0000-4000-8000-000000000005","groupId":"97000000-0000-4000-8000-000000000006","groupName":"Sugar","name":"Less sugar","priceDeltaPaise":0}]}}],"evidence":[],"problems":[],"recovery":[],"delivery":{}}],"returns":[],"settlements":[]}
    """.utf8)
    var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    object["recoveryOffers"] = []
    return try! JSONSerialization.data(withJSONObject: object)
}
