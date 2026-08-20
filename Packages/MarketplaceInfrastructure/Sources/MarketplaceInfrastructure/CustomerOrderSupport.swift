import Foundation

public enum CustomerOrderCancellationMode: String, Codable, Equatable, Sendable {
    case cancel
    case requestReview = "request_review"
    case pendingReview = "pending_review"
    case none
}

public struct CustomerOrderActions: Codable, Equatable, Sendable {
    public let canPay: Bool
    public let cancellationMode: CustomerOrderCancellationMode
    public let canTrack: Bool
    public let canContactStore: Bool
    public let canContactCourier: Bool
    public let canRequestSupport: Bool
}

public enum CustomerOrderSupportEntityKind: String, Codable, Equatable, Sendable {
    case merchantOrder = "merchant_order"
    case parcelDelivery = "parcel_delivery"
}

public enum CustomerOrderSupportCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case deliveryStatus = "delivery_status"
    case merchantOrItems = "merchant_or_items"
    case payment
    case refund
    case cancellation
    case safety
    case other
}

public enum CustomerOrderSupportStatus: String, Codable, Equatable, Sendable {
    case open
    case inReview = "in_review"
    case resolved
    case closed
}

public struct CustomerOrderSupportCase: Codable, Equatable, Identifiable, Sendable {
    public let caseID: UUID
    public let reference: String
    public let entityKind: CustomerOrderSupportEntityKind
    public let entityID: UUID
    public let category: CustomerOrderSupportCategory
    public let message: String
    public let status: CustomerOrderSupportStatus
    public let createdAt: String
    public let updatedAt: String

    public var id: UUID { caseID }

    private enum CodingKeys: String, CodingKey {
        case caseID = "caseId"
        case reference
        case entityKind
        case entityID = "entityId"
        case category
        case message
        case status
        case createdAt
        case updatedAt
    }
}

public struct CustomerOrderSupportResponse: Codable, Equatable, Sendable {
    public let supportCase: CustomerOrderSupportCase
}
