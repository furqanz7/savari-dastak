import Foundation
import MarketplaceFoundation

public struct DastakEarningsSnapshot: Codable, Equatable, Sendable {
    public let currency: String
    public let completedPaise: Int
    public let pendingPaise: Int
    public let thisWeekPaise: Int
}

public protocol DastakEarningsClient: Sendable {
    func merchantSnapshot(idempotencyKey: IdempotencyKey) async throws -> DastakEarningsSnapshot
    func deliveryPartnerSnapshot(idempotencyKey: IdempotencyKey) async throws -> DastakEarningsSnapshot
}

public struct SupabaseDastakEarningsClient: DastakEarningsClient {
    private struct Request: Encodable, Sendable { let operation: String }
    private let functions: any FunctionClient

    public init(functions: any FunctionClient) { self.functions = functions }

    public func merchantSnapshot(idempotencyKey: IdempotencyKey) async throws -> DastakEarningsSnapshot {
        try await snapshot(operation: "merchantSnapshot", key: idempotencyKey)
    }

    public func deliveryPartnerSnapshot(idempotencyKey: IdempotencyKey) async throws -> DastakEarningsSnapshot {
        try await snapshot(operation: "deliveryPartnerSnapshot", key: idempotencyKey)
    }

    private func snapshot(operation: String, key: IdempotencyKey) async throws -> DastakEarningsSnapshot {
        try await functions.invoke("earnings", request: Request(operation: operation), idempotencyKey: key)
    }
}
