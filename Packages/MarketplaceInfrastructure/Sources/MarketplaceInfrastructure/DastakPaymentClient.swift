import Foundation
import MarketplaceFoundation

public enum DastakPaymentState: String, Codable, Equatable, Sendable {
    case pending
    case captured
    case refundPending = "refund_pending"
    case refunded
    case cancelled
}

public enum DastakSettlementState: String, Codable, Equatable, Sendable {
    case unallocated
    case settled
}

public struct DastakPaymentRateCard: Codable, Equatable, Sendable {
    public let serviceZoneID: UUID
    public let deliveryFee: Money
    public let merchantCommissionBasisPoints: Int
    public let courierPayout: Money
    public let active: Bool
    public let version: Int64

    private enum CodingKeys: String, CodingKey {
        case serviceZoneID = "serviceZoneId"
        case deliveryFee
        case merchantCommissionBasisPoints = "merchantCommissionBps"
        case courierPayout
        case active
        case version
    }
}

public struct DastakOrderFinancialSnapshot: Codable, Equatable, Sendable {
    public let orderID: UUID
    public let paymentState: DastakPaymentState
    public let settlementState: DastakSettlementState
    public let currency: String
    public let gross: Money
    public let captured: Money
    public let refundReserved: Money
    public let refunded: Money
    public let merchantPayable: Money
    public let courierPayout: Money
    public let platformMerchantCommission: Money
    public let platformDeliveryMargin: Money
    public let version: Int64
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case orderID = "orderId"
        case paymentState
        case settlementState
        case currency
        case gross
        case captured
        case refundReserved
        case refunded
        case merchantPayable
        case courierPayout
        case platformMerchantCommission
        case platformDeliveryMargin
        case version
        case updatedAt
    }
}

public protocol DastakPaymentClient: Sendable {
    func ownerUpsertRateCard(
        serviceZoneID: UUID,
        deliveryFee: Money,
        merchantCommissionBasisPoints: Int,
        courierPayout: Money,
        active: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakPaymentRateCard

    func ownerOrderSnapshot(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakOrderFinancialSnapshot
}

public struct SupabaseDastakPaymentClient: DastakPaymentClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let serviceZoneId: UUID?
        let orderId: UUID?
        let deliveryFeePaise: Int?
        let merchantCommissionBps: Int?
        let courierPayoutPaise: Int?
        let active: Bool?

        init(
            operation: String,
            serviceZoneId: UUID? = nil,
            orderId: UUID? = nil,
            deliveryFeePaise: Int? = nil,
            merchantCommissionBps: Int? = nil,
            courierPayoutPaise: Int? = nil,
            active: Bool? = nil
        ) {
            self.operation = operation
            self.serviceZoneId = serviceZoneId
            self.orderId = orderId
            self.deliveryFeePaise = deliveryFeePaise
            self.merchantCommissionBps = merchantCommissionBps
            self.courierPayoutPaise = courierPayoutPaise
            self.active = active
        }
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func ownerUpsertRateCard(
        serviceZoneID: UUID,
        deliveryFee: Money,
        merchantCommissionBasisPoints: Int,
        courierPayout: Money,
        active: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakPaymentRateCard {
        try await functions.invoke(
            "payment-ledger",
            request: Request(
                operation: "ownerUpsertRateCard",
                serviceZoneId: serviceZoneID,
                deliveryFeePaise: deliveryFee.paise,
                merchantCommissionBps: merchantCommissionBasisPoints,
                courierPayoutPaise: courierPayout.paise,
                active: active
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func ownerOrderSnapshot(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakOrderFinancialSnapshot {
        try await functions.invoke(
            "payment-ledger",
            request: Request(operation: "ownerOrderSnapshot", orderId: orderID),
            idempotencyKey: idempotencyKey
        )
    }
}
