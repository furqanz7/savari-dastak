import Foundation

/// Navigation only: these actions never pick up a basket, add items or submit orders.
public enum DastakAppAction: String, CaseIterable, Sendable {
    case grocery, food, basket, tracking, search

    public var controlTitle: String {
        switch self {
        case .search: "Search"
        case .grocery: "Grocery"
        case .food: "Food"
        case .basket: "Basket"
        case .tracking: "Track Order"
        }
    }

    public var controlSymbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .grocery: "storefront"
        case .food: "fork.knife"
        case .basket: "basket"
        case .tracking: "location.north.circle"
        }
    }

    public var controlActionHint: String {
        switch self {
        case .search: "Search Dastak"
        case .grocery: "Browse groceries"
        case .food: "Browse restaurants"
        case .basket: "Review your basket"
        case .tracking: "Track your order"
        }
    }

    public init?(url: URL) {
        guard url.scheme == "com.dastak.app", url.host == "open",
              url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        self.init(rawValue: url.lastPathComponent)
    }

    public init?(shortcutType: String) {
        let prefix = "com.dastak.app.quick."
        guard shortcutType.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(shortcutType.dropFirst(prefix.count)))
    }
}

/// A one-shot mailbox survives cold launch and sign-in without storing account data.
/// OpenIntent runs in the foreground app; the extension does not need an App Group.
@MainActor
public struct DastakAppActionInbox {
    public static let opened = Notification.Name("dastak.appAction.opened")
    private static let key = "dastak.appAction.pending.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func request(_ action: DastakAppAction, now: Date = Date()) {
        defaults.set(["action": action.rawValue, "time": now.timeIntervalSince1970], forKey: Self.key)
        NotificationCenter.default.post(name: Self.opened, object: nil)
    }

    public func peek(now: Date = Date()) -> DastakAppAction? {
        guard let value = defaults.dictionary(forKey: Self.key),
              let raw = value["action"] as? String, let action = DastakAppAction(rawValue: raw),
              let time = value["time"] as? Double,
              (0...900).contains(now.timeIntervalSince1970 - time) else {
            defaults.removeObject(forKey: Self.key)
            return nil
        }
        return action
    }

    public func consume(now: Date = Date()) -> DastakAppAction? {
        let action = peek(now: now)
        defaults.removeObject(forKey: Self.key)
        return action
    }
}
