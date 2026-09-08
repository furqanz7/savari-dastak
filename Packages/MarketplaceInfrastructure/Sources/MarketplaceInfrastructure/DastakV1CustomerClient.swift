import Foundation
import MarketplaceFoundation

public struct DastakV1CatalogueNavigationSection: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let sortOrder: Int
}

public struct DastakV1CatalogueCategory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let categoryTypeID: UUID?
    public let name: String
    public let slug: String
    public let imageKey: String?
    public let previewImageKeys: [String]?
    public let navigationSection: DastakV1CatalogueNavigationSection?
    public let status: String?
    public let requiresControlledFlow: Bool?
    public let sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, imageKey, previewImageKeys, navigationSection
        case status, requiresControlledFlow, sortOrder
        case categoryTypeID = "categoryTypeId"
    }
}

public struct DastakV1CatalogueSubcategory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let categoryID: UUID
    public let name: String
    public let slug: String
    public let imageKey: String?
    public let previewImageKeys: [String]?
    public let status: String?
    public let requiresControlledFlow: Bool?
    public let sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case categoryID = "categoryId"
        case name
        case slug
        case imageKey
        case previewImageKeys
        case status
        case requiresControlledFlow
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
    public let categoryTypeID: UUID?
    public let categoryID: UUID
    public let subcategoryID: UUID
    public let brand: DastakV1CatalogueBrand?
    public let name: String
    public let slug: String
    public let variant: String?
    public let packSize: String
    public let description: String?
    public let imageKey: String?
    public let galleryImageKeys: [String]?
    public let barcode: String?
    public let quantityValue: Decimal?
    public let quantityUnit: String?
    public let packCount: Int?
    public let manufacturerName: String?
    public let countryOfOriginCode: String?
    public let dietType: String?
    public let shelfLifeDays: Int?
    public let listPricePaise: Int
    public let sellingPricePaise: Int
    public let currencyCode: String
    public let logisticsAttributes: DastakV1SKULogistics

    public var price: Money { Money(paise: sellingPricePaise) }
    public var listPrice: Money { Money(paise: listPricePaise) }

    private enum CodingKeys: String, CodingKey {
        case id
        case categoryTypeID = "categoryTypeId"
        case categoryID = "categoryId"
        case subcategoryID = "subcategoryId"
        case brand
        case name
        case slug
        case variant
        case packSize
        case description
        case imageKey
        case galleryImageKeys
        case barcode
        case quantityValue, quantityUnit, packCount, manufacturerName
        case countryOfOriginCode, dietType, shelfLifeDays
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
    public let categoryTypes: [DastakV1CatalogueCategory]?
    public let categories: [DastakV1CatalogueCategory]
    public let subcategories: [DastakV1CatalogueSubcategory]
    public let skus: [DastakV1CatalogueSKU]
    public let nextCursor: DastakV1CatalogueCursor?
}

public struct DastakV1RestaurantMenuOption: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let priceDeltaPaise: Int
    public let sortOrder: Int
    public let status: String
    public let version: Int
}

public struct DastakV1RestaurantMenuOptionGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let selectionType: String
    public let minimumSelections: Int
    public let maximumSelections: Int
    public let sortOrder: Int
    public let status: String
    public let version: Int
    public let options: [DastakV1RestaurantMenuOption]
}

public struct DastakV1RestaurantMenuItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let imageKey: String?
    public let basePricePaise: Int
    public let currencyCode: String
    public let taxRateBps: Int
    public let logisticsAttributes: DastakV1SKULogistics
    public let status: String
    public let version: Int
    public let optionGroups: [DastakV1RestaurantMenuOptionGroup]

    public var basePrice: Money { Money(paise: basePricePaise) }
}

public struct DastakV1RestaurantMenuCategory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let sortOrder: Int
    public let status: String
    public let version: Int
    public let items: [DastakV1RestaurantMenuItem]
}

public struct DastakV1RestaurantIdentity: Codable, Equatable, Sendable {
    public let organizationID: UUID
    public let branchID: UUID
    public let name: String
    public let branchName: String
    public let imageKey: String?
    public let description: String?
    public let serviceZoneID: UUID?
    public let acceptingOrders: Bool
    public let isOpen: Bool
    public let branchStatus: String
    public let merchantType: String
    public let softActiveOrderThreshold: Int
    public let activeOrderCount: Int

