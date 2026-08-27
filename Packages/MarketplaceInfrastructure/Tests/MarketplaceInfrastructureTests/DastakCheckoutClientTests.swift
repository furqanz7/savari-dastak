import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakCheckoutClientTests: XCTestCase {
    func testParcelCheckoutUsesParcelIdentityAndPaymentFunction() async throws {
        let functions = CheckoutRecordingFunctionClient()
        let client = SupabaseDastakCheckoutClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "parcel-payment-1"))
        let parcelID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

        let session = try await client.createParcelCheckout(
            parcelID: parcelID,
            idempotencyKey: key
        )

        XCTAssertEqual(session.orderID, parcelID)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "dastak-payments")
        XCTAssertEqual(call.key, key)
        let request = try JSONDecoder().decode(CapturedCheckoutRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "createCheckout")
        XCTAssertEqual(request.entityType, .parcel)
        XCTAssertEqual(request.parcelId, parcelID)
        XCTAssertNil(request.orderId)
    }

    func testV1CheckoutUsesSecuredOrderIdentityAndDecodesAttempt() async throws {
        let functions = CheckoutRecordingFunctionClient()
        let client = SupabaseDastakCheckoutClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "v1-payment-1"))
        let orderID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

        let session = try await client.createV1OrderCheckout(orderID: orderID, idempotencyKey: key)

        XCTAssertEqual(session.entityType, .dastakV1Order)
        XCTAssertEqual(session.attemptID, paymentAttemptID)
        XCTAssertEqual(session.providerMode, .test)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedCheckoutRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "createCheckout")
        XCTAssertEqual(request.entityType, .dastakV1Order)
        XCTAssertEqual(request.orderId, orderID)
    }

    func testV1CheckoutFailureIsBoundToAttemptAndIdempotencyKey() async throws {
        let functions = CheckoutRecordingFunctionClient()
        let client = SupabaseDastakCheckoutClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "v1-failure-1"))
        let orderID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

        let result = try await client.reportV1CheckoutFailure(
            orderID: orderID,
            attemptID: paymentAttemptID,
            failureCode: .checkoutFailed,
            idempotencyKey: key
        )

        XCTAssertEqual(result.attemptID, paymentAttemptID)
        XCTAssertEqual(result.status, "FAILED")
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.key, key)
        let request = try JSONDecoder().decode(CapturedCheckoutRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "reportPaymentFailure")
        XCTAssertEqual(request.paymentAttemptId, paymentAttemptID)
        XCTAssertEqual(request.failureCode, .checkoutFailed)
    }

    func testCustomCheckoutCompletionCarriesOnlyProviderProofAndAttemptIdentity() async throws {
        let functions = CheckoutRecordingFunctionClient()
        let client = SupabaseDastakCheckoutClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "custom-return-1"))
        let orderID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

        let result = try await client.completeV1CustomCheckout(
            orderID: orderID,
            attemptID: paymentAttemptID,
            providerOrderID: "order_test123",
            providerPaymentID: "pay_test123",
            providerSignature: String(repeating: "a", count: 64),
            idempotencyKey: key
        )

        XCTAssertEqual(result.orderID, orderID)
        XCTAssertEqual(result.paymentAttemptID, paymentAttemptID)
        XCTAssertEqual(result.state, .awaitingProviderConfirmation)
        XCTAssertFalse(result.duplicate)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedCheckoutRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "completeCustomCheckout")
        XCTAssertEqual(request.entityType, .dastakV1Order)
        XCTAssertEqual(request.orderId, orderID)
        XCTAssertEqual(request.paymentAttemptId, paymentAttemptID)
        XCTAssertEqual(request.razorpayOrderID, "order_test123")
        XCTAssertEqual(request.razorpayPaymentID, "pay_test123")
        XCTAssertEqual(request.razorpaySignature, String(repeating: "a", count: 64))
        let encoded = String(decoding: call.body, as: UTF8.self)
        XCTAssertFalse(encoded.contains("amount"))
        XCTAssertFalse(encoded.contains("currency"))
    }

    func testV1CheckoutRejectsMissingOrMismatchedProviderMode() throws {
        let missingMode = """
        {"orderId":"11111111-1111-4111-8111-111111111111","entityType":"dastak_v1_order","attemptId":"22222222-2222-4222-8222-222222222222","providerOrderId":"order_test123","keyId":"rzp_test_123","amountPaise":10000,"currency":"INR","receipt":"v1-test"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(DastakCheckoutSession.self, from: Data(missingMode.utf8)))

        let mismatchedMode = """
        {"orderId":"11111111-1111-4111-8111-111111111111","entityType":"dastak_v1_order","attemptId":"22222222-2222-4222-8222-222222222222","providerMode":"TEST","providerOrderId":"order_test123","keyId":"rzp_live_123","amountPaise":10000,"currency":"INR","receipt":"v1-test"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(DastakCheckoutSession.self, from: Data(mismatchedMode.utf8)))
    }
}

private struct CapturedCheckoutRequest: Decodable {
    let operation: String
    let entityType: DastakCheckoutEntityType?
    let orderId: UUID?
    let parcelId: UUID?
    let paymentAttemptId: UUID?
    let failureCode: DastakV1CheckoutFailureCode?
    let razorpayOrderID: String?
    let razorpayPaymentID: String?
    let razorpaySignature: String?

    private enum CodingKeys: String, CodingKey {
        case operation, entityType, orderId, parcelId, paymentAttemptId, failureCode
        case razorpayOrderID = "razorpay_order_id"
        case razorpayPaymentID = "razorpay_payment_id"
        case razorpaySignature = "razorpay_signature"
    }
}

private let paymentAttemptID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

private actor CheckoutRecordingFunctionClient: FunctionClient {
    struct Call: Sendable {
        let name: String
        let body: Data
        let key: IdempotencyKey
    }

    private var call: Call?

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let data = try JSONEncoder().encode(request)
        call = Call(name: name, body: data, key: idempotencyKey)
        let captured = try JSONDecoder().decode(CapturedCheckoutRequest.self, from: data)
        let response: String
        if captured.operation == "reportPaymentFailure" {
            response = """
            {"attemptId":"\(paymentAttemptID)","status":"FAILED"}
            """
        } else if captured.operation == "completeCustomCheckout" {
            response = """
            {
              "orderId":"11111111-1111-4111-8111-111111111111",
              "paymentAttemptId":"\(paymentAttemptID)",
              "providerPaymentId":"pay_test123",
              "state":"AWAITING_PROVIDER_CONFIRMATION",
              "duplicate":false
            }
            """
        } else {
            let v1Fields = captured.entityType == .dastakV1Order
                ? "\"entityType\":\"dastak_v1_order\",\"attemptId\":\"\(paymentAttemptID)\",\"providerMode\":\"TEST\","
                : ""
            response = """
            {
              "orderId":"11111111-1111-4111-8111-111111111111",
              \(v1Fields)
              "providerOrderId":"order_test123",
              "keyId":"rzp_test_123",
              "amountPaise":10000,
              "currency":"INR",
              "receipt":"parcel-11111111"
            }
            """
        }
        return try JSONDecoder().decode(Response.self, from: Data(response.utf8))
    }

    func lastCall() -> Call? {
        call
    }
}
