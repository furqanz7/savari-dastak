import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class CourierDispatchClientTests: XCTestCase {
    func testPartnerSnapshotDecodesOfferWithoutClientOwnedIdentity() async throws {
        let functions = RecordingCourierDispatchFunctionClient()
        let client = SupabaseCourierDispatchClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "dispatch-snapshot-1"))

        let snapshot = try await client.partnerSnapshot(idempotencyKey: key)

        XCTAssertEqual(snapshot.offer?.assignmentStatus, .offered)
        XCTAssertEqual(snapshot.offer?.orderStatus, .ready)
        XCTAssertEqual(snapshot.offer?.store.name, "Test Store")
        XCTAssertNil(snapshot.currentJob)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "courier-dispatch")
        XCTAssertEqual(call.idempotencyKey, key)
        let request = try JSONDecoder().decode(CapturedCourierDispatchRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "partnerSnapshot")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertNil(object["accountId"])
        XCTAssertNil(object["partnerAccountId"])
    }

    func testAcceptSendsOnlyAssignmentIntentAndDecodesCurrentJob() async throws {
        let functions = RecordingCourierDispatchFunctionClient()
        let client = SupabaseCourierDispatchClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "dispatch-accept-1"))
        let assignmentID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        let snapshot = try await client.acceptOffer(
            assignmentID: assignmentID,
            idempotencyKey: key
        )

        XCTAssertNil(snapshot.offer)
        XCTAssertEqual(snapshot.currentJob?.assignmentStatus, .accepted)
        XCTAssertEqual(snapshot.currentJob?.orderStatus, .assigned)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedCourierDispatchRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "acceptOffer")
        XCTAssertEqual(request.assignmentId, assignmentID)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertNil(object["orderId"])
        XCTAssertNil(object["status"])
        XCTAssertNil(object["respondBy"])
    }

    func testDeclineSendsOnlyAssignmentAndReason() async throws {
        let functions = RecordingCourierDispatchFunctionClient()
        let client = SupabaseCourierDispatchClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "dispatch-decline-1"))
        let assignmentID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        let snapshot = try await client.declineOffer(
            assignmentID: assignmentID,
            reason: "Cannot reach the store.",
            idempotencyKey: key
        )

        XCTAssertNil(snapshot.offer)
        XCTAssertNil(snapshot.currentJob)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedCourierDispatchRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "declineOffer")
        XCTAssertEqual(request.assignmentId, assignmentID)
        XCTAssertEqual(request.reason, "Cannot reach the store.")
    }

    func testLifecycleMethodsUseExplicitOperationsAndDecodeServerStatuses() async throws {
        let functions = RecordingCourierDispatchFunctionClient()
        let client = SupabaseCourierDispatchClient(functions: functions)
        let assignmentID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        let toStore = try await client.startToStore(
            assignmentID: assignmentID,
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "dispatch-start-store"))
        )
        XCTAssertEqual(toStore.currentJob?.orderStatus, .enRouteToPickup)
        let toStoreOperation = try await recordedOperation(functions)
        XCTAssertEqual(toStoreOperation, "startToStore")

        let atStore = try await client.arriveAtStore(
            assignmentID: assignmentID,
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "dispatch-arrive-store"))
        )
        XCTAssertEqual(atStore.currentJob?.orderStatus, .atStore)
        let atStoreOperation = try await recordedOperation(functions)
        XCTAssertEqual(atStoreOperation, "arriveAtStore")

        let pickedUp = try await client.confirmPickup(
            assignmentID: assignmentID,
            verificationCode: "1234",
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "dispatch-confirm-pickup"))
        )
        XCTAssertEqual(pickedUp.currentJob?.orderStatus, .pickedUp)
        let pickupOperation = try await recordedOperation(functions)
        XCTAssertEqual(pickupOperation, "confirmPickup")
        let pickupCode = try await recordedVerificationCode(functions)
        XCTAssertEqual(pickupCode, "1234")

        let inTransit = try await client.startDelivery(
            assignmentID: assignmentID,
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "dispatch-start-delivery"))
        )
        XCTAssertEqual(inTransit.currentJob?.orderStatus, .inTransit)
        let deliveryOperation = try await recordedOperation(functions)
        XCTAssertEqual(deliveryOperation, "startDelivery")

        let delivered = try await client.completeDelivery(
            assignmentID: assignmentID,
            verificationCode: "5678",
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "dispatch-complete-delivery"))
        )
        XCTAssertNil(delivered.currentJob)
        let completionOperation = try await recordedOperation(functions)
        XCTAssertEqual(completionOperation, "completeDelivery")
        let deliveryCode = try await recordedVerificationCode(functions)
        XCTAssertEqual(deliveryCode, "5678")
    }

    private func recordedOperation(
        _ functions: RecordingCourierDispatchFunctionClient
    ) async throws -> String {
        let lastCall = await functions.lastCall()
        let call = try XCTUnwrap(lastCall)
        return try JSONDecoder().decode(OperationOnly.self, from: call.body).operation
    }

    private func recordedVerificationCode(
        _ functions: RecordingCourierDispatchFunctionClient
    ) async throws -> String? {
        let lastCall = await functions.lastCall()
        let call = try XCTUnwrap(lastCall)
        return try JSONDecoder().decode(CapturedCourierDispatchRequest.self, from: call.body)
            .verificationCode
    }
}

