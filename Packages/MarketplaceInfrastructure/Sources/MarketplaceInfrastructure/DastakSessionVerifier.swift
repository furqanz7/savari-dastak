import Foundation
import MarketplaceFoundation

enum DastakSessionVerifier {
    static func verify(
        client: any AccountSessionClient,
        device: AccountSessionDevice,
        refreshSession: @Sendable () async throws -> Void
    ) async throws {
        let key = IdempotencyKey(rawValue: UUID().uuidString)!
        try Task.checkCancellation()
        do {
            _ = try await client.snapshot(device: device, idempotencyKey: key)
        } catch let FunctionClientError.api(status, _, _) where status == 401 {
            try Task.checkCancellation()
            try await refreshSession()
            try Task.checkCancellation()
            // Same registration, same key. No other mutation is replayed here.
            _ = try await client.snapshot(device: device, idempotencyKey: key)
        }
    }
}
