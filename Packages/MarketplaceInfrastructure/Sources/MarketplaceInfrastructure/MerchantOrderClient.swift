import Foundation
import MarketplaceFoundation

public enum MerchantOrderStatus: String, Codable, Equatable, Sendable {
    case paymentPending = "payment_pending"
    case paid
    case merchantAccepted = "merchant_accepted"
    case ready
    case assigned
    case enRouteToPickup = "en_route_to_pickup"
    case atStore = "at_store"
    case pickedUp = "picked_up"
    case inTransit = "in_transit"
    case delivered
    case cancelled
    case returningToMerchant = "returning_to_merchant"
}

public enum MerchantOrderPaymentState: String, Codable, Equatable, Sendable {
    case paymentPending = "payment_pending"
    case paid
    case notCollected = "not_collected"
    case refundPending = "refund_pending"
    case refunded
}

public enum MerchantOrderRefundEligibility: String, Codable, Equatable, Sendable {
    case noPayment = "no_payment"
    case fullRefund = "full_refund"
    case ownerReviewRequired = "owner_review_required"
    case merchantFaultFullRefund = "merchant_fault_full_refund"
    case deliveryFeeRetainedUnlessFault = "delivery_fee_retained_unless_fault"
}

public enum MerchantOrderRefundDecisionStatus: String, Codable, Equatable, Sendable {
    case notRequired = "not_required"
    case eligible
    case reviewRequired = "review_required"
    case denied
}

public struct MerchantOrderLineInput: Codable, Equatable, Sendable {
    public let productID: UUID
    public let quantity: Int

    private enum CodingKeys: String, CodingKey {
        case productID = "productId"
        case quantity
    }

    public init(productID: UUID, quantity: Int) {
        self.productID = productID
        self.quantity = quantity
    }
}

public struct MerchantOrderLineSnapshot: Codable, Equatable, Sendable {
    public let productID: UUID
    public let name: String
    public let unitLabel: String
    public let unitPrice: Money
    public let quantity: Int
    public let lineSubtotal: Money

    private enum CodingKeys: String, CodingKey {
        case productID = "productId"
        case name
        case unitLabel
        case unitPrice
        case quantity
        case lineSubtotal
    }
}

public struct MerchantOrderRefundDecision: Codable, Equatable, Sendable {
    public let decisionID: UUID
    public let eligibility: MerchantOrderRefundEligibility
    public let decisionStatus: MerchantOrderRefundDecisionStatus
    public let itemRefund: Money?
    public let deliveryFeeRefund: Money?
    public let reason: String
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case decisionID = "decisionId"
        case eligibility
        case decisionStatus
        case itemRefund
        case deliveryFeeRefund
        case reason
        case createdAt
    }
}

public struct MerchantOrderQuote: Codable, Equatable, Sendable {
    public let quoteID: UUID
    public let storeID: UUID
    public let lines: [MerchantOrderLineSnapshot]
    public let itemSubtotal: Money
    public let deliveryFee: Money
    public let total: Money
    public let dropoff: GeoPoint
    public let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case quoteID = "quoteId"
        case storeID = "storeId"
        case lines
        case itemSubtotal
        case deliveryFee
        case total
        case dropoff
        case expiresAt
    }
}

public struct MerchantOrderSnapshot: Codable, Equatable, Sendable {
    public let orderID: UUID
    public let storeID: UUID
    public let status: MerchantOrderStatus
    public let paymentState: MerchantOrderPaymentState
    public let lines: [MerchantOrderLineSnapshot]
    public let itemSubtotal: Money
    public let deliveryFee: Money
    public let total: Money
    public let dropoff: GeoPoint
    public let stateVersion: Int64
    public let refundDecision: MerchantOrderRefundDecision?
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case orderID = "orderId"
        case storeID = "storeId"
        case status
        case paymentState
        case lines
        case itemSubtotal
        case deliveryFee
        case total
        case dropoff
        case stateVersion
        case refundDecision
        case createdAt
        case updatedAt
    }
}

public struct MerchantOrderCollection: Codable, Equatable, Sendable {
    public let orders: [MerchantOrderSnapshot]
}

public protocol MerchantOrderClient: Sendable {
    func quote(
        storeID: UUID,
        lines: [MerchantOrderLineInput],
        dropoff: GeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderQuote

    func create(
        quoteID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot

    func customerSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderCollection

    func merchantSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderCollection

    func merchantAccept(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot

    func merchantReject(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot

    func merchantMarkReady(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot

    func customerCancel(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot
}

public struct SupabaseMerchantOrderClient: MerchantOrderClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let storeId: UUID?
        let quoteId: UUID?
        let orderId: UUID?
        let lines: [MerchantOrderLineInput]?
        let dropoff: GeoPoint?
        let reason: String?

        init(
            operation: String,
            storeId: UUID? = nil,
            quoteId: UUID? = nil,
            orderId: UUID? = nil,
            lines: [MerchantOrderLineInput]? = nil,
            dropoff: GeoPoint? = nil,
            reason: String? = nil
        ) {
            self.operation = operation
            self.storeId = storeId
            self.quoteId = quoteId
            self.orderId = orderId
            self.lines = lines
            self.dropoff = dropoff
            self.reason = reason
        }
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func quote(
        storeID: UUID,
        lines: [MerchantOrderLineInput],
        dropoff: GeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderQuote {
        try await invoke(
            Request(operation: "quote", storeId: storeID, lines: lines, dropoff: dropoff),
            key: idempotencyKey
        )
    }

    public func create(
        quoteID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(operation: "create", quoteId: quoteID),
            key: idempotencyKey
        )
    }

    public func customerSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderCollection {
        try await invoke(Request(operation: "customerSnapshot"), key: idempotencyKey)
    }

    public func merchantSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderCollection {
        try await invoke(Request(operation: "merchantSnapshot"), key: idempotencyKey)
    }

    public func merchantAccept(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(operation: "merchantAccept", orderId: orderID),
            key: idempotencyKey
        )
    }

    public func merchantReject(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(operation: "merchantReject", orderId: orderID, reason: reason),
            key: idempotencyKey
        )
    }

    public func merchantMarkReady(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(operation: "merchantMarkReady", orderId: orderID),
            key: idempotencyKey
        )
    }

    public func customerCancel(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(operation: "customerCancel", orderId: orderID, reason: reason),
            key: idempotencyKey
        )
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke(
            "merchant-orders",
            request: request,
            idempotencyKey: key
        )
    }
}
