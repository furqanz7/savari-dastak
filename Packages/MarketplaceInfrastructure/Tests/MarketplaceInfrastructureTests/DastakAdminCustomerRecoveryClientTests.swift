import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure

final class DastakAdminCustomerRecoveryClientTests: XCTestCase {
    func testPhoneCorrectionPayloadDoesNotContainAuthIdentityOrEmail() async throws {
        let functions = CustomerRecoveryRecorder()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        _ = try await client.correctCustomerPhone(accountId: customer, reviewedCurrentPhone: "+919876543210", replacementPhone: "+919876543219", expectedPhoneClaimVersion: 4, reason: " Contact correction ", idempotencyKey: key)
        let raw = await functions.last
        let body = try json(try XCTUnwrap(raw))
        XCTAssertEqual(Set(body.keys), ["operation", "accountId", "reviewedCurrentPhone", "replacementPhone", "expectedPhoneClaimVersion", "reason"])
        XCTAssertEqual(body["operation"] as? String, "correctAdminCustomerPhone")
        XCTAssertEqual(body["reason"] as? String, "Contact correction")
        XCTAssertEqual(body["accountId"] as? String, customer.uuidString)
    }
    func testSingleAndAllSessionPayloadsUseOnlyReviewedScope() async throws {
        let functions = CustomerRecoveryRecorder(); let client = SupabaseDastakV1AdminClient(functions: functions)
        for scope in ["SINGLE", "ALL"] {
            _ = try await client.revokeCustomerSessions(accountId: customer, scope: scope, sessionId: scope == "SINGLE" ? customer : nil, reason: " Lost device ", idempotencyKey: key)
            let raw = await functions.last; let body = try json(try XCTUnwrap(raw))
            XCTAssertEqual(body["operation"] as? String, "revokeAdminCustomerSessions")
            XCTAssertEqual(body["scope"] as? String, scope); XCTAssertEqual(body["reason"] as? String, "Lost device")
            XCTAssertEqual(body["sessionId"] as? String, scope == "SINGLE" ? customer.uuidString : nil)
            XCTAssertNil(body["actorId"])
        }
    }
    func testPageRequestUsesTargetedAccountAndServerCursor() async throws {
        let functions = CustomerRecoveryRecorder(); let client = SupabaseDastakV1AdminClient(functions: functions)
        let cursor = try JSONDecoder().decode(DastakAdminCustomerRecoveryCursor.self, from: Data("{\"accountId\":\"\(customer)\",\"updatedAt\":\"2026-10-11T00:00:00Z\"}".utf8))
        _ = try await client.customerRecoveryPage(query: " Test ", accountId: customer, limit: 40, cursor: cursor, idempotencyKey: key)
        let raw = await functions.last; let body = try json(try XCTUnwrap(raw))
        XCTAssertEqual(body["operation"] as? String, "adminCustomerRecoveryPage")
        XCTAssertEqual(body["accountId"] as? String, customer.uuidString)
        XCTAssertEqual(body["query"] as? String, "Test")
        XCTAssertEqual((body["cursor"] as? [String: String])?["accountId"], customer.uuidString)
    }
    func testInvalidScopePhoneVersionAndReasonAreRejectedBeforeNetwork() async throws {
        let functions = CustomerRecoveryRecorder(); let client = SupabaseDastakV1AdminClient(functions: functions)
        for (scope, session) in [("SINGLE", Optional<UUID>.none), ("ALL", Optional(customer)), ("OTHER", Optional<UUID>.none)] {
            do { _ = try await client.revokeCustomerSessions(accountId: customer, scope: scope, sessionId: session, reason: "Lost device", idempotencyKey: key); XCTFail("Invalid scope accepted") } catch {}
        }
        for (phone, version, reason) in [("9876543210", 1, "Contact correction"), ("+919876543210", 1, "Contact correction"), ("+919876543219", 0, "Contact correction"), ("+919876543219", 1, " ")] {
            do { _ = try await client.correctCustomerPhone(accountId: customer, reviewedCurrentPhone: "+919876543210", replacementPhone: phone, expectedPhoneClaimVersion: version, reason: reason, idempotencyKey: key); XCTFail("Invalid phone command accepted") } catch {}
        }
        do { _ = try await client.customerRecoveryPage(query: String(repeating: "x", count: 101), accountId: nil, limit: 40, cursor: nil, idempotencyKey: key); XCTFail("Long query accepted") } catch {}
        let raw = await functions.last; XCTAssertNil(raw)
    }
    func testPrivilegedPhoneFailureDoesNotHideAutomaticTransportRetry() async throws {
        let transport = CustomerSingleAttemptTransport()
        let functions = SupabaseFunctionClient(configuration: .init(product: "Dastak", supabaseURL: URL(string: "https://example.invalid")!, publishableKey: "fixture"), accessTokenProvider: { "fixture-token" }, transport: { try await transport.send($0, failure: true) })
        do { _ = try await SupabaseDastakV1AdminClient(functions: functions).correctCustomerPhone(accountId: customer, reviewedCurrentPhone: "+919876543210", replacementPhone: "+919876543219", expectedPhoneClaimVersion: 1, reason: "Contact correction", idempotencyKey: key); XCTFail("Expected timeout") } catch {}
        let count = await transport.count; XCTAssertEqual(count, 1)
    }
    func testPrivilegedSessionServerFailureIsOneExplicitAttempt() async throws {
        let transport = CustomerSingleAttemptTransport()
        let functions = SupabaseFunctionClient(configuration: .init(product: "Dastak", supabaseURL: URL(string: "https://example.invalid")!, publishableKey: "fixture"), accessTokenProvider: { "fixture-token" }, transport: { try await transport.send($0, failure: false) })
        do { _ = try await SupabaseDastakV1AdminClient(functions: functions).revokeCustomerSessions(accountId: customer, scope: "ALL", sessionId: nil, reason: "Lost device", idempotencyKey: key); XCTFail("Expected server error") } catch {}
        let count = await transport.count; XCTAssertEqual(count, 1)
    }
    private var customer: UUID { UUID(uuidString: "98000000-0000-4000-8000-000000000001")! }
    private var key: IdempotencyKey { IdempotencyKey(rawValue: "98000000-0000-4000-8000-000000000002")! }
    private func json(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
}
private actor CustomerSingleAttemptTransport {
    var count = 0
    func send(_ request: URLRequest, failure: Bool) throws -> (Data, HTTPURLResponse) {
        count += 1
        if failure { throw URLError(.networkConnectionLost) }
        return (Data(#"{"error":{"code":"fixture","message":"Fixture unavailable"}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
    }
}
private actor CustomerRecoveryRecorder: FunctionClient {
    var last: Data?
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        last = try JSONEncoder().encode(request)
        let operation = (try JSONSerialization.jsonObject(with: last!) as? [String: Any])?["operation"] as? String
        let body = operation == "adminCustomerRecoveryPage" ? #"{"customers":[],"hasMore":false}"# : operation == "correctAdminCustomerPhone" ? #"{"accountId":"98000000-0000-4000-8000-000000000001","maskedPhoneNumber":"masked 3219","phoneClaimVersion":5,"phoneVerificationState":"unverified","updatedAt":"2026-10-11T00:00:00Z"}"# : #"{"accountId":"98000000-0000-4000-8000-000000000001","scope":"ALL","revokedSessionCount":0,"activeSessionCount":0,"updatedAt":"2026-10-11T00:00:00Z"}"#
        return try JSONDecoder().decode(Response.self, from: Data(body.utf8))
    }
}
