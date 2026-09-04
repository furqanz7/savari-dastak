import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import MarketplaceInfrastructure
import MarketplaceFoundation

final class FunctionClientTests: XCTestCase {
    func testInvokeAttachesIdempotencyHeaderAndDecodesResponse() async throws {
        let transport = RecordingTransport(
            statusCode: 200,
            responseBody: #"{"accepted":true}"#.data(using: .utf8)!
        )
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { "user-access-token" },
            transport: transport.send
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "request-123"))

        let response: TestResponse = try await client.invoke(
            "perform-action",
            request: TestRequest(value: 2),
            idempotencyKey: key
        )

        XCTAssertEqual(response, TestResponse(accepted: true))
        let recordedRequest = await transport.recordedRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/functions/v1/perform-action")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Idempotency-Key"), "request-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "publishable-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-access-token")
        XCTAssertEqual(
            try JSONDecoder().decode(TestRequest.self, from: try XCTUnwrap(request.httpBody)),
            TestRequest(value: 2)
        )
    }

    func testInvokeDecodesTypedAPIError() async throws {
        let transport = RecordingTransport(
            statusCode: 409,
            responseBody: #"{"error":{"code":"duplicate_request","message":"Already processed"}}"#.data(using: .utf8)!
        )
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { "user-access-token" },
            transport: transport.send
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "request-456"))

        do {
            let _: TestResponse = try await client.invoke(
                "perform-action",
                request: TestRequest(value: 2),
                idempotencyKey: key
            )
            XCTFail("Expected an API error")
        } catch let error as FunctionClientError {
            XCTAssertEqual(
                error,
                .api(statusCode: 409, code: "duplicate_request", message: "Already processed")
            )
        } catch {
            XCTFail("Expected FunctionClientError, got \(error)")
        }
    }

    func testInvokeRejectsMissingUserAccessTokenBeforeTransport() async throws {
        let transport = RecordingTransport(
            statusCode: 200,
            responseBody: #"{"accepted":true}"#.data(using: .utf8)!
        )
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { nil },
            transport: transport.send
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "request-without-session"))

        do {
            let _: TestResponse = try await client.invoke(
                "perform-action",
                request: TestRequest(value: 2),
                idempotencyKey: key
            )
            XCTFail("Expected authentication to be required")
        } catch let error as FunctionClientError {
            XCTAssertEqual(error, .authenticationRequired)
        }

        let callCount = await transport.recordedCallCount()
        XCTAssertEqual(callCount, 0)
    }

    func testInvokeRecoversFromOneTransientSessionReadBeforeTransport() async throws {
        let transport = RecordingTransport(
            statusCode: 200,
            responseBody: #"{"accepted":true}"#.data(using: .utf8)!
        )
        let tokens = TransientAccessTokenProvider()
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { try await tokens.load() },
            transport: transport.send
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "request-restored-session"))

        let response: TestResponse = try await client.invoke(
            "perform-action",
            request: TestRequest(value: 2),
            idempotencyKey: key
        )

        XCTAssertEqual(response, TestResponse(accepted: true))
        let tokenCallCount = await tokens.callCount()
        let transportCallCount = await transport.recordedCallCount()
        XCTAssertEqual(tokenCallCount, 2)
        XCTAssertEqual(transportCallCount, 1)
    }

    func testInvokeMapsMalformedErrorEnvelopePredictably() async throws {
        let transport = RecordingTransport(
            statusCode: 500,
            responseBody: #"{"error":{"message":"database details"}}"#.data(using: .utf8)!
        )
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { "user-access-token" },
            transport: transport.send
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "request-malformed-error"))

        do {
            let _: TestResponse = try await client.invoke(
                "perform-action",
                request: TestRequest(value: 2),
                idempotencyKey: key
            )
            XCTFail("Expected a malformed error response")
        } catch let error as FunctionClientError {
            XCTAssertEqual(error, .malformedErrorResponse(statusCode: 500))
        }
    }

    func testInvokeMapsMalformedSuccessfulResponsePredictably() async throws {
        let transport = RecordingTransport(
            statusCode: 200,
            responseBody: #"{"accepted":"not-a-boolean"}"#.data(using: .utf8)!
        )
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { "user-access-token" },
            transport: transport.send
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "request-malformed-success"))

        do {
            let _: TestResponse = try await client.invoke(
                "perform-action",
                request: TestRequest(value: 2),
                idempotencyKey: key
            )
            XCTFail("Expected an invalid response")
        } catch let error as FunctionClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    private func makeConfiguration() -> BackendConfiguration {
        BackendConfiguration(
            product: "test-product",
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable-key"
        )
    }
}

private struct TestRequest: Codable, Equatable, Sendable {
    let value: Int
}

private struct TestResponse: Codable, Equatable, Sendable {
    let accepted: Bool
}

private actor RecordingTransport {
    typealias TransportResponse = (Data, HTTPURLResponse)

    private let response: TransportResponse
    private var request: URLRequest?
    private var callCount = 0

    init(statusCode: Int, responseBody: Data) {
        response = (
            responseBody,
            HTTPURLResponse(
                url: URL(string: "https://example.supabase.co")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    func send(_ request: URLRequest) async throws -> TransportResponse {
        callCount += 1
        self.request = request
        return response
    }

    func recordedRequest() -> URLRequest? {
        request
    }

    func recordedCallCount() -> Int {
        callCount
    }
}

private actor TransientAccessTokenProvider {
    private var calls = 0

    func load() throws -> String? {
        calls += 1
        if calls == 1 { throw TransientAccessTokenError.unavailable }
        return "restored-user-access-token"
    }

    func callCount() -> Int { calls }
}

private enum TransientAccessTokenError: Error {
    case unavailable
}
