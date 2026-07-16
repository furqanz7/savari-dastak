import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class MerchantOrderClientTests: XCTestCase {
    func testQuoteSendsOnlyProductIdentityQuantityAndDropoff() async throws {
        let functions = RecordingMerchantOrderFunctionClient()
        let client = SupabaseMerchantOrderClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "quote-key-1"))
        let dropoff = GeoPoint(latitude: 12.6819, longitude: 78.6201)

        let quote = try await client.quote(
            storeID: storeID,
            lines: [MerchantOrderLineInput(productID: productID, quantity: 2)],
            dropoff: dropoff,
            idempotencyKey: key
        )

        XCTAssertEqual(quote.total, Money(paise: 29_000))
        XCTAssertEqual(quote.dropoff, dropoff)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "merchant-orders")
        XCTAssertEqual(call.idempotencyKey, key)
        let request = try JSONDecoder().decode(CapturedMerchantOrderRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "quote")
        XCTAssertEqual(request.storeId, storeID)
        XCTAssertEqual(request.lines, [MerchantOrderLineInput(productID: productID, quantity: 2)])
        XCTAssertEqual(request.dropoff, dropoff)
        XCTAssertNil(request.accountId)
        XCTAssertNil(request.unitPrice)
        XCTAssertNil(request.deliveryFee)
        XCTAssertNil(request.total)
    }

    func testCreateUsesOnlyTheServerQuoteIdentifier() async throws {
        let functions = RecordingMerchantOrderFunctionClient()
        let client = SupabaseMerchantOrderClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "create-key-1"))

        let order = try await client.create(quoteID: quoteID, idempotencyKey: key)

        XCTAssertEqual(order.status, .paymentPending)
        XCTAssertEqual(order.paymentState, .paymentPending)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedMerchantOrderRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "create")
        XCTAssertEqual(request.quoteId, quoteID)
        XCTAssertNil(request.itemSubtotal)
        XCTAssertNil(request.paymentState)
    }

    func testCustomerAndMerchantSnapshotsUseTypedServerSnapshots() async throws {
        let functions = RecordingMerchantOrderFunctionClient()
        let client = SupabaseMerchantOrderClient(functions: functions)
        let customerKey = try XCTUnwrap(IdempotencyKey(rawValue: "customer-snapshot-key"))
        let merchantKey = try XCTUnwrap(IdempotencyKey(rawValue: "merchant-snapshot-key"))

        let customer = try await client.customerSnapshot(idempotencyKey: customerKey)
        let merchant = try await client.merchantSnapshot(idempotencyKey: merchantKey)

        XCTAssertEqual(customer.orders.first?.total, Money(paise: 29_000))
        XCTAssertEqual(merchant.orders.first?.stateVersion, 1)
        let calls = await functions.allCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedMerchantOrderRequest.self, from: calls[0].body).operation,
            "customerSnapshot"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedMerchantOrderRequest.self, from: calls[1].body).operation,
            "merchantSnapshot"
        )
    }

    func testMerchantTransitionsSendOnlyOrderIntent() async throws {
        let functions = RecordingMerchantOrderFunctionClient()
        let client = SupabaseMerchantOrderClient(functions: functions)
        let acceptKey = try XCTUnwrap(IdempotencyKey(rawValue: "accept-key-1"))
        let readyKey = try XCTUnwrap(IdempotencyKey(rawValue: "ready-key-1"))

        let accepted = try await client.merchantAccept(orderID: orderID, idempotencyKey: acceptKey)
        let ready = try await client.merchantMarkReady(orderID: orderID, idempotencyKey: readyKey)

        XCTAssertEqual(accepted.status, .merchantAccepted)
        XCTAssertEqual(ready.status, .ready)
        let calls = await functions.allCalls()
        let acceptRequest = try JSONDecoder().decode(
            CapturedMerchantOrderRequest.self,
            from: calls[0].body
        )
        let readyRequest = try JSONDecoder().decode(
            CapturedMerchantOrderRequest.self,
            from: calls[1].body
        )
        XCTAssertEqual(acceptRequest.operation, "merchantAccept")
        XCTAssertEqual(readyRequest.operation, "merchantMarkReady")
        XCTAssertEqual(acceptRequest.orderId, orderID)
        XCTAssertEqual(readyRequest.orderId, orderID)
        XCTAssertNil(acceptRequest.status)
        XCTAssertNil(acceptRequest.accountId)
    }

    func testRejectAndCancelCannotSupplyRefundOrPaymentState() async throws {
        let functions = RecordingMerchantOrderFunctionClient()
        let client = SupabaseMerchantOrderClient(functions: functions)
        let rejectKey = try XCTUnwrap(IdempotencyKey(rawValue: "reject-key-1"))
        let cancelKey = try XCTUnwrap(IdempotencyKey(rawValue: "cancel-key-1"))

        let rejected = try await client.merchantReject(
            orderID: orderID,
            reason: "Item cannot be fulfilled",
            idempotencyKey: rejectKey
        )
        let cancelled = try await client.customerCancel(
            orderID: orderID,
            reason: "Changed my mind",
            idempotencyKey: cancelKey
        )

        XCTAssertEqual(rejected.refundDecision?.eligibility, .merchantFaultFullRefund)
        XCTAssertEqual(cancelled.refundDecision?.itemRefund, Money(paise: 25_000))
        let calls = await functions.allCalls()
        let rejectRequest = try JSONDecoder().decode(
            CapturedMerchantOrderRequest.self,
            from: calls[0].body
        )
        let cancelRequest = try JSONDecoder().decode(
            CapturedMerchantOrderRequest.self,
            from: calls[1].body
        )
        XCTAssertEqual(rejectRequest.reason, "Item cannot be fulfilled")
        XCTAssertEqual(cancelRequest.reason, "Changed my mind")
        XCTAssertNil(rejectRequest.refundDecision)
        XCTAssertNil(rejectRequest.paymentState)
        XCTAssertNil(cancelRequest.refundDecision)
        XCTAssertNil(cancelRequest.paymentState)
    }
}

