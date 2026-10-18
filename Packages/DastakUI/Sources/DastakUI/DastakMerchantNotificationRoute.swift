import Foundation
import MarketplaceInfrastructure

public struct DastakMerchantNotificationRoute: Codable, Equatable, Sendable {
    public let notificationType: String
    public let orderID: UUID
    public let receivedAt: Date
    static let types: Set<String> = [
        "merchant.opportunity", "merchant.restaurant_request", "merchant.recovery_opportunity",
        "merchant.preparation_started", "merchant.rider_assigned", "merchant.rider_arrived",
        "merchant.return_incoming", "merchant.order_cancelled"
    ]
    public static func parse(_ payload: [AnyHashable: Any], now: Date = .now) -> Self? {
        guard let type = payload["notificationType"] as? String, types.contains(type),
              payload["entityType"] as? String == "dastakV1Order",
              let raw = payload["orderId"] as? String ?? payload["entityId"] as? String,
              let id = UUID(uuidString: raw) else { return nil }
        if let entity = payload["entityId"] {
            guard let value = entity as? String, UUID(uuidString: value) == id else { return nil }
        }
        if let order = payload["orderId"] {
            guard let value = order as? String, UUID(uuidString: value) == id else { return nil }
        }
        return .init(notificationType: type, orderID: id, receivedAt: now)
    }
    var queue: DastakMerchantQueue {
        switch notificationType {
        case "merchant.opportunity", "merchant.restaurant_request", "merchant.recovery_opportunity": .incoming
        case "merchant.return_incoming": .returns
        case "merchant.order_cancelled": .history
        default: .all
        }
    }
    var valid: Bool { Self.types.contains(notificationType) }
}

/// One short-lived navigation hint, not an authority, receipt or action journal.
/// Stores no token, customer address, PIN, title/body or other payload fields.
@MainActor
public final class DastakMerchantNotificationInbox {
    public static let opened = Notification.Name("dastak.merchant.openOrders")
    private let defaults: UserDefaults
    private let key = "dastak.merchant.pendingNotification.v1"
    private let seenKey = "dastak.merchant.lastNotification.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    @discardableResult
    public func receive(payload: [AnyHashable: Any], identifier: String, now: Date = .now) -> Bool {
        guard let route = DastakMerchantNotificationRoute.parse(payload, now: now) else { return false }
        // Repeated callbacks for one system alert do not open multiple sheets.
        let fingerprint = String(identifier.prefix(200)) + ":" + route.notificationType + ":" + route.orderID.uuidString
        if let seen = defaults.dictionary(forKey: seenKey),
           seen["id"] as? String == fingerprint, let date = seen["at"] as? Date,
           (0..<86_400).contains(now.timeIntervalSince(date)) { return false }
        guard let bytes = try? JSONEncoder().encode(route) else { return false }
        defaults.set(bytes, forKey: key)
        defaults.set(["id": fingerprint, "at": now], forKey: seenKey)
        NotificationCenter.default.post(name: Self.opened, object: nil)
        return true
    }
    func take(now: Date = .now) -> DastakMerchantNotificationRoute? {
        defer { defaults.removeObject(forKey: key) }
        guard let bytes = defaults.data(forKey: key),
              let route = try? JSONDecoder().decode(DastakMerchantNotificationRoute.self, from: bytes),
              route.valid, (0..<86_400).contains(now.timeIntervalSince(route.receivedAt)) else { return nil }
        return route
    }
}

struct DastakMerchantNotificationChoice: Identifiable, Equatable {
    var id: String { "\(target.kind.rawValue):\(target.id)" }
    let target: DastakMerchantDetailTarget
    let location: String
    let status: String
}

enum DastakMerchantNotificationResolution {
    static func choices(_ route: DastakMerchantNotificationRoute, feeds: DastakV1MerchantRecoveryFeeds?,
                        requests: [DastakV1RestaurantRequest]) -> [DastakMerchantNotificationChoice] {
        let fulfilments = (feeds?.fulfilments ?? []).filter { $0.orderID == route.orderID }
        let recovery = (feeds?.recoveryOpportunities ?? []).filter { $0.orderId == route.orderID }
        let returns = (feeds?.returnReceipts ?? []).filter { $0.orderId == route.orderID }
        let food = requests.filter { $0.orderId == route.orderID }
        var values: [DastakMerchantNotificationChoice] = []
        switch route.notificationType {
        case "merchant.restaurant_request":
            values = food.map { .init(target: .init(kind: .restaurantRequest, id: $0.id, branchID: $0.branch.id), location: $0.branch.displayName, status: $0.status) }
        case "merchant.recovery_opportunity":
            values = recovery.map { .init(target: .init(kind: .recovery, id: $0.id, branchID: $0.branch.id), location: $0.branch.displayName, status: $0.status) }
        case "merchant.return_incoming":
            values = returns.map { .init(target: .init(kind: .returned, id: $0.id, branchID: $0.branch.id), location: $0.branch.displayName, status: $0.status) }
        case "merchant.opportunity":
            // Existing retail offer projection has no order ID. Never guess an
            // opportunity from a display number or another offer in the queue.
            break
        default: break
        }
        if values.isEmpty {
            values = fulfilments.map { .init(target: .init(kind: .fulfilment, id: $0.id, branchID: $0.branch.id), location: $0.branch.displayName, status: $0.status) }
        }
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }.sorted { $0.location == $1.location ? $0.id < $1.id : $0.location < $1.location }
    }
}