    private enum CodingKeys: String, CodingKey {
        case name, branchName, imageKey, description, acceptingOrders, isOpen
        case branchStatus, merchantType, softActiveOrderThreshold, activeOrderCount
        case organizationID = "organizationId"
        case branchID = "branchId"
        case serviceZoneID = "serviceZoneId"
    }
}

public struct DastakV1RestaurantMenu: Codable, Equatable, Identifiable, Sendable {
    public let restaurant: DastakV1RestaurantIdentity
    public let categories: [DastakV1RestaurantMenuCategory]
    public var id: UUID { restaurant.branchID }
}

public struct DastakV1OrderRestaurant: Codable, Equatable, Sendable {
    public let organizationID: UUID
    public let branchID: UUID
    public let name: String
    public let branchName: String
    public let imageKey: String?

    private enum CodingKeys: String, CodingKey {
        case name, branchName, imageKey
        case organizationID = "organizationId"
        case branchID = "branchId"
    }
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
    public let lineType: String
    public let skuID: UUID?
    public let menuItemID: UUID?
    public let optionIDs: [UUID]?
    public let quantity: Int

    public init(skuID: UUID, quantity: Int) {
        lineType = "RETAIL_SKU"
        self.skuID = skuID
        menuItemID = nil
        optionIDs = nil
        self.quantity = quantity
    }

    public init(menuItemID: UUID, optionIDs: [UUID], quantity: Int) {
        lineType = "FOOD_MENU_ITEM"
        skuID = nil
        self.menuItemID = menuItemID
        self.optionIDs = optionIDs
        self.quantity = quantity
    }

    private enum CodingKeys: String, CodingKey {
        case lineType
        case skuID = "skuId"
        case menuItemID = "menuItemId"
        case optionIDs = "optionIds"
        case quantity
    }
}

public struct DastakV1OrderSubmission: Codable, Equatable, Sendable {
    public let deliveryAddress: DastakV1DeliveryAddressInput
    public let recipient: DastakV1RecipientInput
    public let restaurantBranchID: UUID?
    public let lines: [DastakV1OrderLineInput]

    public init(
        deliveryAddress: DastakV1DeliveryAddressInput,
        recipient: DastakV1RecipientInput,
        restaurantBranchID: UUID? = nil,
        lines: [DastakV1OrderLineInput]
    ) {
        self.deliveryAddress = deliveryAddress
        self.recipient = recipient
        self.restaurantBranchID = restaurantBranchID
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey {
        case deliveryAddress, recipient, lines
        case restaurantBranchID = "restaurantBranchId"
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
    case cancelled = "CANCELLED"
    case fulfilmentFailure = "DASTAK_FULFILMENT_FAILURE"
}

public struct DastakV1FulfilmentProgress: Codable, Equatable, Sendable {
    public let state: String
    public let title: String?
    public let estimatedReadyAt: String?
    public let runningLate: Bool?
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

public enum DastakV1LaunchPaymentState: String, Codable, Equatable, Sendable {
    case readyToConfirm = "READY_TO_CONFIRM"
    case paymentDueAtDelivery = "PAYMENT_DUE_AT_DELIVERY"
    case collectionRetryNeeded = "COLLECTION_RETRY_NEEDED"
    case paymentCollected = "PAYMENT_COLLECTED"
    case reservationExpired = "RESERVATION_EXPIRED"
    case notApplicable = "NOT_APPLICABLE"
}

public enum DastakV1LaunchReservationState: String, Codable, Equatable, Sendable {
    case active = "ACTIVE"
    case committed = "COMMITTED"
    case expired = "EXPIRED"
}

public enum DastakV1LaunchCollectionMethod: String, Codable, Equatable, Sendable {
    case cash = "CASH"
    case upi = "UPI"
}

public struct DastakV1LaunchPayment: Codable, Equatable, Sendable {
    public let optionLabel: String
    public let state: DastakV1LaunchPaymentState
    public let amountPaise: Int?
    public let currencyCode: String?
    public let securedAt: String?
    public let reservationExpiresAt: String?
    public let reservationSecondsRemaining: Int
    public let reservationState: DastakV1LaunchReservationState
    public let committedAt: String?
    public let collectedAt: String?
    public let collectionMethod: DastakV1LaunchCollectionMethod?
    public let canCommit: Bool
    public let noChargeNow: Bool
    public let payAtDoorstep: Bool

    public var amount: Money? { amountPaise.map { Money(paise: $0) } }
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
    public let outForDeliveryAt: String?
    public let deliveredAt: String?
    public let recipientAccountRequired: Bool
    public let riderLocation: DastakV1Coordinate?
    public let riderLocationUpdatedAt: String?
    public let distanceToDestinationMeters: Int?
    public var pinVerified: Bool?
}

public struct DastakV1Coordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
}

public enum DastakV1CustomerIssueCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case wrongSKU = "WRONG_SKU"
    case wrongQuantity = "WRONG_QUANTITY"
    case damaged = "DAMAGED"
    case defective = "DEFECTIVE"
    case expired = "EXPIRED"
    case tamperedOrBrokenSeal = "TAMPERED_OR_BROKEN_SEAL"
    case incorrectPackage = "INCORRECT_PACKAGE"
    case suspectedMerchantMisfulfilment = "SUSPECTED_MERCHANT_MISFULFILMENT"
    case deliveryProblem = "DELIVERY_PROBLEM"
    case other = "OTHER"
}

public struct DastakV1RecoveryProgress: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let type: String
    public let status: String
    public let orderLineID: UUID?
    public let openedAt: String
    public let resolvedAt: String?
    public let customerMessage: String

