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
}

private struct CapturedCheckoutRequest: Decodable {
    let operation: String
    let entityType: DastakCheckoutEntityType?
    let orderId: UUID?
    let parcelId: UUID?
}

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
        let response = """
        {
          "orderId":"11111111-1111-4111-8111-111111111111",
          "providerOrderId":"order_test123",
          "keyId":"rzp_test_123",
          "amountPaise":10000,
          "currency":"INR",
          "receipt":"parcel-11111111"
        }
        """
        return try JSONDecoder().decode(Response.self, from: Data(response.utf8))
    }

    func lastCall() -> Call? {
        call
    }
}
