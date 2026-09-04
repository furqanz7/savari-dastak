import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class MerchantApplicationClientTests: XCTestCase {
    func testSubmitUsesTypedMerchantOperationAndIdempotencyKey() async throws {
        let functions = RecordingMerchantFunctionClient()
        let client = SupabaseMerchantApplicationClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "merchant-submit-1"))

        let result = try await client.submit(
            merchantType: .retail,
            legalName: "Corner Store Private Limited",
            businessName: "Corner Store",
            businessAddress: "12 Main Road",
            latitude: 12.65,
            longitude: 78.65,
            evidenceObjectPath: "merchant/account/registration.pdf",
            idempotencyKey: key
        )

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.merchantType, .retail)
        XCTAssertEqual(result.serviceZoneName, "Central service area")
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "merchant-applications")
        XCTAssertEqual(call.idempotencyKey, key)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedMerchantRequest.self, from: call.body),
            .init(
                operation: "submit",
                merchantType: "RETAIL",
                legalName: "Corner Store Private Limited",
                businessName: "Corner Store",
                businessAddress: "12 Main Road",
                latitude: 12.65,
                longitude: 78.65,
                evidenceObjectPath: "merchant/account/registration.pdf",
                applicationId: nil,
                decision: nil,
                reason: nil
            )
        )
    }

    func testListPendingUsesOwnerOperation() async throws {
        let functions = RecordingMerchantFunctionClient()
        let client = SupabaseMerchantApplicationClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "merchant-list-1"))

        let applications = try await client.listPending(idempotencyKey: key)

        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications.first?.submittedAt, "2026-07-16T12:00:00Z")
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedMerchantRequest.self, from: call.body).operation,
            "list"
        )
    }

    func testSelfSnapshotRestoresRejectedMerchantDetails() async throws {
        let functions = RecordingMerchantFunctionClient()
        let client = SupabaseMerchantApplicationClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "merchant-snapshot-1"))

        let snapshot = try await client.selfSnapshot(idempotencyKey: key)

        XCTAssertEqual(snapshot.onboardingState, .rejected)
        XCTAssertEqual(snapshot.merchantType, .retail)
        XCTAssertEqual(snapshot.legalName, "Corner Store Private Limited")
        XCTAssertEqual(snapshot.businessName, "Corner Store")
        XCTAssertEqual(snapshot.businessAddress, "12 Main Road")
        XCTAssertEqual(snapshot.reviewReason, "Upload a clearer document.")
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedMerchantRequest.self, from: call.body).operation,
            "selfSnapshot"
        )
    }

    func testReviewUsesTypedDecisionWithoutSupplyingOwnerIdentity() async throws {
        let functions = RecordingMerchantFunctionClient()
        let client = SupabaseMerchantApplicationClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "merchant-review-1"))
        let applicationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

        let result = try await client.review(
            applicationID: applicationID,
            decision: .approve,
            reason: nil,
            idempotencyKey: key
        )

        XCTAssertEqual(result.status, .approved)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedMerchantRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "review")
        XCTAssertEqual(request.applicationId, applicationID)
        XCTAssertEqual(request.decision, "approve")
        XCTAssertNil(request.reason)
    }
}

private struct CapturedMerchantRequest: Decodable, Equatable {
    let operation: String
    let merchantType: String?
    let legalName: String?
    let businessName: String?
    let businessAddress: String?
    let latitude: Double?
    let longitude: Double?
    let evidenceObjectPath: String?
    let applicationId: UUID?
    let decision: String?
    let reason: String?
}

private actor RecordingMerchantFunctionClient: FunctionClient {
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
            response = #"{"applicationId":"33333333-3333-4333-8333-333333333333","status":"pending","merchantType":"RETAIL","serviceZoneId":"44444444-4444-4444-8444-444444444444","serviceZoneName":"Central service area"}"#.data(using: .utf8)!
        case "list":
            response = #"{"applications":[{"applicationId":"33333333-3333-4333-8333-333333333333","accountId":"22222222-2222-4222-8222-222222222222","applicantName":"Merchant Owner","applicantPhone":"+919876543210","merchantType":"RETAIL","legalName":"Corner Store Private Limited","businessName":"Corner Store","businessAddress":"12 Main Road","latitude":12.65,"longitude":78.65,"serviceZoneId":"44444444-4444-4444-8444-444444444444","serviceZoneName":"Central service area","evidenceObjectPath":"merchant/22222222-2222-4222-8222-222222222222/registration.pdf","status":"pending","submittedAt":"2026-07-16T12:00:00Z"}]}"#.data(using: .utf8)!
        case "selfSnapshot":
            response = #"{"onboardingState":"rejected","applicationId":"33333333-3333-4333-8333-333333333333","merchantType":"RETAIL","legalName":"Corner Store Private Limited","businessName":"Corner Store","businessAddress":"12 Main Road","latitude":12.65,"longitude":78.65,"serviceZoneId":"44444444-4444-4444-8444-444444444444","serviceZoneName":"Central service area","evidenceObjectPath":"merchant/22222222-2222-4222-8222-222222222222/registration.pdf","reviewReason":"Upload a clearer document.","organizationId":null,"branchId":null}"#.data(using: .utf8)!
        case "review":
            response = #"{"applicationId":"33333333-3333-4333-8333-333333333333","status":"approved","merchantType":"RETAIL","serviceZoneId":"44444444-4444-4444-8444-444444444444","serviceZoneName":"Central service area"}"#.data(using: .utf8)!
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
