import Foundation
import MarketplaceFoundation

public struct DastakV1CatalogueCategory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let slug: String
    public let imageKey: String?
    public let sortOrder: Int
}

public struct DastakV1CatalogueSubcategory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let categoryID: UUID
    public let name: String
    public let slug: String
    public let imageKey: String?
    public let sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case categoryID = "categoryId"
        case name
        case slug
        case imageKey
        case sortOrder
    }
}

public struct DastakV1CatalogueBrand: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let slug: String
}

public struct DastakV1SKULogistics: Codable, Equatable, Sendable {
    public let weightGrams: Int?
    public let lengthMillimetres: Int?
    public let widthMillimetres: Int?
    public let heightMillimetres: Int?
    public let temperatureClass: String?
    public let fragile: Bool?
    public let bulky: Bool?
}

public struct DastakV1CatalogueSKU: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let categoryID: UUID
    public let subcategoryID: UUID
    public let brand: DastakV1CatalogueBrand?
    public let name: String
    public let slug: String
    public let variant: String?
    public let packSize: String
    public let description: String?
    public let imageKey: String?
    public let barcode: String?
    public let listPricePaise: Int
    public let sellingPricePaise: Int
    public let currencyCode: String
    public let logisticsAttributes: DastakV1SKULogistics

    public var price: Money { Money(paise: sellingPricePaise) }
    public var listPrice: Money { Money(paise: listPricePaise) }

    private enum CodingKeys: String, CodingKey {
        case id
        case categoryID = "categoryId"
        case subcategoryID = "subcategoryId"
        case brand
        case name
        case slug
        case variant
        case packSize
        case description
        case imageKey
        case barcode
        case listPricePaise
        case sellingPricePaise
        case currencyCode
        case logisticsAttributes
    }
}

public struct DastakV1CatalogueCursor: Codable, Equatable, Sendable {
    public let name: String
    public let skuID: UUID

    public init(name: String, skuID: UUID) {
        self.name = name
        self.skuID = skuID
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case skuID = "skuId"
    }
}

public struct DastakV1CatalogueSnapshot: Codable, Equatable, Sendable {
    public let catalogueVersion: String?
    public let categories: [DastakV1CatalogueCategory]
    public let subcategories: [DastakV1CatalogueSubcategory]
    public let skus: [DastakV1CatalogueSKU]
    public let nextCursor: DastakV1CatalogueCursor?
}

public struct DastakV1DeliveryAddressInput: Codable, Equatable, Sendable {
    public let label: String?
    public let line1: String
    public let line2: String?
    public let landmark: String?
    public let city: String?
    public let state: String?
    public let postalCode: String?
    public let countryCode: String
    public let latitude: Double
    public let longitude: Double
    public let instructions: String?

    public init(
        label: String?,
        line1: String,
        line2: String?,
        landmark: String?,
        city: String?,
        state: String?,
        postalCode: String?,
        countryCode: String = "IN",
        latitude: Double,
        longitude: Double,
        instructions: String?
    ) {
        self.label = label
        self.line1 = line1
        self.line2 = line2
        self.landmark = landmark
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.instructions = instructions
    }
}

public struct DastakV1RecipientInput: Codable, Equatable, Sendable {
    public let name: String
    public let phoneNumber: String

    public init(name: String, phoneNumber: String) {
        self.name = name
        self.phoneNumber = phoneNumber
    }
}

public struct DastakV1OrderLineInput: Codable, Equatable, Sendable {
    public let lineType = "RETAIL_SKU"
    public let skuID: UUID
    public let quantity: Int

    public init(skuID: UUID, quantity: Int) {
        self.skuID = skuID
        self.quantity = quantity
    }

    private enum CodingKeys: String, CodingKey {
        case lineType
        case skuID = "skuId"
        case quantity
    }
}

