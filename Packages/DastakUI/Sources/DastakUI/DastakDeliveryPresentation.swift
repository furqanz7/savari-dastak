import Foundation
import MarketplaceInfrastructure

/// Presentation only; server capability flags remain authoritative for actions.
enum DastakDeliveryPresentation {
    /// Liveness heartbeats increment `version` without changing the handoff.
    /// Do not erase a PIN or payment reference while the rider is typing it.
    static func handoffRevision(_ mission: DastakV1DeliveryMissionSnapshot) -> String {
        ([mission.id.uuidString, mission.status.rawValue,
          "pin:\(mission.finalVerification?.pinVerified == true)",
          "photo:\(mission.finalVerification?.evidencePresent == true)",
          "collection:\(mission.launchCollection?.state.rawValue ?? "none")"] +
         mission.pickupStops.map { "\($0.id):\($0.status?.rawValue ?? "unknown")" }).joined(separator: "|")
    }
    static func callURL(_ number: String) -> URL? {
        let value = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("+"), (8...15).contains(value.dropFirst().count),
              value.dropFirst().first.map({ ("1"..."9").contains(String($0)) }) == true,
              value.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return URL(string: "tel:\(value)")
    }
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
        case .arrived: "Verify the customer PIN, take the package photo, collect payment if due, then complete delivery."
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

/// Labels only: history never estimates earnings or substitutes for the ledger.
enum DastakDeliveryHistoryPresentation {
    enum Tone { case success, cancelled, neutral }

    static func kind(_ value: String) -> String {
        switch value {
        case "V1_DELIVERY", "LEGACY_DELIVERY": "Delivery"
        case "RETURN": "Return"
        case "PARCEL": "Parcel"
        default: DastakMerchantReceiptPresentation.label(value)
        }
    }

    static func symbol(_ value: String) -> String {
        switch value {
        case "RETURN": "arrow.uturn.backward"
        case "PARCEL": "shippingbox"
        default: "bag"
        }
    }

    static func outcome(_ value: String) -> String {
        switch value {
        case "COMPLETED", "DELIVERED": "Completed"
        case "CANCELLED", "CANCELED": "Cancelled"
        case "RETURNED": "Returned"
        default: DastakMerchantReceiptPresentation.label(value)
        }
    }

    static func tone(_ value: String) -> Tone {
        switch value {
        case "COMPLETED", "DELIVERED", "RETURNED": .success
        case "CANCELLED", "CANCELED": .cancelled
        default: .neutral
        }
    }

    static func packages(_ count: Int?) -> String? {
        guard let count, count >= 0 else { return nil }
        return "\(count) \(count == 1 ? "package" : "packages")"
    }

    static func payout(_ paise: Int?) -> String? {
        guard let paise, paise >= 0 else { return nil }
        return "Recorded payout · \(DastakFormatting.money(.init(paise: paise)))"
    }
}
