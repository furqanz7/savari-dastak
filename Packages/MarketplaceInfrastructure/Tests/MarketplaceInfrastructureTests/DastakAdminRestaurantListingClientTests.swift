import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakAdminRestaurantListingClientTests: XCTestCase {
    func testGovernancePagingUsesCurrentContractAndNoClientActor() async throws {
        let functions = ListingFunctionRecorder()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        let cursor = DastakAdminMerchantListingCursor(updatedAt: "2026-10-10T00:00:00Z", rowId: UUID())
        let page = try await client.merchantListingPage(query: "  Cafe  ", limit: 40, cursor: cursor, idempotencyKey: key)
        XCTAssertFalse(page.hasMore)
        let recorded = await functions.last()
        let call = try XCTUnwrap(recorded)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        XCTAssertEqual(call.name, "dastak-v1-orders")
        XCTAssertEqual(body["operation"] as? String, "adminMerchantGovernancePage")
        XCTAssertEqual(body["query"] as? String, "Cafe")
        XCTAssertEqual(body["limit"] as? Int, 40)
        XCTAssertEqual((body["cursor"] as? [String: Any])?["rowId"] as? String, cursor.rowId.uuidString)
        XCTAssertNil(body["actorId"])
    }

    func testRemoveAndRestoreCarryVersionReasonAndOriginalKeyOnly() async throws {
        let functions = ListingFunctionRecorder()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        for visible in [false, true] {
            let result = try await client.setRestaurantCustomerVisibility(branchID: listingBranchID,
                visible: visible, expectedVersion: 3, reason: "  Listing correction  ", idempotencyKey: key)
            XCTAssertEqual(result.branchId, listingBranchID)
            XCTAssertEqual(result.customerListingVisible, visible)
            XCTAssertEqual(result.version, 4)
            let recorded = await functions.last()
            let call = try XCTUnwrap(recorded)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
            XCTAssertEqual(call.key, key)
            XCTAssertEqual(body["operation"] as? String, "setAdminRestaurantCustomerVisibility")
            XCTAssertEqual(body["branchId"] as? String, listingBranchID.uuidString)
            XCTAssertEqual(body["expectedVersion"] as? Int, 3)
            XCTAssertEqual(body["reason"] as? String, "Listing correction")
            XCTAssertEqual(body["visible"] as? Bool, visible)
            XCTAssertNil(body["actorId"])
            XCTAssertNil(body["isOpen"])
            XCTAssertNil(body["status"])
        }
    }

    func testInvalidCommandsNeverReachTransport() async throws {
        let functions = ListingFunctionRecorder()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        for (version, reason) in [(0, "valid reason"), (3, "  "), (3, String(repeating: "x", count: 501))] {
            do {
                _ = try await client.setRestaurantCustomerVisibility(branchID: listingBranchID, visible: false,
                    expectedVersion: version, reason: reason, idempotencyKey: key)
                XCTFail("Invalid visibility command must fail locally")
            } catch {}
        }
        let last = await functions.last()
        XCTAssertNil(last)
    }

    private var key: IdempotencyKey { IdempotencyKey(rawValue: "listing-reviewed-once")! }
}

private let listingBranchID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private actor ListingFunctionRecorder: FunctionClient {
    struct Call: Sendable { let name: String; let body: Data; let key: IdempotencyKey }
    private var call: Call?
    func last() -> Call? { call }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        let data = try JSONEncoder().encode(request)
        call = Call(name: name, body: data, key: idempotencyKey)
        let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let response: Data
        if body["operation"] as? String == "adminMerchantGovernancePage" {
            response = Data(#"{"merchants":[],"hasMore":false,"nextCursor":null,"serviceZones":[]}"#.utf8)
        } else {
            response = try JSONSerialization.data(withJSONObject: ["branchId": listingBranchID.uuidString,
                "customerListingVisible": body["visible"] as! Bool, "version": 4, "updatedAt": "2026-10-10T00:00:00Z"])
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }
    func invokeMultipart<Response: Decodable & Sendable>(_ name: String, fields: [String: String],
        file: FunctionUpload, idempotencyKey: IdempotencyKey) async throws -> Response {
        throw FunctionClientError.invalidResponse
    }
}