    private enum CodingKeys: String, CodingKey {
        case id, type, status, openedAt, resolvedAt, customerMessage
        case orderLineID = "orderLineId"
    }
}

public struct DastakV1CustomerIssueEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let objectPath: String
    public let contentType: String
    public let capturedAt: String
}

public struct DastakV1CustomerIssue: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let orderLineID: UUID?
    public let category: DastakV1CustomerIssueCategory
    public let status: String
    public let description: String
    public let reportedAt: String
    public let resolution: String?
    public let resolvedAt: String?
    public let version: Int
    public let evidence: [DastakV1CustomerIssueEvidence]

    private enum CodingKeys: String, CodingKey {
        case id, category, status, description, reportedAt, resolution, resolvedAt, version, evidence
        case orderLineID = "orderLineId"
    }
}

public struct DastakV1ReturnMissionProgress: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let status: String
    public let assignedAt: String?
    public let arrivedCustomerAt: String?
    public let pickupCompletedAt: String?
    public let completedAt: String?
    public let pickupVerificationStatus: String
    public let pickupCode: String?
}

public struct DastakV1ReturnProgress: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let source: String
    public let status: String
    public let physicalReturnRequired: Bool
    public let reason: String
    public let requestedAt: String
    public let completedAt: String?
    public let packageCount: Int
    public let mission: DastakV1ReturnMissionProgress?
}

public struct DastakV1RefundProgress: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let orderLineID: UUID?
    public let status: String
    public let destination: String
    public let amountPaise: Int
    public let currency: String
    public let reason: String
    public let createdAt: String
    public let completedAt: String?

    public var amount: Money { Money(paise: amountPaise) }

    private enum CodingKeys: String, CodingKey {
        case id, status, destination, amountPaise, currency, reason, createdAt, completedAt
        case orderLineID = "orderLineId"
    }
}

public struct DastakV1OrderSupport: Codable, Equatable, Sendable {
    public let canReportIssue: Bool
    public let recovery: [DastakV1RecoveryProgress]
    public let issues: [DastakV1CustomerIssue]
    public let returns: [DastakV1ReturnProgress]
    public let refunds: [DastakV1RefundProgress]
}

public struct DastakV1CustomerIssueCommandResult: Codable, Equatable, Sendable {
    public let issueID: UUID
    public let orderID: UUID
    public let orderLineID: UUID?
    public let category: DastakV1CustomerIssueCategory
    public let status: String
    public let reportedAt: String
    public let evidenceID: UUID?

