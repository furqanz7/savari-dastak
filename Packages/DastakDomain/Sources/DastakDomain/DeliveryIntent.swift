import Foundation
import MarketplaceFoundation

public struct QuoteParcelRequest: Codable, Equatable, Sendable {
    public let deliveryMethod: DeliveryMethod
    public let pickup: GeoPoint
    public let dropoff: GeoPoint

    public init(
        deliveryMethod: DeliveryMethod,
        pickup: GeoPoint,
        dropoff: GeoPoint
    ) {
        self.deliveryMethod = deliveryMethod
        self.pickup = pickup
        self.dropoff = dropoff
    }
}

public struct CreateParcelRequest: Codable, Equatable, Sendable {
    public let quoteID: UUID
    public let recipient: ParcelRecipient
    public let declaredContents: String
    public let declaredValue: Money

    public init(
        quoteID: UUID,
        recipient: ParcelRecipient,
        declaredContents: String,
        declaredValue: Money
    ) {
        self.quoteID = quoteID
        self.recipient = recipient
        self.declaredContents = declaredContents
        self.declaredValue = declaredValue
    }

    private enum CodingKeys: String, CodingKey {
        case quoteID = "quoteId"
        case recipient
        case declaredContents
        case declaredValue
    }
}

public struct QuoteMerchantOrderRequest: Codable, Equatable, Sendable {
    public let storeID: UUID
    public let lines: [MerchantOrderLine]
    public let dropoff: GeoPoint

    public init(
        storeID: UUID,
        lines: [MerchantOrderLine],
        dropoff: GeoPoint
    ) {
        self.storeID = storeID
        self.lines = lines
        self.dropoff = dropoff
    }

    private enum CodingKeys: String, CodingKey {
        case storeID = "storeId"
        case lines
        case dropoff
    }
}

public struct CreateMerchantOrderRequest: Codable, Equatable, Sendable {
    public let quoteID: UUID

    public init(quoteID: UUID) {
        self.quoteID = quoteID
    }

    private enum CodingKeys: String, CodingKey {
        case quoteID = "quoteId"
    }
}

public struct MarkMerchantOrderReadyRequest: Codable, Equatable, Sendable {
    public let orderID: UUID

    public init(orderID: UUID) {
        self.orderID = orderID
    }

    private enum CodingKeys: String, CodingKey {
        case orderID = "orderId"
    }
}

public struct VerifyDeliveryCodeRequest: Codable, Equatable, Sendable {
    public let assignmentID: UUID
    public let code: String

    public init(assignmentID: UUID, code: String) {
        self.assignmentID = assignmentID
        self.code = code
    }

    private enum CodingKeys: String, CodingKey {
        case assignmentID = "assignmentId"
        case code
    }
}
