import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

/// A structured task-group timeout still waits for a child that ignores
/// cancellation. Delivery must release its UI lease even when auth/transport
/// does not return. The losing task has no access to delivery model state.
typealias DastakDeliveryDeadline = MarketplaceRequestDeadline

/// Scoped to Delivery: one bounded request, followed by explicit reconciliation.
/// A timeout never implies a mutation failed; the durable command keeps its key.
struct DastakDeliveryFunctionClient: FunctionClient {
    let base: any FunctionClient
    var timeout: Duration = .seconds(12)
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        try await DastakDeliveryDeadline.run(after: timeout) {
            try await base.invoke(name, request: OnceRequest(body: request), idempotencyKey: idempotencyKey)
        }
    }
    private struct OnceRequest<Body: Encodable & Sendable>: SingleAttemptFunctionRequest {
        let body: Body
        func encode(to encoder: any Encoder) throws { try body.encode(to: encoder) }
    }
}
