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
            transport: { try await transport.send($0) }
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
            transport: { try await transport.send($0) }
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

    func testInvokeRecoversFromTransientTransportFailureWithSameRequest() async throws {
        let transport = SequencedTransport([
            .failure(URLError(.networkConnectionLost)),
            .response(statusCode: 200, body: #"{"accepted":true}"#.data(using: .utf8)!)
        ])
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { "user-access-token" },
            transport: { try await transport.send($0) }
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "transient-transport"))

        let response: TestResponse = try await client.invoke(
            "perform-action",
            request: TestRequest(value: 2),
            idempotencyKey: key
        )

        XCTAssertEqual(response, TestResponse(accepted: true))
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests.map { $0.value(forHTTPHeaderField: "X-Idempotency-Key") },
            ["transient-transport", "transient-transport"]
        )
    }

    func testInvokeRecoversFromTransientGatewayResponse() async throws {
        let transport = SequencedTransport([
            .response(
                statusCode: 503,
                body: #"{"error":{"code":"temporarily_unavailable","message":"Try again"}}"#
                    .data(using: .utf8)!
            ),
            .response(statusCode: 200, body: #"{"accepted":true}"#.data(using: .utf8)!)
        ])
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { "user-access-token" },
            transport: { try await transport.send($0) }
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "gateway-retry"))

        let response: TestResponse = try await client.invoke(
            "perform-action",
            request: TestRequest(value: 2),
            idempotencyKey: key
        )

        XCTAssertEqual(response, TestResponse(accepted: true))
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testInvokeDoesNotRetryNonTransientClientResponse() async throws {
        let transport = SequencedTransport([
            .response(
                statusCode: 400,
                body: #"{"error":{"code":"invalid_request","message":"Invalid request"}}"#
                    .data(using: .utf8)!
            )
        ])
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { "user-access-token" },
            transport: { try await transport.send($0) }
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "no-client-retry"))

        do {
            let _: TestResponse = try await client.invoke(
                "perform-action",
                request: TestRequest(value: 2),
                idempotencyKey: key
            )
            XCTFail("Expected a client error")
        } catch let error as FunctionClientError {
            XCTAssertEqual(
                error,
                .api(statusCode: 400, code: "invalid_request", message: "Invalid request")
            )
        }

        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testInvokeMultipartPreservesAuthenticationIdempotencyFieldsAndFile() async throws {
        let transport = RecordingTransport(
            statusCode: 200,
            responseBody: #"{"accepted":true}"#.data(using: .utf8)!
        )
        let client = SupabaseFunctionClient(
            configuration: makeConfiguration(),
            accessTokenProvider: { "user-access-token" },
            transport: transport.send
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "media-action-123"))
        let fileData = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])

        let response: TestResponse = try await client.invokeMultipart(
            "upload-media",
            fields: ["entityType": "RESTAURANT_MENU_ITEM", "entityId": "dish-123"],
            file: FunctionUpload(fieldName: "file", fileName: "dish.png", contentType: "image/png", data: fileData),
            idempotencyKey: key
        )

        XCTAssertEqual(response, TestResponse(accepted: true))
        let recordedRequest = await transport.recordedRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Idempotency-Key"), "media-action-123")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = try XCTUnwrap(request.httpBody)
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyText.contains("name=\"entityType\"\r\n\r\nRESTAURANT_MENU_ITEM"))
        XCTAssertTrue(bodyText.contains("name=\"entityId\"\r\n\r\ndish-123"))
        XCTAssertTrue(bodyText.contains("name=\"file\"; filename=\"dish.png\""))
        XCTAssertTrue(bodyText.contains("Content-Type: image/png"))
        XCTAssertTrue(body.range(of: fileData) != nil)
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

private actor SequencedTransport {
    enum Result {
        case response(statusCode: Int, body: Data)
        case failure(any Error)
    }

    private var results: [Result]
    private var requests: [URLRequest] = []

    init(_ results: [Result]) {
        self.results = results
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let result = results.removeFirst()
        switch result {
        case let .response(statusCode, body):
            return (
                body,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [URLRequest] { requests }
    func callCount() -> Int { requests.count }
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
