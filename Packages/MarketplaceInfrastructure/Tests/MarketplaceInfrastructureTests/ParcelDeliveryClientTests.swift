import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class ParcelDeliveryClientTests: XCTestCase {
    func testQuoteSendsLocationsAndMethodWithoutClientOwnedPriceOrDistance() async throws {
        let functions = RecordingParcelFunctionClient()
        let client = SupabaseParcelDeliveryClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "parcel-quote-1"))

        let quote = try await client.quote(
            deliveryMethod: .bike,
            pickup: AddressedGeoPoint(
                latitude: 12.68,
                longitude: 78.62,
                address: "1 Pickup Road"
            ),
            dropoff: AddressedGeoPoint(
                latitude: 12.69,
                longitude: 78.64,
                address: "2 Drop Road"
            ),
            idempotencyKey: key
        )

        XCTAssertEqual(quote.routeDistanceMeters, 4_250)
        XCTAssertEqual(quote.deliveryFee.paise, 5_000)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "parcel-deliveries")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertEqual(object["operation"] as? String, "quote")
        XCTAssertNil(object["accountId"])
        XCTAssertNil(object["routeDistanceMeters"])
        XCTAssertNil(object["deliveryFeePaise"])
        XCTAssertNil(object["courierPayoutPaise"])
    }

    func testCreateSendsOnlyParcelIntentAndDecodesPendingPayment() async throws {
        let functions = RecordingParcelFunctionClient()
        let client = SupabaseParcelDeliveryClient(functions: functions)
        let quoteID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

        let parcel = try await client.createParcel(
            quoteID: quoteID,
            recipientName: "Asha Khan",
            recipientPhoneNumber: "+919876543210",
            declaredContents: "Sealed documents",
            declaredValuePaise: 2_500,
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "parcel-create-1"))
        )

        XCTAssertEqual(parcel.status, .paymentPending)
        XCTAssertEqual(parcel.paymentStatus, .pending)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertEqual(object["operation"] as? String, "createParcel")
        XCTAssertEqual(object["quoteId"] as? String, quoteID.uuidString)
        XCTAssertNil(object["status"])
        XCTAssertNil(object["paymentStatus"])
        XCTAssertNil(object["deliveryFeePaise"])
    }

    func testRecipientSnapshotAndPartnerLifecycleUseExplicitOperations() async throws {
        let functions = RecordingParcelFunctionClient()
        let client = SupabaseParcelDeliveryClient(functions: functions)
        let parcelID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let assignmentID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

        let recipient = try await client.parcelSnapshot(
            parcelID: parcelID,
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "parcel-recipient-1"))
        )
        XCTAssertEqual(recipient.handoffCode?.purpose, .delivery)
        XCTAssertEqual(recipient.handoffCode?.code, "654321")

        _ = try await client.acknowledgeAssignment(
            assignmentID: assignmentID,
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "parcel-ack-1"))
        )
        let acknowledgeOperation = try await functions.lastOperation()
        XCTAssertEqual(acknowledgeOperation, "acknowledgeAssignment")

        _ = try await client.confirmPickup(
            assignmentID: assignmentID,
            verificationCode: "123456",
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "parcel-pickup-1"))
        )
        let pickupOperation = try await functions.lastOperation()
        let pickupCode = try await functions.lastVerificationCode()
        XCTAssertEqual(pickupOperation, "confirmPickup")
        XCTAssertEqual(pickupCode, "123456")

        _ = try await client.completeDelivery(
            assignmentID: assignmentID,
            verificationCode: "654321",
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "parcel-delivery-1"))
        )
        let completionOperation = try await functions.lastOperation()
        let deliveryCode = try await functions.lastVerificationCode()
        XCTAssertEqual(completionOperation, "completeDelivery")
        XCTAssertEqual(deliveryCode, "654321")
    }
}

private struct CapturedParcelRequest: Decodable {
    let operation: String
    let verificationCode: String?
}

private actor RecordingParcelFunctionClient: FunctionClient {
    struct Call: Sendable {
        let name: String
        let body: Data
    }

    private var call: Call?

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let body = try JSONEncoder().encode(request)
        call = Call(name: name, body: body)
        let operation = try JSONDecoder().decode(CapturedParcelRequest.self, from: body).operation
        let response: Data
        switch operation {
        case "quote":
            response = quoteJSON
        case "parcelSnapshot":
            response = parcelJSON(
                status: "in_transit",
                paymentStatus: "paid",
                handoffCode: #"{"purpose":"delivery","code":"654321","expiresAt":"2026-07-20T12:00:00Z"}"#
            )
        case "createParcel":
            response = parcelJSON(status: "payment_pending", paymentStatus: "pending")
        default:
            response = #"{"offer":null,"currentJob":null}"#.data(using: .utf8)!
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? { call }

    func lastOperation() throws -> String {
        guard let call else { throw FunctionClientError.invalidResponse }
        return try JSONDecoder().decode(CapturedParcelRequest.self, from: call.body).operation
    }

    func lastVerificationCode() throws -> String? {
        guard let call else { throw FunctionClientError.invalidResponse }
        return try JSONDecoder().decode(CapturedParcelRequest.self, from: call.body).verificationCode
    }

    private var quoteJSON: Data {
        #"{"quoteId":"33333333-3333-4333-8333-333333333333","deliveryMethod":"bike","routeDistanceMeters":4250,"routeDurationSeconds":720,"deliveryFee":{"currency":"INR","paise":5000},"courierPayout":{"currency":"INR","paise":4000},"expiresAt":"2026-07-19T12:05:00Z"}"#.data(using: .utf8)!
    }

    private func parcelJSON(
        status: String,
        paymentStatus: String,
        handoffCode: String = "null"
    ) -> Data {
        #"{"parcelId":"22222222-2222-4222-8222-222222222222","status":"\#(status)","paymentStatus":"\#(paymentStatus)","refundStatus":"not_requested","deliveryMethod":"bike","pickup":{"latitude":12.68,"longitude":78.62,"address":"1 Pickup Road"},"dropoff":{"latitude":12.69,"longitude":78.64,"address":"2 Drop Road"},"recipient":{"name":"Asha Khan","phoneNumber":"+919876543210"},"declaredContents":"Sealed documents","declaredValue":{"currency":"INR","paise":2500},"deliveryFee":{"currency":"INR","paise":5000},"courierPayout":{"currency":"INR","paise":4000},"handoffCode":\#(handoffCode)}"#.data(using: .utf8)!
    }
}