    private enum CodingKeys: String, CodingKey {
        case status, category, reportedAt
        case issueID = "issueId"
        case orderID = "orderId"
        case orderLineID = "orderLineId"
        case evidenceID = "evidenceId"
    }
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
    public let menuItemID: UUID?
    public let name: String
    public let variant: String?
    public let packSize: String?
    public let quantity: Int
    public let unitPricePaise: Int
    public let lineTotalPaise: Int
    public let status: String
    public let foodSelection: DastakV1FoodSelection?

    private enum CodingKeys: String, CodingKey {
        case id
        case lineType
        case skuID = "skuId"
        case menuItemID = "menuItemId"
        case name
        case variant
        case packSize
        case quantity
        case unitPricePaise
        case lineTotalPaise
        case status
        case foodSelection
    }
}

public struct DastakV1FoodSelection: Codable, Equatable, Sendable {
    public let options: [DastakV1FoodOption]
}

public struct DastakV1FoodOption: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let groupID: UUID
    public let groupName: String
    public let name: String
    public let priceDeltaPaise: Int

    private enum CodingKeys: String, CodingKey {
        case id, groupName, name, priceDeltaPaise
        case groupID = "groupId"
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
    public let launchPayment: DastakV1LaunchPayment?
    public let delivery: DastakV1DeliveryProgress?
    public var tracking: DastakDeliveryTracking?
    public let support: DastakV1OrderSupport?
    public let deliveryAddress: DastakV1DeliveryAddressInput?
    public let recipient: DastakV1RecipientInput?
    public let price: DastakV1OrderPrice
    public let lines: [DastakV1OrderLine]
    public let restaurant: DastakV1OrderRestaurant?
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

    func restaurants(
        query: String?,
        limit: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> [DastakV1RestaurantMenu]

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

    func commitLaunchPayment(
        id: UUID,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderSnapshot

    func reportIssue(
        orderID: UUID,
        orderLineID: UUID?,
        category: DastakV1CustomerIssueCategory,
        description: String,
        objectPath: String?,
        contentType: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1CustomerIssueCommandResult
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

    private struct RestaurantRequest: Encodable, Sendable {
        let operation = "customerRestaurants"
        let query: String?
        let limit: Int
    }

    private struct RestaurantResponse: Decodable, Sendable {
        let restaurants: [DastakV1RestaurantMenu]
    }

    private struct OrderRequest: Encodable, Sendable {
        let supportsConfirmedCancellation = true
        let operation: String
        let expectedVersion: Int?
        let order: DastakV1OrderSubmission?
        let orderId: UUID?
        let limit: Int?
        let cursor: DastakV1OrderCursor?
    }

    private struct IssueRequest: Encodable, Sendable {
        let operation = "reportCustomerIssue"
        let orderId: UUID
        let orderLineId: UUID?
        let category: DastakV1CustomerIssueCategory
        let description: String
        let objectPath: String?
        let contentType: String?
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

    public func restaurants(
        query: String? = nil,
        limit: Int = 50,
        idempotencyKey: IdempotencyKey
    ) async throws -> [DastakV1RestaurantMenu] {
        precondition((1...100).contains(limit))
        let response: RestaurantResponse = try await functions.invoke(
            "dastak-v1-catalogue",
            request: RestaurantRequest(query: query, limit: limit),
            idempotencyKey: idempotencyKey
        )
        return response.restaurants
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

    public func commitLaunchPayment(
        id: UUID,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1OrderSnapshot {
        precondition(expectedVersion > 0)
        return try await invokeOrder(
            OrderRequest(
                operation: "commitLaunchPayment",
                expectedVersion: expectedVersion,
                order: nil,
                orderId: id,
                limit: nil,
                cursor: nil
            ),
            key: idempotencyKey
        )
    }

    public func reportIssue(
        orderID: UUID,
        orderLineID: UUID?,
        category: DastakV1CustomerIssueCategory,
        description: String,
        objectPath: String? = nil,
        contentType: String? = nil,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1CustomerIssueCommandResult {
        let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition((3...1_000).contains(normalized.count))
        precondition((objectPath == nil) == (contentType == nil))
        return try await functions.invoke(
            "dastak-v1-orders",
            request: IssueRequest(
                orderId: orderID,
                orderLineId: orderLineID,
                category: category,
                description: normalized,
                objectPath: objectPath,
                contentType: contentType
            ),
            idempotencyKey: idempotencyKey
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
