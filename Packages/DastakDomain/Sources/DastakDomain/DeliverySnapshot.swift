import Foundation
import MarketplaceFoundation

public struct DeliveryPriceSnapshot: Codable, Equatable, Sendable {
    public let itemSubtotal: Money?
    public let deliveryFee: Money
    public let total: Money

    public init(
        itemSubtotal: Money?,
        deliveryFee: Money,
        total: Money
    ) {
        self.itemSubtotal = itemSubtotal
        self.deliveryFee = deliveryFee
        self.total = total
    }
}

public struct DeliveryCounterpartDisplay: Codable, Equatable, Sendable {
    public let displayName: String
    public let phoneNumber: String?

    public init(displayName: String, phoneNumber: String?) {
        self.displayName = displayName
        self.phoneNumber = phoneNumber
    }
}

public struct DeliverySnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: DeliveryKind
    public let status: DeliveryStatus
    public let paymentState: DeliveryPaymentState
    public let selectedMethod: DeliveryMethod?
    public let price: DeliveryPriceSnapshot
    public let pickup: GeoPoint
    public let dropoff: GeoPoint
    public let counterpart: DeliveryCounterpartDisplay?
    public let assignmentDeadline: Date?
    public let stateVersion: Int64

    public init(
        id: UUID,
        kind: DeliveryKind,
        status: DeliveryStatus,
        paymentState: DeliveryPaymentState,
        selectedMethod: DeliveryMethod?,
        price: DeliveryPriceSnapshot,
        pickup: GeoPoint,
        dropoff: GeoPoint,
        counterpart: DeliveryCounterpartDisplay?,
        assignmentDeadline: Date?,
        stateVersion: Int64
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.paymentState = paymentState
        self.selectedMethod = selectedMethod
        self.price = price
        self.pickup = pickup
        self.dropoff = dropoff
        self.counterpart = counterpart
        self.assignmentDeadline = assignmentDeadline
        self.stateVersion = stateVersion
    }
}
