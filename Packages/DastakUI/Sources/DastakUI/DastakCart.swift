import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

public struct DastakCartEntry: Identifiable, Equatable, Sendable {
    public let product: CatalogueProduct
    public var quantity: Int

    public var id: UUID { product.productID }
    public var subtotal: Money {
        Money(paise: product.price.paise * quantity)
    }
}

public enum DastakCartAddResult: Equatable, Sendable {
    case added
    case differentStore
    case unavailable
}

public struct DastakCart: Equatable, Sendable {
    public private(set) var storeID: UUID?
    public private(set) var entries: [DastakCartEntry] = []

    public init() {}

    public var itemCount: Int {
        entries.reduce(0) { $0 + $1.quantity }
    }

    public var subtotal: Money {
        Money(paise: entries.reduce(0) { $0 + $1.subtotal.paise })
    }

    public var orderLines: [MerchantOrderLineInput] {
        entries.map {
            MerchantOrderLineInput(productID: $0.product.productID, quantity: $0.quantity)
        }
    }

    @discardableResult
    public mutating func add(_ product: CatalogueProduct) -> DastakCartAddResult {
        guard product.isActive, product.availability == .inStock else {
            return .unavailable
        }
        if let storeID, storeID != product.storeID, !entries.isEmpty {
            return .differentStore
        }
        storeID = product.storeID
        if let index = entries.firstIndex(where: { $0.product.productID == product.productID }) {
            entries[index].quantity += 1
        } else {
            entries.append(DastakCartEntry(product: product, quantity: 1))
        }
        return .added
    }

    public mutating func decrement(_ productID: UUID) {
        guard let index = entries.firstIndex(where: { $0.product.productID == productID }) else {
            return
        }
        if entries[index].quantity > 1 {
            entries[index].quantity -= 1
        } else {
            entries.remove(at: index)
        }
        if entries.isEmpty {
            storeID = nil
        }
    }

    public mutating func replaceStore(with product: CatalogueProduct) {
        removeAll()
        _ = add(product)
    }

    public mutating func removeAll() {
        entries.removeAll()
        storeID = nil
    }
}
