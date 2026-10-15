import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakAdminMerchantGovernanceClientTests: XCTestCase {
    func testStatusCommandsUseCorrectTargetAndExpectedVersionWithoutActorOrStoreState() async throws {
        let functions = MerchantFunctionRecorder()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        for target in [DastakAdminMerchantTarget.organization, .branch] {
            for status in [DastakAdminMerchantStatus.active, .suspended] {
                _ = try await client.setMerchantStatus(target: target, id: target == .organization ? orgID : branchID,
                    status: status, expectedVersion: 3, reason: "  Reviewed compliance  ", idempotencyKey: key)
                let recorded = await functions.last()
                let call = try XCTUnwrap(recorded)
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: call.data) as? [String: Any])
                XCTAssertEqual(call.name, "dastak-v1-orders")
                XCTAssertEqual(call.key, key)
                XCTAssertEqual(body["operation"] as? String, target == .organization ? "setAdminMerchantOrganizationStatus" : "setAdminMerchantBranchStatus")
                XCTAssertEqual(body["\(target.rawValue)Id"] as? String, target == .organization ? orgID.uuidString : branchID.uuidString)
                XCTAssertEqual(body["status"] as? String, status.rawValue)
                XCTAssertEqual(body["expectedVersion"] as? Int, 3)
                XCTAssertEqual(body["reason"] as? String, "Reviewed compliance")
                XCTAssertNil(body["actorId"])
                XCTAssertNil(body["isOpen"])
                XCTAssertNil(body["customerListingVisible"])
            }
        }
    }
    func testCorrectionsSendOnlyReviewedPatchFieldsAndVersion() async throws {
        let functions = MerchantFunctionRecorder()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        let result = try await client.correctMerchantBranch(id: branchID,
            changes: .init(displayName: "Updated", latitude: 12.3, longitude: 76.6), expectedVersion: 3,
            reason: "  Verified coordinates  ", idempotencyKey: key)
        XCTAssertEqual(result.changedFields, ["displayName", "coordinates"])
        let recorded = await functions.last()
        let call = try XCTUnwrap(recorded)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: call.data) as? [String: Any])
        XCTAssertEqual(body["operation"] as? String, "correctAdminMerchantBranchDetails")
        XCTAssertEqual(body["branchId"] as? String, branchID.uuidString)
        XCTAssertEqual(body["expectedVersion"] as? Int, 3)
        XCTAssertEqual(body["reason"] as? String, "Verified coordinates")
        let patch = try XCTUnwrap(body["changes"] as? [String: Any])
        XCTAssertEqual(Set(patch.keys), ["displayName", "latitude", "longitude"])
        XCTAssertEqual(patch["latitude"] as? Double, 12.3)
        XCTAssertEqual(patch["longitude"] as? Double, 76.6)
        XCTAssertEqual(call.key, key)
        XCTAssertNil(body["actorId"])
    }
    func testInvalidPatchReasonAndVersionNeverReachTransport() async throws {
        let functions = MerchantFunctionRecorder()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        for patch in [DastakAdminBranchPatch(), .init(displayName: "   "), .init(address: .init(line1: "   ", countryCode: "IN")), .init(latitude: 12), .init(capacityLimit: 501), .init(latitude: .infinity, longitude: 77)] {
            do {
                _ = try await client.correctMerchantBranch(id: branchID, changes: patch, expectedVersion: 3, reason: "Reviewed", idempotencyKey: key)
                XCTFail("Invalid patch must fail")
            } catch {}
        }
        do {
            _ = try await client.setMerchantStatus(target: .branch, id: branchID, status: .suspended, expectedVersion: 0, reason: "Reviewed", idempotencyKey: key)
            XCTFail("Invalid version must fail")
        } catch {}
        do {
            _ = try await client.setMerchantStatus(target: .branch, id: branchID, status: .active, expectedVersion: 3, reason: " ", idempotencyKey: key)
            XCTFail("Missing reason must fail")
        } catch {}
        let call = await functions.last()
        XCTAssertNil(call)
    }
    private var key: IdempotencyKey { IdempotencyKey(rawValue: "merchant-reviewed-once")! }
}

private let orgID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
private let branchID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private actor MerchantFunctionRecorder: FunctionClient {
    struct Call: Sendable { let name: String; let data: Data; let key: IdempotencyKey }
    private var call: Call?
    func last() -> Call? { call }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let data = try JSONEncoder().encode(request)
        call = Call(name: name, data: data, key: idempotencyKey)
        let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var response: [String: Any] = ["organizationId": orgID.uuidString, "status": body["status"] ?? "ACTIVE", "version": 4, "updatedAt": "2026-10-10T00:00:00Z"]
        if body["branchId"] != nil { response["branchId"] = branchID.uuidString }
        if body["changes"] != nil { response["changedFields"] = ["displayName", "coordinates"] }
        return try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: response))
    }
    func invokeMultipart<Response: Decodable & Sendable>(_ name: String, fields: [String: String], file: FunctionUpload, idempotencyKey: IdempotencyKey) async throws -> Response { throw FunctionClientError.invalidResponse }
}
