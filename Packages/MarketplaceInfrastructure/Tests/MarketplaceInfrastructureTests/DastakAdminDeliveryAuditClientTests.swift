import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakAdminDeliveryAuditClientTests: XCTestCase {
    func testDeliveryPageBindsFiltersAndCursorWithoutActor() async throws {
        let transport = GovernanceHistoryRecorder()
        let client = SupabaseDastakV1AdminClient(functions: transport)
        let cursor = try decode(DastakAdminDeliveryCursor.self, ["updatedAt": stamp, "riderId": riderID.uuidString])
        _ = try await client.deliveryGovernancePage(query: " Rider ", status: .suspended, limit: 40, cursor: cursor, idempotencyKey: key)
        let call = await transport.last()
        let body = try json(try XCTUnwrap(call).data)
        XCTAssertEqual(body["operation"] as? String, "adminDeliveryPartnerGovernancePage")
        XCTAssertEqual(body["query"] as? String, "Rider")
        XCTAssertEqual(body["status"] as? String, "SUSPENDED")
        XCTAssertEqual(body["limit"] as? Int, 40)
        XCTAssertEqual((body["cursor"] as? [String: String])?["riderId"], riderID.uuidString)
        XCTAssertNil(body["actorId"])
        XCTAssertEqual(call?.name, "dastak-v1-orders")
    }
    func testRiderMutationsBindGovernanceVersionAndIdempotencyWithoutAvailabilityWrites() async throws {
        let transport = GovernanceHistoryRecorder()
        let client = SupabaseDastakV1AdminClient(functions: transport)
        for status in [DastakAdminRiderStatus.active, .suspended] {
            let result = try await client.setDeliveryPartnerStatus(riderID: riderID, status: status,
                expectedGovernanceVersion: 4, reason: "  Safety review  ", idempotencyKey: key)
            let call = await transport.last()
            let body = try json(try XCTUnwrap(call).data)
            XCTAssertEqual(Set(body.keys), ["operation", "riderId", "status", "expectedGovernanceVersion", "reason"])
            XCTAssertEqual(body["operation"] as? String, "setAdminDeliveryPartnerStatus")
            XCTAssertEqual(body["expectedGovernanceVersion"] as? Int, 4)
            XCTAssertEqual(body["reason"] as? String, "Safety review")
            XCTAssertEqual(body["riderId"] as? String, riderID.uuidString)
            XCTAssertEqual(call?.key, key)
            XCTAssertEqual(result.status, status)
            XCTAssertEqual(result.availabilityStatus, .offline)
        }
    }
    func testInvalidRiderCommandsDoNotReachTransport() async throws {
        let transport = GovernanceHistoryRecorder()
        let client = SupabaseDastakV1AdminClient(functions: transport)
        for (version, reason) in [(0, "Safety review"), (4, " "), (4, String(repeating: "a", count: 501))] {
            do { _ = try await client.setDeliveryPartnerStatus(riderID: riderID, status: .suspended,
                expectedGovernanceVersion: version, reason: reason, idempotencyKey: key); XCTFail("Must reject") } catch {}
        }
        do { _ = try await client.deliveryGovernancePage(query: String(repeating: "a", count: 101), status: nil,
            limit: 40, cursor: nil, idempotencyKey: key); XCTFail("Must reject") } catch {}
        let call = await transport.last()
        XCTAssertNil(call)
    }
    func testAuditRequestUsesFlatServerContractForEveryFilter() async throws {
        let transport = GovernanceHistoryRecorder()
        let client = SupabaseDastakV1AdminClient(functions: transport)
        var filters = DastakAdminAuditFilters()
        filters.fromOccurredAt = stamp; filters.toOccurredAt = "2026-10-11T00:00:00Z"
        filters.actorQuery = "Admin"; filters.action = "DELIVERY_PARTNER_SUSPENDED"; filters.resourceType = "delivery_partner"
        filters.resourceId = riderID; filters.orderId = riderID; filters.branchId = riderID; filters.accountId = riderID; filters.eventId = "v1:12"
        let cursor = try decode(DastakAdminAuditCursor.self, ["occurredAt": stamp, "eventId": "v1:11"])
        _ = try await client.auditHistory(filters: filters, limit: 50, cursor: cursor, idempotencyKey: key)
        let call = await transport.last()
        let body = try json(try XCTUnwrap(call).data)
        XCTAssertEqual(body["operation"] as? String, "adminAuditHistory")
        XCTAssertEqual(body["fromOccurredAt"] as? String, stamp)
        XCTAssertEqual(body["toOccurredAt"] as? String, filters.toOccurredAt)
        XCTAssertEqual(body["actorQuery"] as? String, "Admin")
        XCTAssertEqual(body["action"] as? String, filters.action)
        XCTAssertEqual(body["resourceType"] as? String, "delivery_partner")
        for field in ["resourceId", "orderId", "branchId", "accountId"] { XCTAssertEqual(body[field] as? String, riderID.uuidString) }
        XCTAssertEqual(body["eventId"] as? String, "v1:12")
        XCTAssertEqual((body["cursor"] as? [String: String])?["eventId"], "v1:11")
        XCTAssertNil(body["filters"]); XCTAssertNil(body["actorId"])
    }
    func testAuditRejectsInvalidRangesIdentifiersLengthsAndCursors() async throws {
        let transport = GovernanceHistoryRecorder()
        let client = SupabaseDastakV1AdminClient(functions: transport)
        for field in ["range", "date", "event", "actor", "action"] {
            var filters = DastakAdminAuditFilters()
            switch field {
            case "range": filters.fromOccurredAt = "2026-10-11T00:00:00Z"; filters.toOccurredAt = stamp
            case "date": filters.fromOccurredAt = "bad"
            case "event": filters.eventId = "legacy:not-a-uuid"
            case "actor": filters.actorQuery = String(repeating: "a", count: 101)
            default: filters.action = String(repeating: "a", count: 121)
            }
            do { _ = try await client.auditHistory(filters: filters, limit: 50, cursor: nil, idempotencyKey: key); XCTFail("Must reject") } catch {}
        }
        let cursor = try decode(DastakAdminAuditCursor.self, ["occurredAt": stamp, "eventId": "v1:abc"])
        do { _ = try await client.auditHistory(filters: .init(), limit: 50, cursor: cursor, idempotencyKey: key); XCTFail("Must reject") } catch {}
        let call = await transport.last()
        XCTAssertNil(call)
    }
    func testAuditSummaryDropsUnreviewedPrivateMetadataAndBoundsText() throws {
        let summary = try decode(DastakAdminAuditSummary.self, ["fromStatus": "ACTIVE", "version": 5,
            "decision": true, "outcome": String(repeating: "a", count: 200), "phoneNumber": "+919000000000",
            "rawEvidence": ["secret": "private"], "token": "secret"])
        XCTAssertEqual(Set(summary.values.keys), ["fromStatus", "version", "decision", "outcome"])
        XCTAssertEqual(summary.values["version"], .number(5))
        XCTAssertEqual(summary.values["decision"], .boolean(true))
        XCTAssertEqual(summary.values["outcome"]?.display.count, 160)
        XCTAssertThrowsError(try decode(DastakAdminAuditSummary.self, ["outcome": ["unexpected": "object"]]))
    }
    func testUnknownRiderEnumsAndMissingRequiredProjectionFailDecoding() throws {
        XCTAssertThrowsError(try decode(DastakAdminDeliveryPartner.ActiveWork.self, ["domain": "UNREVIEWED", "id": riderID.uuidString]))
        XCTAssertThrowsError(try decode(DastakAdminDeliveryPartner.Governance.self, ["status": "UNKNOWN", "version": 1]))
        XCTAssertThrowsError(try decode(DastakAdminDeliveryPartner.Approval.self, ["status": "approved"]))
        XCTAssertTrue(DastakAdminContract.isAuditID("legacy:" + riderID.uuidString))
        XCTAssertTrue(DastakAdminContract.isAuditID("v1:123"))
        XCTAssertFalse(DastakAdminContract.isAuditID("v1:１２３"))
    }
    private var key: IdempotencyKey { IdempotencyKey(rawValue: "reviewed-delivery-command")! }
}