private struct CapturedCourierDispatchRequest: Decodable {
    let operation: String
    let assignmentId: UUID?
    let reason: String?
    let verificationCode: String?
}

private actor RecordingCourierDispatchFunctionClient: FunctionClient {
    struct Call: Sendable {
        let name: String
        let body: Data
        let idempotencyKey: IdempotencyKey
    }

    private var call: Call?

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let body = try JSONEncoder().encode(request)
        call = Call(name: name, body: body, idempotencyKey: idempotencyKey)
        let operation = try JSONDecoder().decode(OperationOnly.self, from: body).operation
        let response: Data
        switch operation {
        case "partnerSnapshot":
            response = snapshotJSON(assignmentStatus: "offered", orderStatus: "ready", asOffer: true)
        case "acceptOffer":
            response = snapshotJSON(assignmentStatus: "accepted", orderStatus: "assigned", asOffer: false)
        case "declineOffer":
            response = #"{"offer":null,"currentJob":null}"#.data(using: .utf8)!
        case "startToStore":
            response = snapshotJSON(
                assignmentStatus: "accepted",
                orderStatus: "en_route_to_pickup",
                asOffer: false
            )
        case "arriveAtStore":
            response = snapshotJSON(
                assignmentStatus: "accepted",
                orderStatus: "at_store",
                asOffer: false
            )
        case "confirmPickup":
            response = snapshotJSON(
                assignmentStatus: "accepted",
                orderStatus: "picked_up",
                asOffer: false
            )
        case "startDelivery":
            response = snapshotJSON(
                assignmentStatus: "accepted",
                orderStatus: "in_transit",
                asOffer: false
            )
        case "completeDelivery":
            response = #"{"offer":null,"currentJob":null}"#.data(using: .utf8)!
        default:
            throw FunctionClientError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? {
        call
    }

    private func snapshotJSON(
        assignmentStatus: String,
        orderStatus: String,
        asOffer: Bool
    ) -> Data {
        let assignment = #"{"assignmentId":"22222222-2222-4222-8222-222222222222","orderId":"33333333-3333-4333-8333-333333333333","assignmentStatus":"\#(assignmentStatus)","orderStatus":"\#(orderStatus)","offeredAt":"2026-07-16T12:00:00Z","respondBy":"2026-07-16T12:01:00Z","acceptedAt":\#(assignmentStatus == "accepted" ? "\"2026-07-16T12:00:30Z\"" : "null"),"distanceMeters":125.5,"store":{"storeId":"44444444-4444-4444-8444-444444444444","name":"Test Store","address":"1 Main Road","pickup":{"latitude":12.68,"longitude":78.62}},"dropoff":{"latitude":12.69,"longitude":78.63},"items":[{"productId":"55555555-5555-4555-8555-555555555555","name":"Test Item","unitLabel":"1 pack","quantity":1}]}"#
        let json = asOffer
            ? #"{"offer":\#(assignment),"currentJob":null}"#
            : #"{"offer":null,"currentJob":\#(assignment)}"#
        return json.data(using: .utf8)!
    }
}

private struct OperationOnly: Decodable {
    let operation: String
}