public struct DastakV1OrderSubmission: Codable, Equatable, Sendable {
    public let deliveryAddress: DastakV1DeliveryAddressInput
    public let recipient: DastakV1RecipientInput
    public let lines: [DastakV1OrderLineInput]

    public init(
        deliveryAddress: DastakV1DeliveryAddressInput,
        recipient: DastakV1RecipientInput,
        lines: [DastakV1OrderLineInput]
    ) {
        self.deliveryAddress = deliveryAddress
        self.recipient = recipient
        self.lines = lines
    }
}

public enum DastakV1OrderStatus: String, Codable, Equatable, Sendable {
    case created = "CREATED"
    case matching = "MATCHING"
    case fullySecured = "FULLY_SECURED"
    case awaitingPayment = "AWAITING_PAYMENT"
    case paid = "PAID"
    case preparing = "PREPARING"
    case pickupInProgress = "PICKUP_IN_PROGRESS"
    case outForDelivery = "OUT_FOR_DELIVERY"
    case delivered = "DELIVERED"
    case unavailable = "UNAVAILABLE"
    case paymentExpired = "PAYMENT_EXPIRED"
    case cancelledPrepayment = "CANCELLED_PREPAYMENT"
    case fulfilmentFailure = "DASTAK_FULFILMENT_FAILURE"
}

public struct DastakV1FulfilmentProgress: Codable, Equatable, Sendable {
    public let state: String
    public let title: String?
}

public struct DastakV1PaymentAttempt: Codable, Equatable, Sendable {
    public let id: UUID
    public let status: String
    public let failureCode: String?
    public let createdAt: String
    public let failedAt: String?
    public let succeededAt: String?
}

public struct DastakV1PaymentReservation: Codable, Equatable, Sendable {
    public let status: String
    public let amountPaise: Int
    public let currencyCode: String
    public let reservedAt: String
    public let expiresAt: String
    public let secondsRemaining: Int
    public let canAttempt: Bool
    public let canRetry: Bool
    public let latestAttempt: DastakV1PaymentAttempt?

    public var amount: Money { Money(paise: amountPaise) }
}

public enum DastakV1DeliveryVerificationStatus: String, Codable, Equatable, Sendable {
    case active = "ACTIVE"
    case blocked = "BLOCKED"
    case consumed = "CONSUMED"
    case overridden = "OVERRIDDEN"
}

public struct DastakV1DeliveryProgress: Codable, Equatable, Sendable {
    public let state: String
    public let verificationStatus: DastakV1DeliveryVerificationStatus
    public let deliveryCode: String?
    public let riderArrivedAt: String?
    public let deliveredAt: String?
    public let recipientAccountRequired: Bool
}

public struct DastakV1OrderPrice: Codable, Equatable, Sendable {
    public let snapshotKind: String
    public let subtotalPaise: Int
    public let deliveryFeePaise: Int
    public let platformFeePaise: Int
    public let discountPaise: Int
    public let taxPaise: Int
    public let totalPaise: Int
    public let currencyCode: String

    public var total: Money { Money(paise: totalPaise) }
}

public struct DastakV1OrderLine: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let lineType: String
    public let skuID: UUID?
    public let name: String
    public let variant: String?
    public let packSize: String?
    public let quantity: Int
    public let unitPricePaise: Int
    public let lineTotalPaise: Int
    public let status: String

    private enum CodingKeys: String, CodingKey {
        case id
        case lineType
        case skuID = "skuId"
        case name
        case variant
        case packSize
        case quantity
        case unitPricePaise
        case lineTotalPaise
        case status
    }
}

public struct DastakV1OrderSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayOrderNumber: String
    public let orderType: String
    public let status: DastakV1OrderStatus
    public let version: Int
    public let customerState: String?
    public let fulfilmentProgress: DastakV1FulfilmentProgress?
    public let payment: DastakV1PaymentReservation?
    public let delivery: DastakV1DeliveryProgress?
    public let price: DastakV1OrderPrice
    public let lines: [DastakV1OrderLine]
    public let submittedAt: String?
    public let fullySecuredAt: String?
    public let paymentExpiresAt: String?
    public let paidAt: String?
    public let deliveredAt: String?
    public let createdAt: String
    public let updatedAt: String
}

