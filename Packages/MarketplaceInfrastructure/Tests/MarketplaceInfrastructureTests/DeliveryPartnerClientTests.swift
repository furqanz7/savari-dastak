import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DeliveryPartnerClientTests: XCTestCase {
    func testSubmitUsesTypedMethodAndEvidenceWithoutClientOwnedApproval() async throws {
        let functions = RecordingDeliveryPartnerFunctionClient()
        let client = SupabaseDeliveryPartnerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "partner-submit-1"))

        let result = try await client.submit(
            deliveryMethod: .bike,
            identityEvidenceObjectPath: "dastak-partner/account/identity.pdf",
            vehicleRegistrationNumber: "TN 23 AB 1234",
            vehicleMakeModel: "Honda Activa 6G",
            vehicleEvidenceObjectPath: "dastak-partner/account/vehicle.pdf",
            idempotencyKey: key
        )

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.deliveryMethod, .bike)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedDeliveryPartnerRequest.self, from: call.body)
        XCTAssertEqual(call.name, "delivery-partners")
        XCTAssertEqual(call.idempotencyKey, key)
        XCTAssertEqual(request.operation, "submit")
        XCTAssertEqual(request.deliveryMethod, "bike")
        XCTAssertEqual(request.identityEvidenceObjectPath, "dastak-partner/account/identity.pdf")
        XCTAssertEqual(request.vehicleRegistrationNumber, "TN 23 AB 1234")
        XCTAssertEqual(request.vehicleMakeModel, "Honda Activa 6G")
        XCTAssertEqual(request.vehicleEvidenceObjectPath, "dastak-partner/account/vehicle.pdf")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertNil(object["accountId"])
        XCTAssertNil(object["approved"])
    }

    func testSelfSnapshotDecodesServerOwnedOnboardingAndAvailability() async throws {
        let functions = RecordingDeliveryPartnerFunctionClient()
        let client = SupabaseDeliveryPartnerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "partner-snapshot-1"))

        let snapshot = try await client.selfSnapshot(idempotencyKey: key)

        XCTAssertEqual(snapshot.onboardingState, .approved)
        XCTAssertEqual(snapshot.deliveryMethod, .bike)
        XCTAssertEqual(snapshot.availability?.status, .online)
        XCTAssertEqual(snapshot.availability?.stateVersion, 3)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedDeliveryPartnerRequest.self, from: call.body).operation,
            "selfSnapshot"
        )
    }

    func testOwnerListAndReviewCarryNoOwnerIdentity() async throws {
        let functions = RecordingDeliveryPartnerFunctionClient()
        let client = SupabaseDeliveryPartnerClient(functions: functions)
        let listKey = try XCTUnwrap(IdempotencyKey(rawValue: "partner-list-1"))
        let reviewKey = try XCTUnwrap(IdempotencyKey(rawValue: "partner-review-1"))
        let applicationID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        let applications = try await client.listPending(idempotencyKey: listKey)
        XCTAssertEqual(applications.first?.displayName, "Delivery Partner")
        XCTAssertEqual(applications.first?.phoneNumber, "+919876543210")

        let reviewed = try await client.review(
            applicationID: applicationID,
            decision: .approve,
            reason: nil,
            idempotencyKey: reviewKey
        )
        XCTAssertEqual(reviewed.status, .approved)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedDeliveryPartnerRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "review")
        XCTAssertEqual(request.applicationId, applicationID)
        XCTAssertEqual(request.decision, "approve")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertNil(object["ownerId"])
    }

    func testOnlineAvailabilitySendsOnlyIntentAndCurrentLocation() async throws {
        let functions = RecordingDeliveryPartnerFunctionClient()
        let client = SupabaseDeliveryPartnerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "partner-online-1"))
        let location = GeoPoint(latitude: 12.68, longitude: 78.62)

        let availability = try await client.setAvailability(
            online: true,
            location: location,
            idempotencyKey: key
        )

        XCTAssertEqual(availability.status, .online)
        XCTAssertEqual(availability.location, location)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedDeliveryPartnerRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "setAvailability")
        XCTAssertEqual(request.online, true)
        XCTAssertEqual(request.location, location)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertNil(object["serviceZoneId"])
        XCTAssertNil(object["availableUntil"])
        XCTAssertNil(object["stateVersion"])
    }

    func testOfflineAvailabilitySendsNoLocation() async throws {
        let functions = RecordingDeliveryPartnerFunctionClient()
        let client = SupabaseDeliveryPartnerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "partner-offline-1"))

        let availability = try await client.setAvailability(
            online: false,
            location: nil,
            idempotencyKey: key
        )

        XCTAssertEqual(availability.status, .offline)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedDeliveryPartnerRequest.self, from: call.body)
        XCTAssertEqual(request.online, false)
        XCTAssertNil(request.location)
    }

    func testLocationPublicationDoesNotSendAvailabilityIntent() async throws {
        let functions = RecordingDeliveryPartnerFunctionClient()
        let client = SupabaseDeliveryPartnerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "partner-location-1"))
        let location = GeoPoint(latitude: 12.681, longitude: 78.623)

        let availability = try await client.publishLocation(location: location, idempotencyKey: key)

        XCTAssertEqual(availability.location, location)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedDeliveryPartnerRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "publishLocation")
        XCTAssertEqual(request.location, location)
        XCTAssertNil(request.online)
    }
}

