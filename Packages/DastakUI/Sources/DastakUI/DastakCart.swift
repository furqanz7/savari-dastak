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

public struct DastakCart: Equatable, Sendable {
    public static let maximumQuantity = 99
    public private(set) var entries: [DastakCartEntry] = []

    public init() {}

    public var itemCount: Int {
        entries.reduce(0) { $0 + $1.quantity }
    }

    public var subtotal: Money {
        Money(paise: entries.reduce(0) { $0 + $1.subtotal.paise })
    }

    public var orderLines: [DastakV1OrderLineInput] {
        entries.map {
            DastakV1OrderLineInput(skuID: $0.product.id, quantity: $0.quantity)
        }
    }

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

    public mutating func removeAll() {
        entries.removeAll()
    }
}
