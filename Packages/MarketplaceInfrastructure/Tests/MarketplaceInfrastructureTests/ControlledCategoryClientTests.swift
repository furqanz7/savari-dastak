import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class ControlledCategoryClientTests: XCTestCase {
    func testQuoteSendsOnlyControlledOrderIntent() async throws {
        let functions = RecordingControlledCategoryFunctionClient()
        let client = SupabaseControlledCategoryClient(functions: functions)
        let productID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

        _ = try await client.quote(
            scope: .medicine,
            storeID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            lines: [MerchantOrderLineInput(productID: productID, quantity: 2)],
            dropoff: GeoPoint(latitude: 12.6819, longitude: 78.6201),
            prescriptionEvidencePath: "prescription/account/rx.pdf",
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "controlled-quote-1"))
        )

        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "controlled-categories")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertEqual(object["operation"] as? String, "quote")
        XCTAssertNil(object["accountId"])
        XCTAssertNil(object["price"])
        XCTAssertNil(object["ageVerified"])
        XCTAssertNil(object["complianceApproved"])
    }

    func testRestrictedHandoffSendsVisualResultAndNoTargetStatus() async throws {
        let functions = RecordingControlledCategoryFunctionClient()
        let client = SupabaseControlledCategoryClient(functions: functions)

        _ = try await client.verifyRestrictedHandoff(
            assignmentID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            verificationCode: "1234",
            visualAgeCheck: .passed,
            reason: nil,
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "controlled-handoff-1"))
        )

        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertEqual(object["visualAgeCheck"] as? String, "passed")
        XCTAssertNil(object["status"])
        XCTAssertNil(object["orderId"])
    }
}

private actor RecordingControlledCategoryFunctionClient: FunctionClient {
    struct Call: Sendable { let name: String; let body: Data }
    private var call: Call?

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let body = try JSONEncoder().encode(request)
        call = Call(name: name, body: body)
        let operation = try JSONDecoder().decode(ControlledOperation.self, from: body).operation
        let response: Data
        if operation == "quote" {
            response = #"{"quoteId":"44444444-4444-4444-8444-444444444444","storeId":"22222222-2222-4222-8222-222222222222","lines":[],"itemSubtotal":{"paise":10000},"deliveryFee":{"paise":4000},"deliveryDistanceMeters":4250,"total":{"paise":14000},"dropoff":{"latitude":12.6819,"longitude":78.6201},"expiresAt":"2026-07-19T12:05:00Z"}"#.data(using: .utf8)!
        } else {
            response = #"{"offer":null,"currentJob":null}"#.data(using: .utf8)!
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? { call }
}

private struct ControlledOperation: Decodable { let operation: String }
