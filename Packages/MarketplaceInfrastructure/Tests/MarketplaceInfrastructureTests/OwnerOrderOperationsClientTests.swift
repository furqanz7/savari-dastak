import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class OwnerOrderOperationsClientTests: XCTestCase {
    func testOwnerOperationsUseTypedServerContract() async throws {
        let functions = RecordingOwnerOperationsFunctionClient()
        let client = SupabaseOwnerOrderOperationsClient(functions: functions)

        let snapshot = try await client.snapshot(limit: 50, idempotencyKey: key("owner-snapshot"))
        let resolved = try await client.resolveSupport(
            caseID: supportID,
            resolution: "Customer contacted and issue resolved.",
            idempotencyKey: key("owner-support")
        )
        let reconciliation = try await client.reconcile(idempotencyKey: key("owner-reconcile"))

        XCTAssertEqual(snapshot.summary.totalExceptions, 1)
        XCTAssertEqual(snapshot.exceptions.first?.entityID, orderID)
        XCTAssertEqual(resolved.status, .resolved)
        XCTAssertEqual(reconciliation.merchantOffersCreated, 1)
        let calls = await functions.calls
        XCTAssertEqual(calls.map(\.operation), ["ownerOperations", "ownerResolveSupport", "ownerReconcile"])
        XCTAssertEqual(calls[0].limit, 50)
        XCTAssertEqual(calls[1].caseId, supportID)
        XCTAssertEqual(calls[1].resolution, "Customer contacted and issue resolved.")
    }

    func testRefundReviewSendsOnlyOwnerDecision() async throws {
        let functions = RecordingOwnerOperationsFunctionClient()
        let client = SupabaseOwnerOrderOperationsClient(functions: functions)

        let order = try await client.reviewRefund(
            orderID: orderID,
            outcome: .approveFull,
            faultSource: .merchant,
            reason: "Merchant could not fulfil the order.",
            idempotencyKey: key("owner-refund")
        )

        XCTAssertEqual(order.paymentState, .refundPending)
        let calls = await functions.calls
        let call = try XCTUnwrap(calls.last)
        XCTAssertEqual(call.operation, "ownerReviewRefund")
        XCTAssertEqual(call.orderId, orderID)
        XCTAssertEqual(call.outcome, .approveFull)
        XCTAssertEqual(call.faultSource, .merchant)
        XCTAssertEqual(call.reason, "Merchant could not fulfil the order.")
    }

    private func key(_ value: String) -> IdempotencyKey {
        IdempotencyKey(rawValue: value)!
    }
}

private let orderID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
private let supportID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!

private struct CapturedOwnerRequest: Decodable, Sendable {
    let operation: String
    let limit: Int?
    let caseId: UUID?
    let resolution: String?
    let orderId: UUID?
    let outcome: OwnerRefundOutcome?
    let faultSource: OwnerRefundFaultSource?
    let reason: String?
}

private actor RecordingOwnerOperationsFunctionClient: FunctionClient {
    private(set) var calls: [CapturedOwnerRequest] = []

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        XCTAssertEqual(name, "merchant-orders")
        let body = try JSONEncoder().encode(request)
        let call = try JSONDecoder().decode(CapturedOwnerRequest.self, from: body)
        calls.append(call)
        let response: Data = switch call.operation {
        case "ownerOperations": ownerSnapshotJSON
        case "ownerResolveSupport": resolvedSupportJSON
        case "ownerReviewRefund": refundOrderJSON
        case "ownerReconcile": reconciliationJSON
        default: throw FunctionClientError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }
}

private let ownerSnapshotJSON = #"""
{
  "summary":{"openSupport":1,"refundReviews":0,"lockedHandoffs":0,"stalledOrders":0,"totalExceptions":1},
  "exceptions":[{"exceptionId":"support:88888888-8888-4888-8888-888888888888","kind":"support","severity":"attention","entityKind":"merchant_order","entityId":"77777777-7777-4777-8777-777777777777","title":"Customer support request","detail":"Order is late","status":"open","occurredAt":"2026-08-20T10:00:00Z"}],
  "parcels":[]
}
"""#.data(using: .utf8)!

private let resolvedSupportJSON = #"{"caseId":"88888888-8888-4888-8888-888888888888","reference":"DSK-1001","entityKind":"merchant_order","entityId":"77777777-7777-4777-8777-777777777777","category":"delivery_status","message":"Order is late","status":"resolved","createdAt":"2026-08-20T10:00:00Z","updatedAt":"2026-08-20T10:05:00Z"}"#.data(using: .utf8)!

private let refundOrderJSON = #"{"orderId":"77777777-7777-4777-8777-777777777777","storeId":"33333333-3333-4333-8333-333333333333","status":"cancelled","paymentState":"refund_pending","lines":[],"itemSubtotal":{"paise":25000},"deliveryFee":{"paise":4000},"deliveryDistanceMeters":4250,"total":{"paise":29000},"dropoff":{"latitude":12.6819,"longitude":78.6201},"stateVersion":5,"createdAt":"2026-08-20T10:00:00Z","updatedAt":"2026-08-20T10:05:00Z"}"#.data(using: .utf8)!

private let reconciliationJSON = #"{"merchantOrdersRecovered":1,"parcelsRecovered":0,"merchantOffersCreated":1,"parcelOffersCreated":0,"reconciledAt":"2026-08-20T10:05:00Z"}"#.data(using: .utf8)!
