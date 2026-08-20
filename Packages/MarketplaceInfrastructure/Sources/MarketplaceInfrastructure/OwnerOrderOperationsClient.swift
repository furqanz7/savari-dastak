import Foundation
import MarketplaceFoundation

public enum OwnerOrderExceptionKind: String, Codable, Equatable, Sendable {
    case support
    case refundReview = "refund_review"
    case handoffLocked = "handoff_locked"
    case stalledOrder = "stalled_order"
}

public enum OwnerOrderExceptionSeverity: String, Codable, Equatable, Sendable {
    case critical
    case attention
}

public enum OwnerOrderEntityKind: String, Codable, Equatable, Sendable {
    case merchantOrder = "merchant_order"
    case parcelDelivery = "parcel_delivery"
}

public enum OwnerRefundOutcome: String, Codable, CaseIterable, Equatable, Sendable {
    case approveFull = "approve_full"
    case approveItemsOnly = "approve_items_only"
    case deny
}

public enum OwnerRefundFaultSource: String, Codable, CaseIterable, Equatable, Sendable {
    case merchant
    case dastak
}

public struct OwnerOrderException: Codable, Equatable, Identifiable, Sendable {
    public let exceptionID: String
    public let kind: OwnerOrderExceptionKind
    public let severity: OwnerOrderExceptionSeverity
    public let entityKind: OwnerOrderEntityKind
    public let entityID: UUID
    public let title: String
    public let detail: String
    public let status: String
    public let purpose: MerchantOrderHandoffPurpose?
    public let occurredAt: String

    public var id: String { exceptionID }

    private enum CodingKeys: String, CodingKey {
        case exceptionID = "exceptionId"
        case kind, severity, entityKind
        case entityID = "entityId"
        case title, detail, status, purpose, occurredAt
    }
}

public struct OwnerOrderOperationsSummary: Codable, Equatable, Sendable {
    public let openSupport: Int
    public let refundReviews: Int
    public let lockedHandoffs: Int
    public let stalledOrders: Int
    public let totalExceptions: Int
}

public struct OwnerOrderOperationsSnapshot: Codable, Equatable, Sendable {
    public let summary: OwnerOrderOperationsSummary
    public let exceptions: [OwnerOrderException]
    public let parcels: [ParcelDelivery]
}

public struct OwnerOrderReconciliation: Codable, Equatable, Sendable {
    public let merchantOrdersRecovered: Int
    public let parcelsRecovered: Int
    public let merchantOffersCreated: Int
    public let parcelOffersCreated: Int
    public let reconciledAt: String
}

public protocol OwnerOrderOperationsClient: Sendable {
    func snapshot(limit: Int, idempotencyKey: IdempotencyKey) async throws -> OwnerOrderOperationsSnapshot
    func resolveSupport(
        caseID: UUID,
        resolution: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerOrderSupportCase
    func resetParcelHandoff(
        parcelID: UUID,
        purpose: MerchantOrderHandoffPurpose,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelDelivery
    func reviewRefund(
        orderID: UUID,
        outcome: OwnerRefundOutcome,
        faultSource: OwnerRefundFaultSource?,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot
    func reconcile(idempotencyKey: IdempotencyKey) async throws -> OwnerOrderReconciliation
}

public struct SupabaseOwnerOrderOperationsClient: OwnerOrderOperationsClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let limit: Int?
        let caseId: UUID?
        let resolution: String?
        let parcelId: UUID?
        let purpose: MerchantOrderHandoffPurpose?
        let reason: String?
        let orderId: UUID?
        let outcome: OwnerRefundOutcome?
        let faultSource: OwnerRefundFaultSource?

        init(
            operation: String,
            limit: Int? = nil,
            caseId: UUID? = nil,
            resolution: String? = nil,
            parcelId: UUID? = nil,
            purpose: MerchantOrderHandoffPurpose? = nil,
            reason: String? = nil,
            orderId: UUID? = nil,
            outcome: OwnerRefundOutcome? = nil,
            faultSource: OwnerRefundFaultSource? = nil
        ) {
            self.operation = operation
            self.limit = limit
            self.caseId = caseId
            self.resolution = resolution
            self.parcelId = parcelId
            self.purpose = purpose
            self.reason = reason
            self.orderId = orderId
            self.outcome = outcome
            self.faultSource = faultSource
        }
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func snapshot(
        limit: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> OwnerOrderOperationsSnapshot {
        try await invoke(Request(operation: "ownerOperations", limit: limit), key: idempotencyKey)
    }

    public func resolveSupport(
        caseID: UUID,
        resolution: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerOrderSupportCase {
        try await invoke(
            Request(operation: "ownerResolveSupport", caseId: caseID, resolution: resolution),
            key: idempotencyKey
        )
    }

    public func resetParcelHandoff(
        parcelID: UUID,
        purpose: MerchantOrderHandoffPurpose,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelDelivery {
        try await invoke(
            Request(
                operation: "ownerResetParcelHandoff",
                parcelId: parcelID,
                purpose: purpose,
                reason: reason
            ),
            key: idempotencyKey
        )
    }

    public func reviewRefund(
        orderID: UUID,
        outcome: OwnerRefundOutcome,
        faultSource: OwnerRefundFaultSource?,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(
                operation: "ownerReviewRefund",
                reason: reason,
                orderId: orderID,
                outcome: outcome,
                faultSource: faultSource
            ),
            key: idempotencyKey
        )
    }

    public func reconcile(
        idempotencyKey: IdempotencyKey
    ) async throws -> OwnerOrderReconciliation {
        try await invoke(Request(operation: "ownerReconcile"), key: idempotencyKey)
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke("merchant-orders", request: request, idempotencyKey: key)
    }
}