public struct DastakV1OrderCursor: Codable, Equatable, Sendable {
    public let createdAt: String
    public let orderID: UUID

    public init(createdAt: String, orderID: UUID) {
        self.createdAt = createdAt
        self.orderID = orderID
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt
        case orderID = "orderId"
    }
}

public struct DastakV1OrderCollection: Codable, Equatable, Sendable {
    public let orders: [DastakV1OrderSnapshot]
    public let nextCursor: DastakV1OrderCursor?
}

public protocol DastakV1CustomerClient: Sendable {
    func catalogue(
        query: String?,
        categoryID: UUID?,
        subcategoryID: UUID?,
        limit: Int,
        cursor: DastakV1CatalogueCursor?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1CatalogueSnapshot

    func submit(
        _ order: DastakV1OrderSubmission,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderSnapshot

    func orders(
        limit: Int,
        cursor: DastakV1OrderCursor?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderCollection

    func order(
        id: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderSnapshot

    func cancel(
        id: UUID,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderSnapshot
}

public struct SupabaseDastakV1CustomerClient: DastakV1CustomerClient {
    private struct CatalogueRequest: Encodable, Sendable {
        let operation = "customerCatalogue"
        let query: String?
        let categoryId: UUID?
        let subcategoryId: UUID?
        let limit: Int
        let cursor: DastakV1CatalogueCursor?
    }

    private struct OrderRequest: Encodable, Sendable {
        let operation: String
        let expectedVersion: Int?
        let order: DastakV1OrderSubmission?
        let orderId: UUID?
        let limit: Int?
        let cursor: DastakV1OrderCursor?
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func catalogue(
        query: String? = nil,
        categoryID: UUID? = nil,
        subcategoryID: UUID? = nil,
        limit: Int = 250,
        cursor: DastakV1CatalogueCursor? = nil,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1CatalogueSnapshot {
        precondition((1...250).contains(limit))
        return try await functions.invoke(
            "dastak-v1-catalogue",
            request: CatalogueRequest(
                query: query,
                categoryId: categoryID,
                subcategoryId: subcategoryID,
                limit: limit,
                cursor: cursor
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func submit(
        _ order: DastakV1OrderSubmission,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderSnapshot {
        try await invokeOrder(
            OrderRequest(
                operation: "submit",
                expectedVersion: 0,
                order: order,
                orderId: nil,
                limit: nil,
                cursor: nil
            ),
            key: idempotencyKey
        )
    }

    public func orders(
        limit: Int = 20,
        cursor: DastakV1OrderCursor? = nil,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderCollection {
        precondition((1...100).contains(limit))
        return try await invokeOrder(
            OrderRequest(
                operation: "list",
                expectedVersion: nil,
                order: nil,
                orderId: nil,
                limit: limit,
                cursor: cursor
            ),
            key: idempotencyKey
        )
    }

    public func order(
        id: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderSnapshot {
        try await invokeOrder(
            OrderRequest(
                operation: "get",
                expectedVersion: nil,
                order: nil,
                orderId: id,
                limit: nil,
                cursor: nil
            ),
            key: idempotencyKey
        )
    }

    public func cancel(
        id: UUID,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderSnapshot {
        precondition(expectedVersion > 0)
        return try await invokeOrder(
            OrderRequest(
                operation: "cancel",
                expectedVersion: expectedVersion,
                order: nil,
                orderId: id,
                limit: nil,
                cursor: nil
            ),
            key: idempotencyKey
        )
    }

    private func invokeOrder<Response: Decodable & Sendable>(
        _ request: OrderRequest,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke(
            "dastak-v1-orders",
            request: request,
            idempotencyKey: key
        )
    }
}
