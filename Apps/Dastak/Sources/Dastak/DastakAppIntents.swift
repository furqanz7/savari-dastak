import AppIntents
import MarketplaceFoundation

enum DastakShortcutDestination: String, AppEnum {
    case grocery, food, basket, tracking, search
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Dastak screen"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .grocery: "Grocery", .food: "Food", .basket: "Basket", .tracking: "Order tracking", .search: "Search"
    ]

    @MainActor
    func open() { DastakAppActionInbox().request(DastakAppAction(rawValue: rawValue)!) }
}

// OpenIntent brings the app to the foreground, including when invoked by a control.
// Compiled into BOTH targets so the system resolves the action to the app process.
struct OpenDastakScreenIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Dastak Screen"
    @Parameter(title: "Screen") var target: DastakShortcutDestination
    init() { target = .grocery }
    init(target: DastakShortcutDestination) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult { target.open(); return .result() }
}

// Named, parameter-free Shortcuts do not ask the user to select a screen each time.
// openAppWhenRun also supports the app's iOS 17 deployment target.
#if !DASTAK_CONTROL_EXTENSION
struct OpenDastakGroceryIntent: AppIntent {
    static let title: LocalizedStringResource = "Grocery"
    static let description = IntentDescription("Browse groceries in Dastak. Sign in if needed.")
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult { DastakShortcutDestination.grocery.open(); return .result() }
}

struct OpenDastakFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Food"
    static let description = IntentDescription("Browse restaurants and cafés in Dastak. Sign in if needed.")
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult { DastakShortcutDestination.food.open(); return .result() }
}

struct OpenDastakBasketIntent: AppIntent {
    static let title: LocalizedStringResource = "Basket"
    static let description = IntentDescription("Review your current Dastak basket. An empty basket stays on Home.")
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult { DastakShortcutDestination.basket.open(); return .result() }
}

struct TrackDastakOrderIntent: AppIntent {
    static let title: LocalizedStringResource = "Track Order"
    static let description = IntentDescription("View your active Dastak order, or open Orders if none is active.")
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult { DastakShortcutDestination.tracking.open(); return .result() }
}

struct SearchDastakIntent: AppIntent {
    static let title: LocalizedStringResource = "Search"
    static let description = IntentDescription(
        "Open product and food search in Dastak. Sign in if needed.",
        searchKeywords: ["Search", "Find products", "Groceries", "Food"])
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult { DastakShortcutDestination.search.open(); return .result() }
}

struct DastakAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .yellow }
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SearchDastakIntent(), phrases: ["Open search in \(.applicationName)", "Search products in \(.applicationName)", "Find items with \(.applicationName)", "Search \(.applicationName)"], shortTitle: "Search", systemImageName: "magnifyingglass")
        AppShortcut(intent: OpenDastakGroceryIntent(), phrases: ["Open groceries in \(.applicationName)", "Shop groceries with \(.applicationName)"], shortTitle: "Grocery", systemImageName: "basket")
        AppShortcut(intent: OpenDastakFoodIntent(), phrases: ["Open food in \(.applicationName)", "Browse restaurants in \(.applicationName)"], shortTitle: "Food", systemImageName: "fork.knife")
        AppShortcut(intent: OpenDastakBasketIntent(), phrases: ["Open my basket in \(.applicationName)"], shortTitle: "Basket", systemImageName: "basket.fill")
        AppShortcut(intent: TrackDastakOrderIntent(), phrases: ["Track my order in \(.applicationName)", "Where is my \(.applicationName) order"], shortTitle: "Track Order", systemImageName: "scooter")
    }
}
#endif
