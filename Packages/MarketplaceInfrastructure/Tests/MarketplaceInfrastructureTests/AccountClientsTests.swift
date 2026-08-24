import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class AccountClientsTests: XCTestCase {
    func testIndividualSessionRemovalUsesTypedServerCommand() async throws {
        let functions = RecordingAccountFunctionClient()
        let client = SupabaseAccountSessionClient(functions: functions)
        let sessionID = try XCTUnwrap(UUID(uuidString: "de200000-0000-4000-8000-000000000002"))
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "remove-device-1"))

        let snapshot = try await client.revoke(sessionID: sessionID, idempotencyKey: key)

        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertTrue(try XCTUnwrap(snapshot.sessions.first).isCurrent)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "account-sessions")
        XCTAssertEqual(call.idempotencyKey, key)
        let request = try JSONDecoder().decode(CapturedAccountRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "revoke")
        XCTAssertEqual(request.sessionId, sessionID)
        XCTAssertNil(request.deviceName)
    }

    func testAccountExportProducesPortableJSONWithoutChangingItsFilename() async throws {
        let functions = RecordingAccountFunctionClient()
        let client = SupabaseAccountProfileClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "export-account-1"))

        let exported = try await client.exportAccount(idempotencyKey: key)

        XCTAssertEqual(exported.filename, "dastak-account-de000000.json")
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exported.data) as? [String: Any]
        )
        XCTAssertEqual(payload["formatVersion"] as? Int, 1)
        XCTAssertEqual((payload["profile"] as? [String: Any])?["displayName"] as? String, "Dastak Customer")
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "account-profile")
        XCTAssertEqual(call.idempotencyKey, key)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedAccountRequest.self, from: call.body).operation,
            "export"
        )
    }

    func testIdentitySnapshotDecodesPostgresISO8601Timestamp() async throws {
        let functions = RecordingAccountFunctionClient()
        let client = SupabaseAccountProfileClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "identity-snapshot-1"))

        let identities = try await client.identitySnapshot(idempotencyKey: key)

        let identity = try XCTUnwrap(identities.first)
        XCTAssertEqual(identity.provider, .google)
        XCTAssertEqual(identity.linkKind, .origin)
        XCTAssertEqual(
            identity.linkedAt.timeIntervalSince1970,
            1_777_026_896.123456,
            accuracy: 0.001
        )
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "account-profile")
        XCTAssertEqual(call.idempotencyKey, key)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedAccountRequest.self, from: call.body).operation,
            "identitySnapshot"
        )
    }
}

private actor RecordingAccountFunctionClient: FunctionClient {
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
        let operation = try JSONDecoder().decode(CapturedAccountRequest.self, from: body).operation
        let response: Data
        switch operation {
        case "revoke":
            response = #"{"sessions":[{"sessionId":"de200000-0000-4000-8000-000000000001","deviceName":"Current iPhone","platform":"ios","appName":"Dastak","createdAt":"2026-08-24T08:00:00Z","lastSeenAt":"2026-08-24T08:01:00Z","isCurrent":true}]}"#.data(using: .utf8)!
        case "export":
            response = #"{"filename":"dastak-account-de000000.json","export":{"formatVersion":1,"profile":{"displayName":"Dastak Customer"},"orders":[]}}"#.data(using: .utf8)!
        case "identitySnapshot":
            response = #"{"providers":[{"provider":"google","linkKind":"ORIGIN","linkedAt":"2026-04-24T10:34:56.123456+00:00"}]}"#.data(using: .utf8)!
        default:
            throw FunctionClientError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? { call }
}

private struct CapturedAccountRequest: Decodable {
    let operation: String
    let sessionId: UUID?
    let deviceName: String?
}
