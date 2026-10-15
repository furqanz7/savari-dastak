import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

public struct DastakCartEntry: Codable, Identifiable, Equatable, Sendable {
    public let product: DastakV1CatalogueSKU
    public var quantity: Int

    public var id: UUID { product.id }
    public var subtotal: Money {
        Money(paise: product.sellingPricePaise * quantity)
    }
}

public enum DastakCartAddResult: Equatable, Sendable {
    case added
    case quantityLimit
}

public struct DastakFoodCartEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let restaurantBranchID: UUID
    public let restaurantName: String
    public let item: DastakV1RestaurantMenuItem
    public let optionIDs: [UUID]
    public let optionNames: [String]
    public let unitPricePaise: Int
    public var quantity: Int

    public var subtotal: Money { Money(paise: unitPricePaise * quantity) }
}

public enum DastakFoodCartAddResult: Equatable, Sendable {
    case added
    case quantityLimit
    case differentRestaurant
}

struct DastakReorderResult: Equatable, Sendable {
    let addedUnits: Int
    let skippedLines: Int

    var openedBasket: Bool { addedUnits > 0 }
}

/// Captured before replacement consent, not after the user approves it.
struct DastakReorderReview: Identifiable, Sendable {
    let id = UUID()
    let order: DastakV1OrderSnapshot
    let service: DastakBasketService
    let baskets: DastakCustomerBaskets
    let activeService: DastakBasketService
    let accountID: UUID?
    let areaKey: String
    let contextRevision: UUID
    var requiresReplacement: Bool { !baskets[service].isEmpty }

    static func services(for order: DastakV1OrderSnapshot) -> [DastakBasketService] {
        guard !order.lines.isEmpty, order.lines.allSatisfy({ line in
            (line.lineType == "RETAIL_SKU" && line.skuID != nil && line.menuItemID == nil)
                || (line.lineType == "FOOD_MENU_ITEM" && line.menuItemID != nil && line.skuID == nil)
        }) else { return [] }
        return DastakBasketService.allCases.filter { service in
            order.lines.contains { $0.lineType == (service == .grocery ? "RETAIL_SKU" : "FOOD_MENU_ITEM") }
        }
    }
}

public struct DastakCart: Codable, Equatable, Sendable {
    public static let maximumQuantity = 99
    public private(set) var entries: [DastakCartEntry] = []
    public private(set) var foodEntries: [DastakFoodCartEntry] = []

    public init() {}

    public var itemCount: Int {
        entries.reduce(0) { $0 + $1.quantity } + foodEntries.reduce(0) { $0 + $1.quantity }
    }

    public var isEmpty: Bool { entries.isEmpty && foodEntries.isEmpty }

    public var subtotal: Money {
        Money(paise: entries.reduce(0) { $0 + $1.subtotal.paise } + foodEntries.reduce(0) { $0 + $1.subtotal.paise })
    }

    public var orderLines: [DastakV1OrderLineInput] {
        entries.map {
            DastakV1OrderLineInput(skuID: $0.product.id, quantity: $0.quantity)
        } + foodEntries.map {
            DastakV1OrderLineInput(
                menuItemID: $0.item.id,
                optionIDs: $0.optionIDs,
                quantity: $0.quantity
            )
        }
    }

    public var restaurantBranchID: UUID? { foodEntries.first?.restaurantBranchID }

    @discardableResult
    public mutating func add(_ product: DastakV1CatalogueSKU) -> DastakCartAddResult {
        if let index = entries.firstIndex(where: { $0.product.id == product.id }) {
            guard entries[index].quantity < Self.maximumQuantity else {
                return .quantityLimit
            }
            entries[index].quantity += 1
        } else {
            entries.append(DastakCartEntry(product: product, quantity: 1))
        }
        return .added
    }

    public mutating func decrement(_ productID: UUID) {
        guard let index = entries.firstIndex(where: { $0.product.id == productID }) else {
            return
        }
        if entries[index].quantity > 1 {
            entries[index].quantity -= 1
        } else {
            entries.remove(at: index)
        }
    }

