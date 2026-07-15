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
    case invalidResponse
}

public struct SupabaseFunctionClient: FunctionClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let configuration: BackendConfiguration
    private let transport: Transport

    public init(configuration: BackendConfiguration) {
        self.configuration = configuration
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

    init(configuration: BackendConfiguration, transport: @escaping Transport) {
        self.configuration = configuration
        self.transport = transport
    }

    public func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response {
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
            "Bearer \(configuration.publishableKey)",
            forHTTPHeaderField: "Authorization"
        )
        urlRequest.setValue(idempotencyKey.rawValue, forHTTPHeaderField: "X-Idempotency-Key")

        let (data, response) = try await transport(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            let payload = try JSONDecoder().decode(APIErrorPayload.self, from: data)
            throw FunctionClientError.api(
                statusCode: response.statusCode,
                code: payload.code,
                message: payload.message
            )
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct APIErrorPayload: Decodable {
    let code: String?
    let message: String
}
