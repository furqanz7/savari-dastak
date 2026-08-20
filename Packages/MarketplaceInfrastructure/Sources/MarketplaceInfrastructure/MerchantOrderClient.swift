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
    public let deliveryDistanceMeters: Int
    public let total: Money
    public let dropoff: GeoPoint
    public let deliveryAddress: MerchantOrderAddressSnapshot?
    public let expiresAt: String
    public let controlledCategory: ControlledOrderMetadata?

    private enum CodingKeys: String, CodingKey {
        case quoteID = "quoteId"
        case storeID = "storeId"
        case lines
        case itemSubtotal
        case deliveryFee
        case deliveryDistanceMeters
        case total
        case dropoff
        case deliveryAddress
        case expiresAt
        case controlledCategory
    }
}

public struct MerchantOrderAddressSnapshot: Codable, Equatable, Sendable {
    public let label: String?
    public let address: String?
    public let details: String?
    public let displayAddress: String?
}

public struct CustomerCourierSnapshot: Codable, Equatable, Sendable {
    public let displayName: String
    public let phoneNumber: String
    public let deliveryMethod: DeliveryMethod
    public let location: GeoPoint?
    public let lastSeenAt: String?
}

public struct MerchantOrderStoreSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let phoneNumber: String
    public let pickup: AddressedGeoPoint
}

public struct MerchantOrderTimeline: Codable, Equatable, Sendable {
    public let createdAt: String
    public let acceptedAt: String?
    public let readyAt: String?
    public let assignedAt: String?
    public let enRouteToPickupAt: String?
    public let atStoreAt: String?
    public let pickedUpAt: String?
    public let inTransitAt: String?
    public let deliveredAt: String?
    public let cancelledAt: String?
}

public enum MerchantOrderHandoffPurpose: String, Codable, Equatable, Sendable {
    case pickup
    case delivery
}

public struct MerchantOrderHandoffCode: Codable, Equatable, Sendable {
    public let purpose: MerchantOrderHandoffPurpose
    public let code: String
    public let expiresAt: String
}

public struct MerchantOrderSnapshot: Codable, Equatable, Sendable {
    public let orderID: UUID
    public let storeID: UUID
    public let status: MerchantOrderStatus
    public let paymentState: MerchantOrderPaymentState
    public let lines: [MerchantOrderLineSnapshot]
    public let itemSubtotal: Money
    public let deliveryFee: Money
    public let deliveryDistanceMeters: Int
    public let total: Money
    public let dropoff: GeoPoint
    public let deliveryAddress: MerchantOrderAddressSnapshot?
    public let store: MerchantOrderStoreSnapshot?
    public let courier: CustomerCourierSnapshot?
    public let timeline: MerchantOrderTimeline?
    public let stateVersion: Int64
    public let refundDecision: MerchantOrderRefundDecision?
    public let handoffCode: MerchantOrderHandoffCode?
    public let controlledCategory: ControlledOrderMetadata?
    public var customerActions: CustomerOrderActions? = nil
    public var supportCases: [CustomerOrderSupportCase]? = nil
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
        case deliveryDistanceMeters
        case total
        case dropoff
        case deliveryAddress
        case store
        case courier
        case timeline
        case stateVersion
        case refundDecision
        case handoffCode
        case controlledCategory
        case customerActions
        case supportCases
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

    func customerDetail(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot

    func createCustomerSupport(
        orderID: UUID,
        category: CustomerOrderSupportCategory,
        message: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerOrderSupportResponse

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

    func merchantConfirmReturn(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot

    func customerCancel(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot

    func ownerResetHandoffCode(
        orderID: UUID,
        purpose: MerchantOrderHandoffPurpose,
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
        let purpose: MerchantOrderHandoffPurpose?
        let category: CustomerOrderSupportCategory?
        let message: String?

        init(
            operation: String,
            storeId: UUID? = nil,
            quoteId: UUID? = nil,
            orderId: UUID? = nil,
            lines: [MerchantOrderLineInput]? = nil,
            dropoff: GeoPoint? = nil,
            reason: String? = nil,
            purpose: MerchantOrderHandoffPurpose? = nil,
            category: CustomerOrderSupportCategory? = nil,
            message: String? = nil
        ) {
            self.operation = operation
            self.storeId = storeId
            self.quoteId = quoteId
            self.orderId = orderId
            self.lines = lines
            self.dropoff = dropoff
            self.reason = reason
            self.purpose = purpose
            self.category = category
            self.message = message
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

    public func customerDetail(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(operation: "customerDetail", orderId: orderID),
            key: idempotencyKey
        )
    }

    public func createCustomerSupport(
        orderID: UUID,
        category: CustomerOrderSupportCategory,
        message: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerOrderSupportResponse {
        try await invoke(
            Request(
                operation: "customerSupport",
                orderId: orderID,
                category: category,
                message: message
            ),
            key: idempotencyKey
        )
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

    public func merchantConfirmReturn(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(
                operation: "merchantConfirmReturn",
                orderId: orderID,
                reason: reason
            ),
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

    public func ownerResetHandoffCode(
        orderID: UUID,
        purpose: MerchantOrderHandoffPurpose,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(
            Request(
                operation: "ownerResetHandoff",
                orderId: orderID,
                reason: reason,
                purpose: purpose
            ),
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