private let storeID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private let productID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
private let quoteID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
private let orderID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!

private struct CapturedMerchantOrderRequest: Decodable {
    let operation: String
    let accountId: UUID?
    let storeId: UUID?
    let quoteId: UUID?
    let orderId: UUID?
    let lines: [MerchantOrderLineInput]?
    let dropoff: GeoPoint?
    let reason: String?
    let unitPrice: Money?
    let itemSubtotal: Money?
    let deliveryFee: Money?
    let total: Money?
    let paymentState: MerchantOrderPaymentState?
    let refundDecision: MerchantOrderRefundDecision?
    let status: MerchantOrderStatus?
}

private actor RecordingMerchantOrderFunctionClient: FunctionClient {
    struct Call: Sendable {
        let name: String
        let body: Data
        let idempotencyKey: IdempotencyKey
    }

    private var calls: [Call] = []

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let body = try JSONEncoder().encode(request)
        calls.append(Call(name: name, body: body, idempotencyKey: idempotencyKey))
        let operation = try JSONDecoder().decode(OperationOnly.self, from: body).operation
        let response: Data
        switch operation {
        case "quote":
            response = quoteJSON
        case "create", "customerSnapshot", "merchantSnapshot":
            response = operation == "create" ? orderJSON : snapshotJSON
        case "merchantAccept":
            response = acceptedOrderJSON
        case "merchantMarkReady":
            response = readyOrderJSON
        case "merchantReject":
            response = merchantRejectedOrderJSON
        case "customerCancel":
            response = customerCancelledOrderJSON
        default:
            throw FunctionClientError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? {
        calls.last
    }

    func allCalls() -> [Call] {
        calls
    }
}

private struct OperationOnly: Decodable {
    let operation: String
}

private let lineJSON = #"{"productId":"55555555-5555-4555-8555-555555555555","name":"Lime Soda","unitLabel":"750 ml","unitPrice":{"paise":12500},"quantity":2,"lineSubtotal":{"paise":25000}}"#
private let quoteJSON = (#"{"quoteId":"66666666-6666-4666-8666-666666666666","storeId":"33333333-3333-4333-8333-333333333333","lines":["# + lineJSON + #"],"itemSubtotal":{"paise":25000},"deliveryFee":{"paise":4000},"total":{"paise":29000},"dropoff":{"latitude":12.6819,"longitude":78.6201},"expiresAt":"2026-07-16T15:00:00+00:00"}"#).data(using: .utf8)!
private let orderBase = #""orderId":"77777777-7777-4777-8777-777777777777","storeId":"33333333-3333-4333-8333-333333333333","lines":["# + lineJSON + #"],"itemSubtotal":{"paise":25000},"deliveryFee":{"paise":4000},"total":{"paise":29000},"dropoff":{"latitude":12.6819,"longitude":78.6201},"createdAt":"2026-07-16T14:55:00+00:00","updatedAt":"2026-07-16T14:55:00+00:00""#
private let orderJSON = ("{" + orderBase + #", "status":"payment_pending","paymentState":"payment_pending","stateVersion":1,"refundDecision":null}"#).data(using: .utf8)!
private let acceptedOrderJSON = ("{" + orderBase + #", "status":"merchant_accepted","paymentState":"paid","stateVersion":3,"refundDecision":null}"#).data(using: .utf8)!
private let readyOrderJSON = ("{" + orderBase + #", "status":"ready","paymentState":"paid","stateVersion":4,"refundDecision":null}"#).data(using: .utf8)!
private let merchantRefundJSON = #"{"decisionId":"88888888-8888-4888-8888-888888888888","eligibility":"merchant_fault_full_refund","decisionStatus":"eligible","itemRefund":{"paise":25000},"deliveryFeeRefund":{"paise":4000},"reason":"Item cannot be fulfilled","createdAt":"2026-07-16T15:05:00+00:00"}"#
private let customerRefundJSON = #"{"decisionId":"99999999-9999-4999-8999-999999999999","eligibility":"full_refund","decisionStatus":"eligible","itemRefund":{"paise":25000},"deliveryFeeRefund":{"paise":4000},"reason":"Changed my mind","createdAt":"2026-07-16T15:05:00+00:00"}"#
private let merchantRejectedOrderJSON = ("{" + orderBase + #", "status":"cancelled","paymentState":"refund_pending","stateVersion":3,"refundDecision":"# + merchantRefundJSON + "}").data(using: .utf8)!
private let customerCancelledOrderJSON = ("{" + orderBase + #", "status":"cancelled","paymentState":"refund_pending","stateVersion":3,"refundDecision":"# + customerRefundJSON + "}").data(using: .utf8)!
private let snapshotJSON = ("{\"orders\":[" + String(data: orderJSON, encoding: .utf8)! + "]}").data(using: .utf8)!
