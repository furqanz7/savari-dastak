import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakPaymentClientTests: XCTestCase {
    func testOwnerRateCardSendsOnlyServerPricingInputs() async throws {
        let functions = RecordingPaymentFunctionClient()
        let client = SupabaseDastakPaymentClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "payment-rate-key-1"))

        let rate = try await client.ownerUpsertRateCard(
            serviceZoneID: serviceZoneID,
            deliveryFee: Money(paise: 4_000),
            merchantCommissionBasisPoints: 1_000,
            courierPayout: Money(paise: 3_000),
            active: true,
            idempotencyKey: key
        )

        XCTAssertEqual(rate.merchantCommissionBasisPoints, 1_000)
        XCTAssertEqual(rate.courierPayout, Money(paise: 3_000))
        let lastCall = await functions.lastCall()
        let call = try XCTUnwrap(lastCall)
        XCTAssertEqual(call.name, "payment-ledger")
        XCTAssertEqual(call.idempotencyKey, key)
        let request = try JSONDecoder().decode(CapturedPaymentRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "ownerUpsertRateCard")
        XCTAssertEqual(request.serviceZoneId, serviceZoneID)
        XCTAssertEqual(request.deliveryFeePaise, 4_000)
        XCTAssertEqual(request.merchantCommissionBps, 1_000)
        XCTAssertEqual(request.courierPayoutPaise, 3_000)
        XCTAssertEqual(request.active, true)
        XCTAssertNil(request.accountId)
        XCTAssertNil(request.merchantPayablePaise)
        XCTAssertNil(request.platformMarginPaise)
    }

    func testOwnerSnapshotDecodesServerFinancialSplit() async throws {
        let functions = RecordingPaymentFunctionClient()
        let client = SupabaseDastakPaymentClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "payment-snapshot-key-1"))

        let snapshot = try await client.ownerOrderSnapshot(
            orderID: orderID,
            idempotencyKey: key
        )

        XCTAssertEqual(snapshot.paymentState, .captured)
        XCTAssertEqual(snapshot.settlementState, .settled)
        XCTAssertEqual(snapshot.merchantPayable, Money(paise: 9_000))
        XCTAssertEqual(snapshot.courierPayout, Money(paise: 3_000))
        XCTAssertEqual(snapshot.platformMerchantCommission, Money(paise: 1_000))
        XCTAssertEqual(snapshot.platformDeliveryMargin, Money(paise: 1_000))
        let lastCall = await functions.lastCall()
        let call = try XCTUnwrap(lastCall)
        let request = try JSONDecoder().decode(CapturedPaymentRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "ownerOrderSnapshot")
        XCTAssertEqual(request.orderId, orderID)
        XCTAssertNil(request.accountId)
    }
}

private let serviceZoneID = UUID(uuidString: "82000000-0000-4000-8000-000000000010")!
private let orderID = UUID(uuidString: "82000000-0000-4000-8000-000000000080")!

private struct CapturedPaymentRequest: Decodable {
    let operation: String
    let accountId: UUID?
    let serviceZoneId: UUID?
    let orderId: UUID?
    let deliveryFeePaise: Int?
    let merchantCommissionBps: Int?
    let courierPayoutPaise: Int?
    let active: Bool?
    let merchantPayablePaise: Int?
    let platformMarginPaise: Int?
}

private actor RecordingPaymentFunctionClient: FunctionClient {
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
        let data = operation == "ownerUpsertRateCard" ? rateCardJSON : snapshotJSON
        return try JSONDecoder().decode(Response.self, from: data)
    }

    func lastCall() -> Call? {
        calls.last
    }
}

private struct OperationOnly: Decodable {
    let operation: String
}

private let rateCardJSON = #"""
{
  "serviceZoneId":"82000000-0000-4000-8000-000000000010",
  "deliveryFee":{"paise":4000},
  "merchantCommissionBps":1000,
  "courierPayout":{"paise":3000},
  "active":true,
  "version":2
}
"""#.data(using: .utf8)!

private let snapshotJSON = #"""
{
  "orderId":"82000000-0000-4000-8000-000000000080",
  "paymentState":"captured",
  "settlementState":"settled",
  "currency":"INR",
  "gross":{"paise":14000},
  "captured":{"paise":14000},
  "refundReserved":{"paise":0},
  "refunded":{"paise":0},
  "merchantPayable":{"paise":9000},
  "courierPayout":{"paise":3000},
  "platformMerchantCommission":{"paise":1000},
  "platformDeliveryMargin":{"paise":1000},
  "version":3,
  "updatedAt":"2026-07-17T12:00:00+00:00"
}
"""#.data(using: .utf8)!
