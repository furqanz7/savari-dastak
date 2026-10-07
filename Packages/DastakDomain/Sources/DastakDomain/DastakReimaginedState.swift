import Foundation

public enum DastakReimaginedService: String, Equatable, Sendable {
    case grocery, food
}

public enum DastakReimaginedSection: Equatable, Sendable {
    case home, orders, profile, settings
}

public enum DastakReimaginedView: Equatable, Sendable {
    case home
    case category(UUID)
    case browse(String)
    case restaurant(UUID)
    case search(String)
}

public struct DastakReimaginedFoodCategoryMember: Equatable, Sendable {
    public let branchID: UUID
    public let categoryID: UUID
    public init(branchID: UUID, categoryID: UUID) { self.branchID = branchID; self.categoryID = categoryID }
}

public struct DastakReimaginedFoodCategoryFilter: Equatable, Sendable {
    public let label: String
    public let members: [DastakReimaginedFoodCategoryMember]
    public init(label: String, members: [DastakReimaginedFoodCategoryMember]) { self.label = label; self.members = members }
}

public struct DastakReimaginedExploration: Equatable, Sendable {
    public internal(set) var view: DastakReimaginedView = .home
    public internal(set) var searchOpen = false
    public internal(set) var searchDraft = ""
    public internal(set) var detailID: UUID?
    public internal(set) var productTypeFilters: [UUID: UUID] = [:]
    public internal(set) var foodCategoryFilter: DastakReimaginedFoodCategoryFilter?
    public internal(set) var checkout = false
}

public struct DastakReimaginedFoodLine: Equatable, Sendable {
    public let branchID: UUID
    public let itemID: UUID
    public let optionIDs: [UUID]
    public var quantity: Int

    public init(branchID: UUID, itemID: UUID, optionIDs: [UUID] = [], quantity: Int) {
        self.branchID = branchID
        self.itemID = itemID
        self.optionIDs = optionIDs
        self.quantity = quantity
    }

    fileprivate func matches(_ other: Self) -> Bool {
        branchID == other.branchID && itemID == other.itemID &&
            optionIDs.map(\.uuidString).sorted() == other.optionIDs.map(\.uuidString).sorted()
    }
}

public struct DastakReimaginedShopping: Equatable, Sendable {
    public var grocery: [UUID: Int]
    public var food: [DastakReimaginedFoodLine]

    public init(grocery: [UUID: Int] = [:], food: [DastakReimaginedFoodLine] = []) {
        self.grocery = grocery
        self.food = food
    }
}

public struct DastakReimaginedOrder: Equatable, Sendable {
    public let id: UUID
    public let service: DastakReimaginedService

    public init(id: UUID, service: DastakReimaginedService) {
        self.id = id
        self.service = service
    }
}

public enum DastakReimaginedEnvironment: Equatable, Sendable {
    case outside, groceryEntrance, groceryCounter, foodEntrance, foodApproachingCounter, foodCounter
}

public enum DastakReimaginedAction: Sendable {
    case signedIn(accountID: UUID, shopping: DastakReimaginedShopping = .init())
    case signedOut
    case selectService(DastakReimaginedService)
    case selectSoonService
    case navigate(DastakReimaginedSection)
    case openCategory(UUID)
    case openBrowseDestination(String)
    case openLocation, closeLocation
    case openRestaurant(UUID)
    case selectFoodCategory(DastakReimaginedFoodCategoryFilter?)
    case openDetail(UUID)
    case closeDetail
    case setProductType(subcategoryID: UUID, productTypeID: UUID?)
    case openSearch, closeSearch, submitSearch
    case typeSearch(String)
    case takeBucket
    case setGroceryQuantity(skuID: UUID, quantity: Int)
    case setFoodQuantity(DastakReimaginedFoodLine)
    case reviewShopping, continueShopping, checkoutFailed
    case checkoutSucceeded(service: DastakReimaginedService, orderID: UUID, purchased: DastakReimaginedShopping)
    case orderUpdated(DastakReimaginedOrder?)
    case outsideInteraction
}

/// Customer navigation and shopping intent. Prices, stock, taxonomy and order status come from existing clients.
public struct DastakReimaginedState: Equatable, Sendable {
    public private(set) var accountID: UUID?
    public private(set) var service: DastakReimaginedService = .grocery
    public private(set) var section: DastakReimaginedSection = .home
    public private(set) var grocery = DastakReimaginedExploration()
    public private(set) var food = DastakReimaginedExploration()
    public private(set) var shopping = DastakReimaginedShopping()
    public private(set) var bucketAcquired = false
    public private(set) var bucketPrompt = false
    public private(set) var locationOpen = false
    public private(set) var activeOrder: DastakReimaginedOrder?

    public init() {}

