import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

enum DastakFormatting {
    static func money(_ money: Money) -> String {
        let amount = NSDecimalNumber(decimal: money.rupees)
        return amount.doubleValue.formatted(
            .currency(code: "INR").locale(Locale(identifier: "en_IN"))
        )
    }

    static func orderStatus(_ status: MerchantOrderStatus) -> String {
        switch status {
        case .paymentPending: "Payment pending"
        case .paid: "Paid"
        case .merchantAccepted: "Accepted"
        case .ready: "Ready for pickup"
        case .assigned: "Partner assigned"
        case .enRouteToPickup: "Heading to store"
        case .atStore: "At store"
        case .pickedUp: "Picked up"
        case .inTransit: "On the way"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        case .returningToMerchant: "Returning to store"
        }
    }

    static func parcelStatus(_ status: ParcelDeliveryStatus) -> String {
        switch status {
        case .paymentPending: "Payment pending"
        case .paid: "Paid"
        case .assigned: "Partner assigned"
        case .enRouteToPickup: "Heading to pickup"
        case .pickedUp: "Picked up"
        case .inTransit: "On the way"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        }
    }
}