    @discardableResult
    public mutating func addFood(
        restaurant: DastakV1RestaurantIdentity,
        item: DastakV1RestaurantMenuItem,
        optionIDs: [UUID]
    ) -> DastakFoodCartAddResult {
        if let branchID = restaurantBranchID, branchID != restaurant.branchID {
            return .differentRestaurant
        }
        let options = item.optionGroups.flatMap(\.options).filter { optionIDs.contains($0.id) }
        let normalized = options.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let key = item.id.uuidString + ":" + normalized.map(\.uuidString).joined(separator: ",")
        if let index = foodEntries.firstIndex(where: { $0.id == key }) {
            guard foodEntries[index].quantity < Self.maximumQuantity else { return .quantityLimit }
            foodEntries[index].quantity += 1
        } else {
            foodEntries.append(DastakFoodCartEntry(
                id: key,
                restaurantBranchID: restaurant.branchID,
                restaurantName: DastakRestaurantPresentation.customerFacingName(
                    name: restaurant.name, branchName: restaurant.branchName
                ),
                item: item,
                optionIDs: normalized,
                optionNames: options.map(\.name),
                unitPricePaise: item.basePricePaise + options.reduce(0) { $0 + $1.priceDeltaPaise },
                quantity: 1
            ))
        }
        return .added
    }

    public mutating func decrementFood(_ entryID: String) {
        guard let index = foodEntries.firstIndex(where: { $0.id == entryID }) else { return }
        if foodEntries[index].quantity > 1 { foodEntries[index].quantity -= 1 }
        else { foodEntries.remove(at: index) }
    }

    public mutating func incrementFood(_ entryID: String) -> DastakFoodCartAddResult {
        guard let index = foodEntries.firstIndex(where: { $0.id == entryID }) else { return .added }
        guard foodEntries[index].quantity < Self.maximumQuantity else { return .quantityLimit }
        foodEntries[index].quantity += 1
        return .added
    }

    public mutating func removeAll() {
        entries.removeAll()
        foodEntries.removeAll()
    }

    func only(_ service: DastakBasketService) -> Self {
        var result = self
        if service == .grocery { result.foodEntries.removeAll() }
        else { result.entries.removeAll() }
        return result
    }
}

enum DastakBasketService: String, Codable, CaseIterable, Identifiable, Sendable {
    case grocery, food
    var id: String { rawValue }
    var title: String { self == .grocery ? "Grocery" : "Food" }
}

struct DastakCustomerBaskets: Codable, Equatable, Sendable {
    private var grocery = DastakCart()
    private var food = DastakCart()

    subscript(_ service: DastakBasketService) -> DastakCart {
        get { service == .grocery ? grocery : food }
        set {
            // Keep even legacy mixed reorders out of a combined checkout.
            if service == .grocery { grocery = newValue.only(.grocery) }
            else { food = newValue.only(.food) }
        }
    }

    var isValid: Bool {
        guard grocery.foodEntries.isEmpty, food.entries.isEmpty,
              grocery.entries.count <= 500, food.foodEntries.count <= 500,
              Set(grocery.entries.map(\.id)).count == grocery.entries.count,
              Set(food.foodEntries.map(\.id)).count == food.foodEntries.count,
              Set(food.foodEntries.map(\.restaurantBranchID)).count <= 1 else { return false }
        // Bound cached values before any subtotal arithmetic. Prices are estimates;
        // only IDs, options and quantities are sent to the authoritative server.
        let safePrice = Int.max / DastakCart.maximumQuantity / 1_000
        return grocery.entries.allSatisfy {
            (1...DastakCart.maximumQuantity).contains($0.quantity)
                && (0...safePrice).contains($0.product.sellingPricePaise)
        } && food.foodEntries.allSatisfy {
            (1...DastakCart.maximumQuantity).contains($0.quantity)
                && (0...safePrice).contains($0.unitPricePaise)
                && $0.id == $0.item.id.uuidString + ":" + $0.optionIDs.map(\.uuidString).joined(separator: ",")
        }
    }
}

/// Local, versioned basket cache. No shared/anonymous account fallback and no
/// recipient, address, access token or payment details are stored here.
@MainActor
struct DastakBasketStore {
    let defaults: UserDefaults

    private struct Envelope: Codable {
        let version: Int
        let accountID: UUID
        let baskets: DastakCustomerBaskets
    }

    func load(accountID: UUID) -> DastakCustomerBaskets {
        guard let data = defaults.data(forKey: key(accountID)), data.count <= 2_000_000,
              let saved = try? JSONDecoder().decode(Envelope.self, from: data),
              saved.version == 1, saved.accountID == accountID, saved.baskets.isValid else {
            return DastakCustomerBaskets()
        }
        return saved.baskets
    }

    func save(_ baskets: DastakCustomerBaskets, accountID: UUID) {
        guard baskets.isValid,
              let data = try? JSONEncoder().encode(Envelope(version: 1, accountID: accountID, baskets: baskets)),
              data.count <= 2_000_000 else { return }
        defaults.set(data, forKey: key(accountID))
    }

    func remove(accountID: UUID) {
        defaults.removeObject(forKey: key(accountID))
    }

    private func key(_ accountID: UUID) -> String {
        "dastak.customer.\(accountID.uuidString.lowercased()).baskets.v1"
    }
}
