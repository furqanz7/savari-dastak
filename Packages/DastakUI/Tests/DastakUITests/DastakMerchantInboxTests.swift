import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantInboxTests: XCTestCase {
    func testCurrentOrdersSurviveLegacyCatalogueAndEarningsFailures() async throws {
        let functions = MerchantInboxFunctions()
        let model = model(functions)
        await model.bootstrap()
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.opportunities.count, 1)
        XCTAssertEqual(model.restaurantRequests.count, 1)
        XCTAssertEqual(model.v1Fulfilments.count, 1)
        XCTAssertEqual(model.orderRefreshFailures, ["Earlier orders"])
        XCTAssertNil(model.errorMessage, "Background refresh errors belong inline, not in repeated modal alerts.")
        let calls = await functions.operations
        XCTAssertTrue(calls.contains("merchantOpportunities"), "This endpoint is the branch heartbeat.")
        XCTAssertTrue(calls.contains("restaurantRequests"))
    }

    func testOneCurrentFeedFailureKeepsOtherFeedsAndPreviousData() async {
        let functions = MerchantInboxFunctions()
        let model = model(functions)
        await model.refreshOrders()
        await functions.fail("merchantOpportunities")
        await model.refreshOrders()
        XCTAssertEqual(model.opportunities.count, 1, "Retain last good data with a visible stale warning.")
        XCTAssertEqual(model.v1Fulfilments.count, 1)
        XCTAssertEqual(model.restaurantRequests.count, 1)
        XCTAssertTrue(model.orderRefreshFailures.contains("Incoming orders"))
    }

    func testAcceptanceCarriesScopeVersionPrepTimeAndStableRetryKey() async throws {
        let functions = MerchantInboxFunctions()
        let model = model(functions)
        await model.refreshOrders()
        let opportunity = try XCTUnwrap(model.opportunities.first)
        await model.respondToOpportunity(opportunity, accept: true, prepMinutes: 20)
        await model.respondToOpportunity(opportunity, accept: true, prepMinutes: 20)
        let calls = await functions.responses
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.first?.key, calls.last?.key, "A failed response must retry the same server command.")
        let body = try XCTUnwrap(calls.first?.body)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(request["operation"] as? String, "acceptMerchantOpportunity")
        XCTAssertEqual(request["requestScope"] as? String, "REQUESTED_SUBSET")
        XCTAssertEqual(request["expectedVersion"] as? Int, 4)
        XCTAssertEqual(request["promisedPrepMinutes"] as? Int, 20)
        XCTAssertNil(request["price"])
        XCTAssertNil(request["accountId"])
    }

    func testRestaurantDeclineCarriesReasonAndVersionWithoutPreparation() async throws {
        let functions = MerchantInboxFunctions()
        let client = SupabaseDastakV1MerchantInboxClient(functions: functions)
        let key = IdempotencyKey(rawValue: "restaurant-decline")!
        let requests = try await client.restaurantRequests(idempotencyKey: key)
        do {
            _ = try await client.respond(request: requests[0], accept: false, prepMinutes: 15, reason: "Kitchen closed", idempotencyKey: key)
        } catch {}
        let calls = await functions.responses
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(calls.first?.body)) as? [String: Any])
        XCTAssertEqual(request["response"] as? String, "DECLINE")
        XCTAssertEqual(request["reason"] as? String, "Kitchen closed")
        XCTAssertEqual(request["expectedVersion"] as? Int, 2)
        XCTAssertNil(request["promisedPrepMinutes"])
    }

    func testHistoryNeverShowsCompletedOrdersAsPreparingOrReady() throws {
        let delivered = try JSONDecoder().decode(DastakV1MerchantFulfilment.self, from: Data(
            fulfilmentFixture.replacingOccurrences(of: "\"orderStatus\":\"PREPARING\"", with: "\"orderStatus\":\"DELIVERED\"").utf8
        ))
        XCTAssertTrue(DastakMerchantQueue.history.includes(delivered))
        XCTAssertFalse(DastakMerchantQueue.preparing.includes(delivered))
        XCTAssertFalse(DastakMerchantQueue.all.includes(delivered))
    }

    func testProductVariantsFoodOptionsAndPickupCodeArePreserved() throws {
        let order = try JSONDecoder().decode(DastakV1MerchantFulfilment.self, from: Data(fulfilmentFixture.utf8))
        XCTAssertEqual(order.lines[0].packSize, "500 ml")
        XCTAssertEqual(order.lines[0].selection?.options[0].name, "Less sugar")
        XCTAssertEqual(order.delivery?.pickupCode, "1234")
    }

    func testCountdownUsesServerDeadlineAndHandlesFractionalSeconds() throws {
        let now = try XCTUnwrap(DastakMerchantOrderClock.date("2026-09-07T12:00:00Z"))
        XCTAssertEqual(DastakMerchantOrderClock.remaining("2026-09-07T12:01:30.000Z", now: now), "1:30")
        XCTAssertTrue(DastakMerchantOrderClock.isExpired("2026-09-07T11:59:59Z", now: now))
        XCTAssertEqual(DastakMerchantOrderClock.remaining("2026-09-07T11:59:59Z", now: now), "0:00")
    }

    func testReadyConflictRefreshesInlineWithoutBlockingAlert() async throws {
        let functions = MerchantInboxFunctions()
        let model = model(functions)
        await model.refreshOrders()
        await functions.failReadyAsChanged()

        await model.markV1Ready(try XCTUnwrap(model.v1Fulfilments.first))

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(
            model.notice,
            "This order changed while you were working. The latest status is now shown."
        )
        let calls = await functions.operations
        XCTAssertGreaterThanOrEqual(calls.filter { $0 == "merchantFulfilments" }.count, 2)
    }

    private func model(_ functions: MerchantInboxFunctions) -> DastakMerchantModel {
        DastakMerchantModel(services: MarketplaceAuthenticatedServices(
            functions: functions, accountIDProvider: { UUID() },
            objectUploader: { _, _, _, _, _ in }
        ))
    }
}

