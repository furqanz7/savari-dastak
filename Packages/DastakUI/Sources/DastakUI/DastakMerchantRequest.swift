import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

/// Merchant owns the timeout and reconciliation policy. A late SDK callback can
/// finish its network work, but cannot regain ownership of a released UI action.
struct DastakMerchantFunctionClient: FunctionClient {
    let base: any FunctionClient
    var timeout: Duration = .seconds(12)

    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        try await MarketplaceRequestDeadline.run(after: timeout) {
            try await base.invoke(name, request: Once(body: request), idempotencyKey: idempotencyKey)
        }
    }

    func invokeMultipart<Response: Decodable & Sendable>(
        _ name: String, fields: [String: String], file: FunctionUpload, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        try await MarketplaceRequestDeadline.run(after: timeout) {
            try await base.invokeMultipartSingleAttempt(name, fields: fields, file: file, idempotencyKey: idempotencyKey)
        }
    }

    func invokeMultipartSingleAttempt<Response: Decodable & Sendable>(
        _ name: String, fields: [String: String], file: FunctionUpload, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        try await invokeMultipart(name, fields: fields, file: file, idempotencyKey: idempotencyKey)
    }

    private struct Once<Body: Encodable & Sendable>: SingleAttemptFunctionRequest {
        let body: Body
        func encode(to encoder: any Encoder) throws { try body.encode(to: encoder) }
    }
}
