import Foundation
import MarketplaceInfrastructure

enum DastakV1OrderPresentation {
    static func isActive(_ status: DastakV1OrderStatus) -> Bool {
        DastakCustomerModel.isActiveV1Order(status)
    }

    static func title(_ status: DastakV1OrderStatus) -> String {
        switch status {
        case .created, .matching: "Finding every item"
        case .fullySecured, .awaitingPayment: "Your basket is secured"
        case .paid, .preparing: "Preparing your order"
        case .pickupInProgress: "Picking up your order"
        case .outForDelivery: "On the way"
        case .delivered: "Delivered"
        case .unavailable: "Basket unavailable"
        case .paymentExpired: "Payment window expired"
        case .cancelledPrepayment: "Order cancelled"
        case .fulfilmentFailure: "Order needs attention"
        }
    }

    static func message(_ status: DastakV1OrderStatus) -> String {
        switch status {
        case .created, .matching:
            "Dastak is matching every exact item. Retail merchant identities stay private."
        case .fullySecured, .awaitingPayment:
            "Every item is reserved. Payment is requested before preparation begins."
        case .paid, .preparing:
            "Payment is confirmed and your complete order is being prepared."
        case .pickupInProgress:
            "Your delivery partner is collecting your complete order."
        case .outForDelivery:
            "Every required package is with your delivery partner and heading to you."
        case .delivered:
            "Every package was securely handed over. Your order is complete."
        case .unavailable:
            "Dastak could not secure the complete basket. You were not charged."
        case .paymentExpired:
            "The reservation ended before payment completed. Reserved items were released."
        case .cancelledPrepayment:
            "This order was cancelled before payment."
        case .fulfilmentFailure:
            "Dastak is protecting your payment and coordinating recovery. Follow the updates below."
        }
    }

    static func assurance(_ status: DastakV1OrderStatus) -> String {
        switch status {
        case .created, .matching, .fullySecured, .awaitingPayment:
            "No charge until the complete basket is secured"
        case .paid, .preparing, .pickupInProgress, .outForDelivery, .delivered:
            "Secure package custody is tracked by Dastak"
        case .unavailable, .paymentExpired, .cancelledPrepayment:
            "No completed payment is attached to this order"
        case .fulfilmentFailure:
            "Payment protection and recovery remain with Dastak"
        }
    }

    static func symbol(_ status: DastakV1OrderStatus) -> String {
        switch status {
        case .fullySecured, .awaitingPayment: "checkmark.shield.fill"
        case .paid, .preparing: "shippingbox.fill"
        case .pickupInProgress, .outForDelivery: "scooter"
        case .delivered: "checkmark.circle.fill"
        case .cancelledPrepayment: "xmark.circle.fill"
        case .paymentExpired: "clock.badge.exclamationmark"
        case .unavailable: "cart.badge.minus"
        case .fulfilmentFailure: "exclamationmark.shield.fill"
        case .created, .matching: "magnifyingglass"
        }
    }

    static func orderType(_ value: String) -> String {
        switch value {
        case "FOOD_ONLY": "Restaurant order"
        case "MIXED": "Food + retail order"
        default: "Retail order"
        }
    }

    static func displayState(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func addressLine(_ address: DastakV1DeliveryAddressInput) -> String {
        [address.line1, address.line2, address.landmark, address.city, address.state,
         address.postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func optionSummary(_ line: DastakV1OrderLine) -> String? {
        let names = line.foodSelection?.options.map(\.name) ?? []
        if !names.isEmpty { return names.joined(separator: " · ") }
        return [line.variant, line.packSize]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
