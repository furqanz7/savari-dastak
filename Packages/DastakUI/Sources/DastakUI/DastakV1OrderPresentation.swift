import Foundation
import MarketplaceInfrastructure

enum DastakV1OrderPresentation {
    static let journeySteps = [
        "Finding items",
        "Ready for payment",
        "Preparing",
        "Picking up",
        "On the way",
        "Delivered",
    ]

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
            "We’re checking availability for every exact item in your basket. You’ll pay only after everything is secured."
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

    static func journeyStep(_ status: DastakV1OrderStatus) -> Int? {
        switch status {
        case .created, .matching: 0
        case .fullySecured, .awaitingPayment: 1
        case .paid, .preparing: 2
        case .pickupInProgress: 3
        case .outForDelivery: 4
        case .delivered: 5
        case .unavailable, .paymentExpired, .cancelledPrepayment, .fulfilmentFailure: nil
        }
    }

    static func journeyLabel(_ status: DastakV1OrderStatus) -> String? {
        guard let step = journeyStep(status) else { return nil }
        return journeySteps[step]
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
        var seen = Set<String>()
        return [address.line2, address.line1, address.landmark, address.city,
                address.state, address.postalCode]
            .compactMap(normalizedAddressComponent)
            .flatMap {
                $0.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            .filter { seen.insert($0.lowercased()).inserted }
            .joined(separator: ", ")
    }

    static func phoneNumber(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        let local: String
        if digits.count == 12, digits.hasPrefix("91") {
            local = String(digits.dropFirst(2))
        } else if digits.count == 10 {
            local = digits
        } else {
            return value
        }
        return "+91 \(local.prefix(5)) \(local.suffix(5))"
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

    static func itemCount(_ order: DastakV1OrderSnapshot) -> Int {
        order.lines.reduce(0) { $0 + $1.quantity }
    }

    static func canReorder(_ status: DastakV1OrderStatus) -> Bool {
        [.delivered, .unavailable, .paymentExpired, .cancelledPrepayment].contains(status)
    }

    static func deliveredDuration(_ order: DastakV1OrderSnapshot) -> String? {
        guard let started = date(order.submittedAt ?? order.createdAt),
              let finished = date(order.deliveredAt ?? order.delivery?.deliveredAt)
        else { return nil }
        let minutes = max(1, Int((finished.timeIntervalSince(started) / 60.0).rounded()))
        if minutes < 60 { return "Delivered in \(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0
            ? "Delivered in \(hours) hr"
            : "Delivered in \(hours) hr \(remainder) min"
    }

    static func searchText(_ order: DastakV1OrderSnapshot) -> String {
        [
            order.displayOrderNumber,
            order.restaurant?.name,
            order.restaurant?.branchName,
            order.recipient?.name,
            order.deliveryAddress.map(addressLine),
            order.lines.map(\.name).joined(separator: " "),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    private static func normalizedAddressComponent(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsedCommas = value.replacingOccurrences(
            of: #"(?:\s*,\s*)+"#,
            with: ", ",
            options: .regularExpression
        )
        let trimmed = collapsedCommas.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        )
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
