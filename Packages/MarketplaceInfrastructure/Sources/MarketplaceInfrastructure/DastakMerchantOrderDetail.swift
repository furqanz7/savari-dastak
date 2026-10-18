import Foundation
import MarketplaceFoundation

public struct DastakMerchantDetailTarget: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case fulfilment = "FULFILMENT", opportunity = "OPPORTUNITY", restaurantRequest = "RESTAURANT_REQUEST", recovery = "RECOVERY", returned = "RETURN" }
    public let kind: Kind
    public let id: UUID
    public let branchID: UUID
    public init(kind: Kind, id: UUID, branchID: UUID) { self.kind = kind; self.id = id; self.branchID = branchID }
    private enum CodingKeys: String, CodingKey { case kind, id; case branchID = "branchId" }
}

public struct DastakMerchantOrderDetail: Decodable, Sendable {
    public struct Order: Decodable, Sendable {
        public let id: UUID
        public let displayOrderNumber: String
        public let status: String
        public let orderType: String
        public let createdAt: String
    }
    public struct Record: Decodable, Identifiable, Sendable {
        public let id: UUID
        public let kind: String
        public let status: String
        public let version: Int
        public let lines: [DastakV1MerchantLine]
        public let productSubtotalPaise: Int?
        public let promisedPrepMinutes: Int?
        public let packageCount: Int?
        public let prepStartedAt: String?
        public let estimatedReadyAt: String?
        public let actualReadyAt: String?
        public let offeredAt: String?
        public let respondedAt: String?
        public let responseReason: String?
        public let evidence: [Evidence]
        public let problems: [DastakV1MerchantProblemReport]
        public let recovery: [Recovery]
        public let delivery: Delivery
    }
    public struct Evidence: Decodable, Identifiable, Sendable { public let id: UUID; public let contentType: String; public let capturedAt: String }
    public struct Recovery: Decodable, Identifiable, Sendable { public let id: UUID; public let status: String; public let reason: String; public let openedAt: String; public let resolvedAt: String? }
    public struct Delivery: Decodable, Sendable { public let riderName: String?; public let riderAssigned: Bool?; public let stopStatus: String?; public let pickedUpAt: String? }
    public let target: DastakMerchantDetailTarget
    public let branch: DastakV1MerchantBranch
    public let order: Order
    public let records: [Record]
    public let recoveryOffers: [DastakV1RecoveryOpportunity]
    public let returns: [DastakV1MerchantReturnReceipt]
    public let settlements: [DastakV1MerchantSettlement]

    public func validates(_ requested: DastakMerchantDetailTarget) -> Bool {
        target == requested && branch.id == requested.branchID
            && Set(records.map { "\($0.kind):\($0.id)" }).count == records.count
            && records.allSatisfy { ["FULFILMENT", "OPPORTUNITY", "RESTAURANT_REQUEST"].contains($0.kind)
                && $0.version > 0 && $0.productSubtotalPaise.map { $0 >= 0 } != false
                && $0.lines.allSatisfy { $0.quantity > 0 && $0.lineSubtotalPaise.map { $0 >= 0 } != false } }
            && returns.allSatisfy { $0.branch.id == requested.branchID && $0.orderId == order.id && $0.receiptCode == nil }
            && settlements.allSatisfy { $0.orderId == order.id }
            && recoveryOffers.allSatisfy { $0.branch.id == requested.branchID && $0.orderId == order.id && $0.requestedQuantity > 0 }
            && (requested.kind == .recovery ? recoveryOffers.contains { $0.id == requested.id }
                : requested.kind == .returned ? returns.contains { $0.id == requested.id }
                : records.contains { $0.kind == requested.kind.rawValue && $0.id == requested.id })
    }
}

public struct SupabaseDastakMerchantOrderDetailClient: Sendable {
    private let functions: any FunctionClient
    public init(functions: any FunctionClient) { self.functions = functions }
    private struct Request: Encodable, Sendable {
        let operation = "merchantOrderDetail"
        let branchId: UUID
        let targetKind: String
        let targetId: UUID
    }
    public func get(_ target: DastakMerchantDetailTarget, key: IdempotencyKey) async throws -> DastakMerchantOrderDetail {
        let value: DastakMerchantOrderDetail = try await functions.invoke("dastak-v1-orders",
            request: Request(branchId: target.branchID, targetKind: target.kind.rawValue, targetId: target.id), idempotencyKey: key)
        guard value.validates(target) else { throw FunctionClientError.invalidResponse }
        return value
    }
}