private struct CapturedDeliveryPartnerRequest: Decodable {
    let operation: String
    let deliveryMethod: String?
    let identityEvidenceObjectPath: String?
    let vehicleRegistrationNumber: String?
    let vehicleMakeModel: String?
    let vehicleEvidenceObjectPath: String?
    let applicationId: UUID?
    let decision: String?
    let reason: String?
    let online: Bool?
    let location: GeoPoint?
}

private actor RecordingDeliveryPartnerFunctionClient: FunctionClient {
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
        case "submit":
            response = #"{"applicationId":"22222222-2222-4222-8222-222222222222","status":"pending","deliveryMethod":"bike"}"#.data(using: .utf8)!
        case "selfSnapshot":
            response = #"{"onboardingState":"approved","applicationId":"22222222-2222-4222-8222-222222222222","deliveryMethod":"bike","identityEvidenceObjectPath":"dastak-partner/account/identity.pdf","vehicleRegistrationNumber":"TN 23 AB 1234","vehicleMakeModel":"Honda Activa 6G","vehicleEvidenceObjectPath":"dastak-partner/account/vehicle.pdf","reviewReason":null,"availability":{"status":"online","location":{"latitude":12.68,"longitude":78.62},"serviceZoneId":"33333333-3333-4333-8333-333333333333","availableUntil":"2026-07-16T12:15:00Z","stateVersion":3}}"#.data(using: .utf8)!
        case "listPending":
            response = #"{"applications":[{"applicationId":"22222222-2222-4222-8222-222222222222","accountId":"11111111-1111-4111-8111-111111111111","displayName":"Delivery Partner","phoneNumber":"+919876543210","deliveryMethod":"bike","identityEvidenceObjectPath":"dastak-partner/account/identity.pdf","vehicleRegistrationNumber":"TN 23 AB 1234","vehicleMakeModel":"Honda Activa 6G","vehicleEvidenceObjectPath":"dastak-partner/account/vehicle.pdf","status":"pending","submittedAt":"2026-07-16T12:00:00Z"}]}"#.data(using: .utf8)!
        case "review":
            response = #"{"applicationId":"22222222-2222-4222-8222-222222222222","status":"approved","deliveryMethod":"bike"}"#.data(using: .utf8)!
        case "setAvailability":
            let request = try JSONDecoder().decode(CapturedDeliveryPartnerRequest.self, from: body)
            response = request.online == true
                ? #"{"status":"online","location":{"latitude":12.68,"longitude":78.62},"serviceZoneId":"33333333-3333-4333-8333-333333333333","availableUntil":"2026-07-16T12:15:00Z","stateVersion":2}"#.data(using: .utf8)!
                : #"{"status":"offline","location":null,"serviceZoneId":null,"availableUntil":null,"stateVersion":3}"#.data(using: .utf8)!
        case "publishLocation":
            response = #"{"status":"online","location":{"latitude":12.681,"longitude":78.623},"serviceZoneId":"33333333-3333-4333-8333-333333333333","availableUntil":"2026-07-16T12:15:00Z","stateVersion":4}"#.data(using: .utf8)!
        default:
            throw FunctionClientError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? {
        call
    }
}

private struct OperationOnly: Decodable {
    let operation: String
}
