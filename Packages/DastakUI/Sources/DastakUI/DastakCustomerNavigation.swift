import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

enum DastakCustomerSection: String, CaseIterable, Hashable, Sendable {
    case home = "Home", orders = "Orders", profile = "Profile", settings = "Settings"
    var symbol: String {
        switch self {
        case .home: "house"
        case .orders: "receipt"
        case .profile: "person"
        case .settings: "gearshape"
        }
    }
}

enum DastakCustomerService: String, CaseIterable, Hashable, Sendable {
    case food = "Food", grocery = "Grocery", parcel = "Parcel", print = "Print"
    var isAvailable: Bool { self == .food || self == .grocery }
    var basketService: DastakBasketService { self == .food ? .food : .grocery }
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .grocery: "bag"
        case .parcel: "shippingbox"
        case .print: "printer"
        }
    }
}

/// UI intent only. Baskets, recovery and order state remain owned by CustomerModel.
struct DastakCustomerNavigation: Equatable {
    enum ActionPresentation: Equatable { case home, basket, tracking, emptyBasket }

    init(service: DastakCustomerService = .grocery) {
        self.service = service.isAvailable ? service : .grocery
    }

    mutating func apply(_ action: DastakAppAction, basketHasItems: Bool) -> ActionPresentation {
        // Explicit system actions dismiss retained product/menu overlays before
        // switching service; ordinary in-app service changes still retain browsing.
        resetCurrentHome()
        switch action {
        case .grocery:
            selectService(.grocery)
            navigate(.home)
            return .home
        case .food:
            selectService(.food)
            navigate(.home)
            return .home
        case .basket:
            navigate(.home)
            return basketHasItems ? .basket : .emptyBasket
        case .tracking:
            navigate(.orders)
            return .tracking
        case .search:
            navigate(.home)
            startsWithSearch = true
            return .home
        }
    }
    static func directorySections(_ map: DastakV1CatalogueBrowseMap) -> [DastakV1CatalogueBrowseMap.Node] {
        map.children(of: nil) // Validated SECTION roots, in canonical sort order.
    }
    private(set) var section: DastakCustomerSection = .home
    private(set) var service: DastakCustomerService = .grocery
    private(set) var groceryHomeRevision = 0
    private(set) var foodHomeRevision = 0
    private(set) var directoryKey: String?
    private(set) var directoryRevision = 0
    private(set) var startsWithSearch = false

    mutating func navigate(_ section: DastakCustomerSection) {
        startsWithSearch = false
        self.section = section
        if section == .home { resetCurrentHome() }
    }

    @discardableResult
    mutating func selectService(_ service: DastakCustomerService) -> Bool {
        guard service.isAvailable else { return false }
        startsWithSearch = false
        if self.service == service { resetCurrentHome() }
        self.service = service
        section = .home
        return true
    }

    @discardableResult
    mutating func openDirectory(_ key: String, allowedKeys: Set<String>) -> Bool {
        guard service == .grocery, allowedKeys.contains(key) else { return false }
        startsWithSearch = false
        section = .home
        directoryKey = key
        directoryRevision &+= 1
        return true
    }

    private mutating func resetCurrentHome() {
        startsWithSearch = false
        if service == .grocery {
            groceryHomeRevision &+= 1
            directoryKey = nil
        } else { foodHomeRevision &+= 1 }
    }

    mutating func updateDirectoryHighlight(_ key: String?, allowedKeys: Set<String>) {
        guard key == nil || allowedKeys.contains(key!) else { return }
        directoryKey = key
    }
}

enum DastakCustomerAccountPanel: Equatable {
    case combined, profile, settings
    enum Section: CaseIterable, Hashable { case details, addresses, shopping, preferences, identity, actions, support, partners }
    var title: String {
        switch self { case .combined: "Account"; case .profile: "Profile"; case .settings: "Settings" }
    }
    var sections: [Section] {
        switch self {
        case .combined: Section.allCases
        case .profile: [.details, .addresses, .shopping]
        case .settings: [.preferences, .identity, .actions, .support, .partners]
        }
    }
}
