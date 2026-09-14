import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MarketplaceFoundation

public protocol FunctionClient: Sendable {
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response
    func invokeMultipart<Response: Decodable & Sendable>(
        _ name: String,
        fields: [String: String],
        file: FunctionUpload,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response
}

public struct FunctionUpload: Equatable, Sendable {
    public let fieldName: String
    public let fileName: String
    public let contentType: String
    public let data: Data

    public init(fieldName: String = "file", fileName: String, contentType: String, data: Data) {
        self.fieldName = fieldName
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
    }
}

public extension FunctionClient {
    func invokeMultipart<Response: Decodable & Sendable>(
        _ name: String,
        fields: [String: String],
        file: FunctionUpload,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        throw FunctionClientError.invalidResponse
    }
}

public enum FunctionClientError: Error, Equatable, Sendable {
    case api(statusCode: Int, code: String?, message: String)
    case authenticationRequired
    case invalidResponse
    case malformedErrorResponse(statusCode: Int)
}

public struct SupabaseFunctionClient: FunctionClient {
    public typealias AccessTokenProvider = @Sendable () async throws -> String?
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let configuration: BackendConfiguration
    private let accessTokenProvider: AccessTokenProvider
    private let transport: Transport

    public init(
        configuration: BackendConfiguration,
        accessTokenProvider: @escaping AccessTokenProvider
    ) {
        self.configuration = configuration
        self.accessTokenProvider = accessTokenProvider
        self.transport = { request in
            guard #available(macOS 12.0, *) else {
                throw FunctionClientError.invalidResponse
            }
            let (data, response) = try await Self.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FunctionClientError.invalidResponse
            }
            return (data, httpResponse)
        }
    }

    init(
        configuration: BackendConfiguration,
        accessTokenProvider: @escaping AccessTokenProvider,
        transport: @escaping Transport
    ) {
        self.configuration = configuration
        self.accessTokenProvider = accessTokenProvider
        self.transport = transport
    }

    public func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        let accessToken = try await authenticatedAccessToken()

        let url = configuration.supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(name)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        urlRequest.setValue(idempotencyKey.rawValue, forHTTPHeaderField: "X-Idempotency-Key")

        let (data, response) = try await sendWithTransientRecovery(
            urlRequest,
            endpoint: name
        )
        guard (200..<300).contains(response.statusCode) else {
            guard let payload = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) else {
                throw FunctionClientError.malformedErrorResponse(statusCode: response.statusCode)
            }
            throw FunctionClientError.api(
                statusCode: response.statusCode,
                code: payload.error.code,
                message: payload.error.message
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            #if DEBUG
            print(
                "[Dastak API] response_decode_failed endpoint=\(name) " +
                    "failure=\(Self.safeDecodingFailure(error))"
            )
            #endif
            throw FunctionClientError.invalidResponse
        }
    }

    public func invokeMultipart<Response: Decodable & Sendable>(
        _ name: String,
        fields: [String: String],
        file: FunctionUpload,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        let accessToken = try await authenticatedAccessToken()
        let boundary = "DastakBoundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        let safeName = file.fileName.replacingOccurrences(of: "\"", with: "")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(safeName)\"\r\nContent-Type: \(file.contentType)\r\n\r\n")
        body.append(file.data)
        append("\r\n--\(boundary)--\r\n")

        let url = configuration.supabaseURL.appendingPathComponent("functions").appendingPathComponent("v1").appendingPathComponent(name)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey.rawValue, forHTTPHeaderField: "X-Idempotency-Key")
        let (data, response) = try await sendWithTransientRecovery(request, endpoint: name)
        guard (200..<300).contains(response.statusCode) else {
            guard let payload = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) else {
                throw FunctionClientError.malformedErrorResponse(statusCode: response.statusCode)
            }
            throw FunctionClientError.api(statusCode: response.statusCode, code: payload.error.code, message: payload.error.message)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw FunctionClientError.invalidResponse
        }
        return decoded
    }

    private func sendWithTransientRecovery(
        _ request: URLRequest,
        endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        let delays: [Duration] = [.milliseconds(120), .milliseconds(320)]

        for attempt in 0...delays.count {
            do {
                let response = try await transport(request)
                if Self.retryable(statusCode: response.1.statusCode), attempt < delays.count {
                    #if DEBUG
                    print(
                        "[Dastak API] transient_response endpoint=\(endpoint) " +
                            "status=\(response.1.statusCode) retry=\(attempt + 1)"
                    )
                    #endif
                    try await Task.sleep(for: delays[attempt])
                    continue
                }
                return response
            } catch {
                if Self.isCancellation(error) { throw CancellationError() }
                guard Self.isTransientTransport(error), attempt < delays.count else {
                    #if DEBUG
                    print(
                        "[Dastak API] request_failed endpoint=\(endpoint) " +
                            "category=\(Self.safeTransportFailure(error)) attempts=\(attempt + 1)"
                    )
                    #endif
                    throw error
                }
                #if DEBUG
                print(
                    "[Dastak API] transient_transport endpoint=\(endpoint) " +
                        "category=\(Self.safeTransportFailure(error)) retry=\(attempt + 1)"
                )
                #endif
                try await Task.sleep(for: delays[attempt])
            }
        }

        throw FunctionClientError.invalidResponse
    }

    private func authenticatedAccessToken() async throws -> String {
        for attempt in 0..<2 {
            do {
                if let token = try await accessTokenProvider()?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !token.isEmpty
                {
                    return token
                }
            } catch {
                // A restored mobile session can briefly be unavailable while
                // the auth client publishes its initial local session. Make
                // one bounded second read; a real missing session still fails.
            }
            if attempt == 0 { await Task.yield() }
        }
        throw FunctionClientError.authenticationRequired
    }

    private static func safeDecodingFailure(_ error: Error) -> String {
        let category: String
        let codingPath: [CodingKey]
        switch error {
        case let DecodingError.typeMismatch(_, context):
            category = "type_mismatch"
            codingPath = context.codingPath
        case let DecodingError.valueNotFound(_, context):
            category = "value_not_found"
            codingPath = context.codingPath
        case let DecodingError.keyNotFound(key, context):
            category = "key_not_found"
            codingPath = context.codingPath + [key]
        case let DecodingError.dataCorrupted(context):
            category = "data_corrupted"
            codingPath = context.codingPath
        default:
            category = "unknown"
            codingPath = []
        }
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? category : "\(category):\(path)"
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private static func retryable(statusCode: Int) -> Bool {
        statusCode == 429 || [502, 503, 504].contains(statusCode)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled || Task.isCancelled
    }

    private static func isTransientTransport(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .secureConnectionFailed,
            .cannotLoadFromNetwork,
            .dataNotAllowed
        ].contains(error.code)
    }

    private static func safeTransportFailure(_ error: Error) -> String {
        if let error = error as? URLError { return "url_\(error.code.rawValue)" }
        return String(describing: type(of: error))
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

private struct APIErrorPayload: Decodable {
    let code: String
    let message: String
}
