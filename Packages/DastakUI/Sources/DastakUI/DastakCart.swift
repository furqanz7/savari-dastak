import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

public struct DastakCartEntry: Identifiable, Equatable, Sendable {
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

public struct DastakFoodCartEntry: Identifiable, Equatable, Sendable {
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

public struct DastakCart: Equatable, Sendable {
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
                restaurantName: restaurant.name,
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
}
