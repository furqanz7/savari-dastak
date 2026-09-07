import Foundation
import MarketplaceFoundation

public struct DastakV1MerchantOpportunity: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayOrderNumber: String
    public let requestScope: String
    public let status: String
    public let reservationState: String?
    public let version: Int
    public let branch: DastakV1MerchantBranch
    public let expiresAt: String
    public let secondsRemaining: Int
    public let prepTimeOptionsMinutes: [Int]
    public let lines: [DastakV1MerchantLine]
}

public struct DastakV1RestaurantRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let orderId: UUID
    public let displayOrderNumber: String
    public let status: String
    public let version: Int
    public let branch: DastakV1MerchantBranch
    public let offeredAt: String
    public let softThresholdWarning: Bool
    public let lines: [DastakV1MerchantLine]
}

public protocol DastakV1MerchantInboxClient: Sendable {
    func opportunities(idempotencyKey: IdempotencyKey) async throws -> [DastakV1MerchantOpportunity]
    func restaurantRequests(idempotencyKey: IdempotencyKey) async throws -> [DastakV1RestaurantRequest]
    func respond(
        opportunity: DastakV1MerchantOpportunity, accept: Bool,
        prepMinutes: Int, idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantOpportunity
    func respond(
        request: DastakV1RestaurantRequest, accept: Bool,
        prepMinutes: Int, reason: String?, idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1RestaurantRequest
}

public struct SupabaseDastakV1MerchantInboxClient: DastakV1MerchantInboxClient {
    private let functions: any FunctionClient
    public init(functions: any FunctionClient) { self.functions = functions }

    private struct Request: Encodable, Sendable {
        let operation: String
        var limit: Int? = nil
        var opportunityId: UUID? = nil
        var requestId: UUID? = nil
        var requestScope: String? = nil
        var response: String? = nil
        var promisedPrepMinutes: Int? = nil
        var reason: String? = nil
        var expectedVersion: Int? = nil
    }
    private struct Opportunities: Decodable, Sendable { let opportunities: [DastakV1MerchantOpportunity] }
    private struct Requests: Decodable, Sendable { let requests: [DastakV1RestaurantRequest] }

    public func opportunities(idempotencyKey: IdempotencyKey) async throws -> [DastakV1MerchantOpportunity] {
        // This authenticated endpoint also records the branch reachability heartbeat.
        let result: Opportunities = try await functions.invoke(
            "dastak-v1-orders", request: Request(operation: "merchantOpportunities", limit: 100),
            idempotencyKey: idempotencyKey
        )
        return result.opportunities
    }

    public func restaurantRequests(idempotencyKey: IdempotencyKey) async throws -> [DastakV1RestaurantRequest] {
        let result: Requests = try await functions.invoke(
            "dastak-v1-orders", request: Request(operation: "restaurantRequests", limit: 100),
            idempotencyKey: idempotencyKey
        )
        return result.requests
    }

    public func respond(
        opportunity: DastakV1MerchantOpportunity, accept: Bool,
        prepMinutes: Int, idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantOpportunity {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: accept ? "acceptMerchantOpportunity" : "declineMerchantOpportunity",
                opportunityId: opportunity.id, requestScope: opportunity.requestScope,
                promisedPrepMinutes: accept ? prepMinutes : nil, expectedVersion: opportunity.version
            ), idempotencyKey: idempotencyKey
        )
    }

    public func respond(
        request: DastakV1RestaurantRequest, accept: Bool,
        prepMinutes: Int, reason: String?, idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1RestaurantRequest {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "respondRestaurantRequest", requestId: request.id,
                response: accept ? "CONFIRM" : "DECLINE",
                promisedPrepMinutes: accept ? prepMinutes : nil,
                reason: accept ? nil : reason, expectedVersion: request.version
            ), idempotencyKey: idempotencyKey
        )
    }
}