private actor MerchantInboxFunctions: FunctionClient {
    struct ResponseCall: Sendable { let key: String; let body: Data }
    var operations: [String] = []
    var responses: [ResponseCall] = []
    private var failures: Set<String> = []
    private var readyChanged = false
    func fail(_ operation: String) { failures.insert(operation) }
    func failReadyAsChanged() { readyChanged = true }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        let body = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let operation = object?["operation"] as? String ?? name
        operations.append(operation)
        if operation == "markFulfilmentReady", readyChanged {
            throw FunctionClientError.api(
                statusCode: 409,
                code: "invalid_state",
                message: "That action is not available in the current state."
            )
        }
        if operation.hasPrefix("accept") || operation.hasPrefix("decline") || operation == "respondRestaurantRequest" {
            responses.append(ResponseCall(key: idempotencyKey.rawValue, body: body))
            throw URLError(.timedOut)
        }
        guard !failures.contains(operation) else { throw URLError(.notConnectedToInternet) }
        let json: String
        switch operation {
        case "merchantOpportunities": json = "{\"opportunities\":[\(opportunityFixture)]}"
        case "restaurantRequests": json = "{\"requests\":[\(restaurantFixture)]}"
        case "merchantFulfilments": json = "{\"fulfilments\":[\(fulfilmentFixture)]}"
        default: throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: Data(json.utf8))
    }
}

private let branchFixture = #"{"id":"91000000-0000-4000-8000-000000000001","displayName":"Test store"}"#
private let opportunityFixture = """
{"id":"91000000-0000-4000-8000-000000000002","displayOrderNumber":"DSK-001","requestScope":"REQUESTED_SUBSET","status":"OFFERED","version":4,"branch":\(branchFixture),"expiresAt":"2026-09-07T12:01:30Z","secondsRemaining":90,"prepTimeOptionsMinutes":[10,15,20],"lines":[]}
"""
private let restaurantFixture = """
{"id":"91000000-0000-4000-8000-000000000003","orderId":"91000000-0000-4000-8000-000000000004","displayOrderNumber":"DSK-002","status":"OFFERED","version":2,"branch":\(branchFixture),"offeredAt":"2026-09-07T12:00:00Z","softThresholdWarning":false,"lines":[]}
"""
private let fulfilmentFixture = """
{"id":"91000000-0000-4000-8000-000000000005","orderId":"91000000-0000-4000-8000-000000000004","displayOrderNumber":"DSK-002","orderStatus":"PREPARING","status":"PREPARING","version":3,"branch":\(branchFixture),"promisedPrepMinutes":15,"secondsRemaining":120,"runningLate":false,"evidence":[],"canDeclarePackages":true,"canAddEvidence":true,"canMarkReady":false,
"lines":[{"orderLineId":"91000000-0000-4000-8000-000000000006","name":"Milk tea","quantity":2,"packSize":"500 ml","selection":{"options":[{"id":"91000000-0000-4000-8000-000000000007","groupId":"91000000-0000-4000-8000-000000000008","groupName":"Sweetness","name":"Less sugar","priceDeltaPaise":0}]}}],
"delivery":{"riderAssigned":true,"pickupCode":"1234"}}
"""
