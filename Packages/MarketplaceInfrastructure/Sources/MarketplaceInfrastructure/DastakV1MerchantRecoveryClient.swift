import Foundation
import MarketplaceFoundation

public struct DastakV1MerchantRecoveryCase: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let orderLineId: UUID
    public let status: String
    public let reason: String
    public let openedAt: String
    public let resolvedAt: String?
}

public struct DastakV1MerchantProblemReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let statusAtReport: String
    public let reason: String
    public let reportedAt: String
}

public struct DastakV1RecoveryOpportunity: Codable, Equatable, Identifiable, Sendable {
    public struct SKU: Codable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let variantName: String?
        public let packSize: String
        public let imageKey: String?
    }
    public let id: UUID
    public let recoveryCaseId: UUID
    public let orderId: UUID
    public let orderLineId: UUID
    public let status: String
    public let requestedQuantity: Int
    public let startedAt: String
    public let expiresAt: String
    public let promisedPrepMinutes: Int?
    public let version: Int
    public let branch: DastakV1MerchantBranch
    public let sku: SKU
}

/// The endpoint serves independent lanes. A malformed/missing lane is unknown, not empty.
public struct DastakV1MerchantRecoveryFeeds: Decodable, Sendable {
    public let fulfilments: [DastakV1MerchantFulfilment]?
    public let recoveryOpportunities: [DastakV1RecoveryOpportunity]?
    public let returnReceipts: [DastakV1MerchantReturnReceipt]?
    public let settlements: [DastakV1MerchantSettlement]?
    private enum CodingKeys: String, CodingKey { case fulfilments, recoveryOpportunities, returnReceipts, settlements }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fulfilments = try? values.decode([DastakV1MerchantFulfilment].self, forKey: .fulfilments)
        let recovery = try? values.decode([DastakV1RecoveryOpportunity].self, forKey: .recoveryOpportunities)
        recoveryOpportunities = recovery.flatMap { offers in
            offers.allSatisfy { $0.version > 0 && $0.requestedQuantity > 0 && !$0.sku.packSize.isEmpty }
                ? offers : nil
        }
        let returns = try? values.decode([DastakV1MerchantReturnReceipt].self, forKey: .returnReceipts)
        returnReceipts = returns.flatMap { receipts in
            receipts.allSatisfy { $0.packageCount > 0 } && Set(receipts.map(\.id)).count == receipts.count
                ? receipts : nil
        }
        let entries = try? values.decode([DastakV1MerchantSettlement].self, forKey: .settlements)
        settlements = entries.flatMap { Set($0.map(\.id)).count == $0.count ? $0 : nil }
    }
}

public struct DastakV1ExactFailureReceipt: Decodable, Sendable {
    public let recoveryCaseId: UUID
    public let orderId: UUID
    public let orderLineId: UUID
    public let status: String
    public let exactSkuId: UUID
    public let quantity: Int
    public let customerPaymentChanged: Bool
}

public struct DastakV1RecoveryResponseReceipt: Decodable, Sendable {
    public let recoveryOpportunityId: UUID
    public let recoveryCaseId: UUID
    public let status: String
    public let replacementFulfilmentId: UUID?
    public let exactSkuId: UUID?
    public let quantity: Int?
    public let additionalCustomerPaymentPaise: Int?
}

public struct SupabaseDastakV1MerchantRecoveryClient: Sendable {
    private let functions: any FunctionClient
    public init(functions: any FunctionClient) { self.functions = functions }
    private struct Request: SingleAttemptFunctionRequest {
        let operation: String
        var allowsAutomaticRetries: Bool { operation == "merchantFulfilments" }
        var limit: Int?
        var fulfilmentId: UUID?
        var orderLineId: UUID?
        var recoveryOpportunityId: UUID?
        var reason: String?
        var response: String?
        var promisedPrepMinutes: Int?
        var expectedVersion: Int?
    }
    public func feeds(idempotencyKey: IdempotencyKey) async throws -> DastakV1MerchantRecoveryFeeds {
        try await functions.invoke("dastak-v1-orders", request: Request(operation: "merchantFulfilments", limit: 100), idempotencyKey: idempotencyKey)
    }
    public func reportExactFailure(fulfilmentID: UUID, lineID: UUID, reason: String, version: Int,
        key: IdempotencyKey) async throws -> DastakV1ExactFailureReceipt {
        try await functions.invoke("dastak-v1-orders", request: Request(operation: "reportExactSkuFailure",
            fulfilmentId: fulfilmentID, orderLineId: lineID, reason: reason, expectedVersion: version), idempotencyKey: key)
    }
    public func reportProblem(fulfilmentID: UUID, reason: String, version: Int,
        key: IdempotencyKey) async throws -> DastakV1MerchantFulfilment {
        try await functions.invoke("dastak-v1-orders", request: Request(operation: "reportFulfilmentProblem",
            fulfilmentId: fulfilmentID, reason: reason, expectedVersion: version), idempotencyKey: key)
    }
    public func respond(offerID: UUID, accept: Bool, prepMinutes: Int, version: Int,
        key: IdempotencyKey) async throws -> DastakV1RecoveryResponseReceipt {
        try await functions.invoke("dastak-v1-orders", request: Request(operation: "respondExactSkuRecoveryOffer",
            recoveryOpportunityId: offerID, response: accept ? "ACCEPT" : "UNAVAILABLE",
            promisedPrepMinutes: accept ? prepMinutes : nil, expectedVersion: version), idempotencyKey: key)
    }
}
