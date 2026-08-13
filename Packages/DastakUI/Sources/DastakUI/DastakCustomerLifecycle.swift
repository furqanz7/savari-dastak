import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

enum DastakCustomerPrimaryAction: Equatable {
    case pay
    case cancel
    case requestCancellation
    case none
}

struct DastakCustomerLifecyclePresentation: Equatable {
    let title: String
    let message: String
    let primaryAction: DastakCustomerPrimaryAction
}

enum DastakCustomerLifecycle {
    static func merchantOrder(
        status: MerchantOrderStatus,
        paymentState: MerchantOrderPaymentState
    ) -> DastakCustomerLifecyclePresentation {
        let action: DastakCustomerPrimaryAction = if paymentState == .paymentPending {
            .pay
        } else {
            switch status {
            case .paid: .cancel
            case .merchantAccepted, .ready, .assigned, .enRouteToPickup, .atStore, .pickedUp, .inTransit:
                .requestCancellation
            case .paymentPending, .delivered, .cancelled, .returningToMerchant:
                .none
            }
        }

        return DastakCustomerLifecyclePresentation(
            title: merchantOrderTitle(status),
            message: merchantOrderMessage(status),
            primaryAction: action
        )
    }

    static func parcel(
        status: ParcelDeliveryStatus,
        paymentStatus: ParcelPaymentStatus,
        audience: ParcelDeliveryAudience
    ) -> DastakCustomerLifecyclePresentation {
        let action: DastakCustomerPrimaryAction = if audience == .recipient {
            .none
        } else if paymentStatus == .pending || paymentStatus == .failed {
            .pay
        } else {
            switch status {
            case .paid, .assigned, .enRouteToPickup: .cancel
            case .paymentPending, .pickedUp, .inTransit, .delivered, .cancelled: .none
            }
        }

        return DastakCustomerLifecyclePresentation(
            title: parcelTitle(status),
            message: parcelMessage(status),
            primaryAction: action
        )
    }

    static func paymentTitle(_ state: MerchantOrderPaymentState) -> String {
        switch state {
        case .paymentPending: "Payment pending"
        case .paid: "Paid"
        case .notCollected: "Not charged"
        case .refundPending: "Refund processing"
        case .refunded: "Refunded"
        }
    }

    static func paymentTitle(_ state: ParcelPaymentStatus) -> String {
        switch state {
        case .pending: "Payment pending"
        case .paid: "Paid"
        case .failed: "Payment failed"
        case .refundPending: "Refund processing"
        case .refunded: "Refunded"
        case .cancelled: "Not charged"
        }
    }

    private static func merchantOrderTitle(_ status: MerchantOrderStatus) -> String {
        switch status {
        case .paymentPending: "Payment pending"
        case .paid: "Sent to store"
        case .merchantAccepted: "Being prepared"
        case .ready: "Ready for pickup"
        case .assigned: "Partner assigned"
        case .enRouteToPickup: "Heading to store"
        case .atStore: "At the store"
        case .pickedUp: "Picked up"
        case .inTransit: "Arriving soon"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        case .returningToMerchant: "Returning to store"
        }
    }

    private static func merchantOrderMessage(_ status: MerchantOrderStatus) -> String {
        switch status {
        case .paymentPending: "Complete payment to send the order to the store."
        case .paid: "The store is reviewing your order."
        case .merchantAccepted: "The store is preparing your items."
        case .ready: "Your order is packed and ready."
        case .assigned: "A delivery partner is assigned."
        case .enRouteToPickup: "Your partner is heading to the store."
        case .atStore: "Your partner has reached the store."
        case .pickedUp: "Your partner has collected the order."
        case .inTransit: "Your order is on the way."
        case .delivered: "Your order was delivered."
        case .cancelled: "This order was cancelled."
        case .returningToMerchant: "The order is being returned to the store."
        }
    }

    private static func parcelTitle(_ status: ParcelDeliveryStatus) -> String {
        switch status {
        case .paymentPending: "Payment pending"
        case .paid: "Finding a partner"
        case .assigned: "Partner assigned"
        case .enRouteToPickup: "Heading to pickup"
        case .pickedUp: "Picked up"
        case .inTransit: "Arriving soon"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        }
    }

    private static func parcelMessage(_ status: ParcelDeliveryStatus) -> String {
        switch status {
        case .paymentPending: "Complete payment to request pickup."
        case .paid: "Dastak is finding a delivery partner."
        case .assigned: "A delivery partner is assigned."
        case .enRouteToPickup: "Your partner is heading to pickup."
        case .pickedUp: "Your parcel has been collected."
        case .inTransit: "Your parcel is on the way."
        case .delivered: "Your parcel was delivered."
        case .cancelled: "This parcel delivery was cancelled."
        }
    }
}

struct DastakOrderPlacementAttempt: Equatable {
    private(set) var quoteID: UUID?
    private(set) var idempotencyKey: IdempotencyKey?

    mutating func key(
        for quoteID: UUID,
        makeKey: () -> IdempotencyKey
    ) -> IdempotencyKey {
        if self.quoteID == quoteID, let idempotencyKey {
            return idempotencyKey
        }
        let key = makeKey()
        self.quoteID = quoteID
        idempotencyKey = key
        return key
    }

    mutating func reset() {
        quoteID = nil
        idempotencyKey = nil
    }
}

enum DastakCustomerDestination: Hashable {
    case merchantOrder(UUID)
    case parcel(UUID)

    init?(notificationPayload: [AnyHashable: Any]) {
        if let entityType = notificationPayload["entityType"] as? String,
           let rawEntityID = notificationPayload["entityId"] as? String,
           let entityID = UUID(uuidString: rawEntityID) {
            switch entityType {
            case "parcel": self = .parcel(entityID)
            case "merchantOrder": self = .merchantOrder(entityID)
            default: return nil
            }
            return
        }

        if let rawParcelID = notificationPayload["parcelId"] as? String,
           let parcelID = UUID(uuidString: rawParcelID) {
            self = .parcel(parcelID)
            return
        }

        guard let rawOrderID = notificationPayload["orderId"] as? String,
              let orderID = UUID(uuidString: rawOrderID) else { return nil }
        self = .merchantOrder(orderID)
    }
}
