public enum DeliveryKind: String, Codable, Equatable, Hashable, Sendable {
    case parcel
    case merchantOrder = "merchant_order"
}

public enum DeliveryStatus: String, Codable, Equatable, Hashable, Sendable {
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

    public func canTransition(to next: Self, for kind: DeliveryKind) -> Bool {
        switch (kind, self, next) {
        case (.parcel, .paymentPending, .paid),
             (.parcel, .paymentPending, .cancelled),
             (.parcel, .paid, .assigned),
             (.parcel, .paid, .cancelled),
             (.parcel, .assigned, .paid),
             (.parcel, .assigned, .enRouteToPickup),
             (.parcel, .assigned, .cancelled),
             (.parcel, .enRouteToPickup, .pickedUp),
             (.parcel, .enRouteToPickup, .cancelled),
             (.parcel, .pickedUp, .inTransit),
             (.parcel, .inTransit, .delivered):
            true

        case (.merchantOrder, .paymentPending, .paid),
             (.merchantOrder, .paymentPending, .cancelled),
             (.merchantOrder, .paid, .merchantAccepted),
             (.merchantOrder, .paid, .cancelled),
             (.merchantOrder, .merchantAccepted, .ready),
             (.merchantOrder, .merchantAccepted, .cancelled),
             (.merchantOrder, .ready, .assigned),
             (.merchantOrder, .ready, .cancelled),
             (.merchantOrder, .assigned, .ready),
             (.merchantOrder, .assigned, .enRouteToPickup),
             (.merchantOrder, .assigned, .cancelled),
             (.merchantOrder, .enRouteToPickup, .atStore),
             (.merchantOrder, .enRouteToPickup, .cancelled),
             (.merchantOrder, .atStore, .pickedUp),
             (.merchantOrder, .atStore, .cancelled),
             (.merchantOrder, .pickedUp, .inTransit),
             (.merchantOrder, .pickedUp, .returningToMerchant),
             (.merchantOrder, .inTransit, .delivered),
             (.merchantOrder, .inTransit, .returningToMerchant),
             (.merchantOrder, .returningToMerchant, .cancelled):
            true

        default:
            false
        }
    }
}

public enum DeliveryPaymentState: String, Codable, Equatable, Hashable, Sendable {
    case pending
    case paymentPending = "payment_pending"
    case paid
    case notCollected = "not_collected"
    case failed
    case refundPending = "refund_pending"
    case refunded
    case cancelled
}
