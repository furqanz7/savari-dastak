import Foundation
import MarketplaceInfrastructure

/// Presentation only; server capability flags remain authoritative for actions.
enum DastakDeliveryPresentation {
    static func title(_ status: DastakV1MissionStatus) -> String {
        switch status {
        case .assigned: "Ready for pickup"
        case .enRouteToPickups: "Head to the pickup"
        case .pickupInProgress: "Collect your packages"
        case .allPackagesPickedUp: "Ready to deliver"
        case .outForDelivery: "On the way to the customer"
        case .arrived: "Complete the handoff"
        case .deliveryRecovery: "Delivery needs support"
        }
    }

    static func instruction(_ status: DastakV1MissionStatus) -> String {
        switch status {
        case .assigned: "Review your stops, then start your pickups."
        case .enRouteToPickups: "Mark arrival when you reach the merchant."
        case .pickupInProgress: "Count every package and ask the merchant for the pickup code."
        case .allPackagesPickedUp: "All pickups are verified. Start the route to your customer."
        case .outForDelivery: "Keep every package secure. Mark arrival at the destination."
        case .arrived: "Complete payment if due, add a package photo, then verify the customer code."
        case .deliveryRecovery: "Keep the packages with you. Contact Operations for the next steps."
        }
    }

    static func step(_ status: DastakV1MissionStatus) -> Int? {
        switch status {
        case .assigned, .enRouteToPickups, .pickupInProgress: 0
        case .allPackagesPickedUp, .outForDelivery: 1
        case .arrived: 2
        case .deliveryRecovery: nil
        }
    }

    static func secondsRemaining(until value: String, now: Date) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return 0 }
        return max(0, Int(ceil(date.timeIntervalSince(now))))
    }

    static func code(_ value: String, length: Int) -> String {
        String(value.filter { $0.isASCII && $0.isNumber }.prefix(length))
    }
}
