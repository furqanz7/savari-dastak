import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakV1AdminClientTests: XCTestCase {
    func testAccessDecodesFixedSuperadminAndExecutiveSlots() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        let access = try await client.access(idempotencyKey: key("admin-access"))

        XCTAssertEqual(access.role, .superadmin)
        XCTAssertTrue(access.canManageAdmins)
        XCTAssertEqual(access.slots.map(\.slot), [0, 1, 2])
        XCTAssertEqual(access.slots[1].role, .executiveAdmin)
        XCTAssertNil(access.slots[1].email)
        let request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "adminAccess")
        XCTAssertNil(request["accountId"])
    }

    func testExecutiveAssignmentSendsOnlySlotEmailVersionAndReason() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        let slot = try await client.setExecutiveAdmin(
            slot: 1,
            email: "executive@example.com",
            expectedVersion: 1,
            reason: "Updated from protected Dastak Admin access settings.",
            idempotencyKey: key("admin-assign")
        )

        XCTAssertEqual(slot.email, "executive@example.com")
        XCTAssertTrue(slot.linked)
        let request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "setExecutiveAdmin")
        XCTAssertEqual(request["slot"] as? Int, 1)
        XCTAssertEqual(request["expectedVersion"] as? Int, 1)
        XCTAssertNil(request["accountId"])
        XCTAssertNil(request["role"])
    }

    private func key(_ value: String) throws -> IdempotencyKey {
        try XCTUnwrap(IdempotencyKey(rawValue: value))
    }

    private func requestBody(_ client: RecordingAdminFunctionClient) async throws -> [String: Any] {
        let recordedCall = await client.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "dastak-v1-orders")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
    }
}

private actor RecordingAdminFunctionClient: FunctionClient {
    struct Call: Sendable { let name: String; let body: Data }
    private var call: Call?

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey _: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let body = try JSONEncoder().encode(request)
        call = Call(name: name, body: body)
        let operation = try JSONDecoder().decode(AdminOperation.self, from: body).operation
        let response = operation == "adminAccess" ? adminAccessJSON : executiveSlotJSON
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? { call }
}

private struct AdminOperation: Decodable { let operation: String }
private let adminAccessJSON = #"""
{
  "role":"SUPERADMIN","canManageAdmins":true,
  "slots":[
    {"slot":0,"role":"SUPERADMIN","email":"super@example.com","linked":true,"version":1},
    {"slot":1,"role":"EXECUTIVE_ADMIN","email":null,"linked":false,"version":1},
    {"slot":2,"role":"EXECUTIVE_ADMIN","email":"future@example.com","linked":false,"version":2}
  ]
}
"""#.data(using: .utf8)!
private let executiveSlotJSON = #"""
{
  "slot":1,"role":"EXECUTIVE_ADMIN","email":"executive@example.com","linked":true,"version":2
}
"""#.data(using: .utf8)!