    public var environment: DastakReimaginedEnvironment {
        guard accountID != nil else { return .outside }
        if service == .grocery { return grocery.checkout ? .groceryCounter : .groceryEntrance }
        if food.checkout { return .foodCounter }
        return shopping.food.isEmpty ? .foodEntrance : .foodApproachingCounter
    }

    public mutating func send(_ action: DastakReimaginedAction) {
        switch action {
        case .signedOut:
            self = Self()
            return
        case let .signedIn(accountID, shopping):
            guard self.accountID != accountID else { return }
            self = Self()
            self.accountID = accountID
            self.shopping = shopping
            bucketAcquired = shopping.grocery.values.contains { $0 > 0 }
            return
        default: break
        }
        guard accountID != nil else { return }
        switch action {
        case let .selectService(destination):
            if service == destination { resetHome() }
            else { service = destination; section = .home; bucketPrompt = false }
        case let .navigate(destination):
            if destination == .home { resetHome() } else { section = destination }
        case let .openCategory(id):
            guard service == .grocery else { return }
            section = .home
            updateExploration { $0.view = .category(id); $0.detailID = nil; $0.checkout = false }
        case let .openBrowseDestination(key):
            guard service == .grocery else { return }
            section = .home
            updateExploration { $0.view = .browse(key); $0.detailID = nil; $0.checkout = false }
        case .openLocation: locationOpen = true
        case .closeLocation: locationOpen = false
        case let .openRestaurant(id):
            guard service == .food else { return }
            section = .home
            updateExploration { $0.view = .restaurant(id); $0.detailID = nil; $0.checkout = false }
        case let .selectFoodCategory(filter):
            guard service == .food else { return }
            section = .home
            updateExploration {
                $0.view = .home; $0.detailID = nil; $0.checkout = false; $0.searchOpen = false
                $0.foodCategoryFilter = filter
            }
        case let .openDetail(id): updateExploration { $0.detailID = id }
        case .closeDetail: updateExploration { $0.detailID = nil }
        case let .setProductType(subcategoryID, productTypeID):
            guard service == .grocery else { return }
            grocery.productTypeFilters[subcategoryID] = productTypeID
        case .openSearch: updateExploration { $0.searchOpen = true }
        case .closeSearch: updateExploration { $0.searchOpen = false }
        case let .typeSearch(query): updateExploration { $0.searchDraft = query }
        case .submitSearch:
            let query = (service == .grocery ? grocery : food).searchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            section = .home
            updateExploration { $0.view = .search(query); $0.searchOpen = false; $0.detailID = nil; $0.checkout = false }
        case .takeBucket:
            guard service == .grocery else { return }
            bucketAcquired = true
            bucketPrompt = false
        case let .setGroceryQuantity(skuID, quantity):
            guard service == .grocery, quantity >= 0 else { return }
            guard quantity == 0 || bucketAcquired else { bucketPrompt = true; return }
            shopping.grocery[skuID] = quantity > 0 ? quantity : nil
            bucketPrompt = false
            if shopping.grocery.isEmpty { grocery.checkout = false }
        case let .setFoodQuantity(line):
            guard service == .food, line.quantity >= 0 else { return }
            shopping.food.removeAll { $0.matches(line) }
            if line.quantity > 0 { shopping.food.append(line) }
            if shopping.food.isEmpty { food.checkout = false }
        case .reviewShopping:
            guard service == .grocery ? !shopping.grocery.isEmpty : !shopping.food.isEmpty else { return }
            section = .home
            updateExploration { $0.checkout = true; $0.searchOpen = false; $0.detailID = nil }
        case .continueShopping: updateExploration { $0.checkout = false }
        case let .checkoutSucceeded(purchasedService, orderID, purchased):
            // Consume the submitted snapshot so a late response cannot erase newly added items.
            if purchasedService == .grocery {
                for (id, quantity) in purchased.grocery {
                    let remaining = (shopping.grocery[id] ?? 0) - quantity
                    shopping.grocery[id] = remaining > 0 ? remaining : nil
                }
                grocery = .init()
            } else {
                shopping.food = shopping.food.compactMap { line in
                    var remaining = line
                    remaining.quantity -= purchased.food.first { $0.matches(line) }?.quantity ?? 0
                    return remaining.quantity > 0 ? remaining : nil
                }
                food = .init()
            }
            activeOrder = .init(id: orderID, service: purchasedService)
            bucketPrompt = false
        case let .orderUpdated(order): activeOrder = order
        case .checkoutFailed, .outsideInteraction, .selectSoonService, .signedIn, .signedOut: break
        }
    }

    private mutating func resetHome() {
        section = .home
        bucketPrompt = false
        if service == .grocery { grocery = .init() } else { food = .init() }
    }

    private mutating func updateExploration(_ update: (inout DastakReimaginedExploration) -> Void) {
        if service == .grocery { update(&grocery) } else { update(&food) }
    }
}