private let riderID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let stamp = "2026-10-10T00:00:00Z"
private func decode<T: Decodable>(_ type: T.Type, _ body: [String: Any]) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: body))
}
private func json(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
private actor GovernanceHistoryRecorder: FunctionClient {
    struct Call: Sendable { let name: String; let data: Data; let key: IdempotencyKey }
    private var call: Call?
    func last() -> Call? { call }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let data = try JSONEncoder().encode(request)
        call = .init(name: name, data: data, key: idempotencyKey)
        let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let response: [String: Any]
        switch body["operation"] as? String {
        case "adminDeliveryPartnerGovernancePage": response = ["deliveryPartners": [], "hasMore": false, "nextCursor": NSNull()]
        case "adminAuditHistory": response = ["events": [], "hasMore": false, "nextCursor": NSNull()]
        default: response = ["riderId": riderID.uuidString, "status": body["status"]!, "governanceVersion": 5,
            "availabilityStatus": "OFFLINE", "availabilityVersion": 9, "updatedAt": stamp]
        }
        return try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: response))
    }
    func invokeMultipart<Response: Decodable & Sendable>(_ name: String, fields: [String: String], file: FunctionUpload, idempotencyKey: IdempotencyKey) async throws -> Response { throw FunctionClientError.invalidResponse }
}
