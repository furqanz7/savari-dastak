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
            let (data, response) = try await URLSession.shared.data(for: request)
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

        let (data, response) = try await transport(urlRequest)
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
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

private struct APIErrorPayload: Decodable {
    let code: String
    let message: String
}
