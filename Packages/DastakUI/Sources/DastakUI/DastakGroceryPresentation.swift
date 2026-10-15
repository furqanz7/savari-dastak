import Foundation
import MarketplaceInfrastructure

/// Presentation only. Pack selection still adds the exact SKU through CustomerModel.
enum DastakGroceryPresentation {
    static func purchaseTitle(stockQuantity: Int?, chooseSize: Bool = false) -> String {
        // A grouped shelf tile opens its sizes even if every size is sold out.
        // Inside the product card the selected exact SKU controls the action.
        if chooseSize { return "Choose size" }
        return stockQuantity == 0 ? "Out of stock" : "ADD"
    }

    static func searchPackDescription(_ product: DastakV1CatalogueSKU) -> String {
        [product.variant, product.packSize].compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    static func searchAccessibilityIdentity(_ product: DastakV1CatalogueSKU) -> String {
        [product.name, searchPackDescription(product)]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    struct Family: Identifiable {
        let product: DastakV1CatalogueSKU
        var packs: [DastakV1CatalogueSKU]
        var id: UUID { product.id }
    }

    struct ShelfBasketSelection {
        let product: DastakV1CatalogueSKU
        let quantity: Int
        let hasMultipleSizes: Bool
    }

    static func shelfBasketSelection(_ family: Family, cart: DastakCart) -> ShelfBasketSelection {
        let packs = Set(family.packs.map(\.id))
        let entries = cart.entries.filter { packs.contains($0.id) && $0.quantity > 0 }
        let selected = entries.first.flatMap { entry in family.packs.first { $0.id == entry.id } } ?? family.product
        return ShelfBasketSelection(product: selected, quantity: entries.reduce(0) { $0 + $1.quantity },
                                    hasMultipleSizes: entries.count > 1)
    }

    /// One carousel page per product family; pack selection never changes pages.
    struct DetailDeck {
        let families: [Family]
        var selectedFamilyID: UUID
        private var selectedPacks: [UUID: UUID] = [:]

        init(initial: DastakV1CatalogueSKU, products: [DastakV1CatalogueSKU]) {
            var candidates = products.filter { $0.categoryID == initial.categoryID }
            if !candidates.contains(where: { $0.id == initial.id }) { candidates.insert(initial, at: 0) }
            families = DastakGroceryPresentation.families(candidates)
            let family = families.first { $0.packs.contains(where: { $0.id == initial.id }) }!
            selectedFamilyID = family.id
            selectedPacks[family.id] = initial.id
        }

        func selectedProduct(in familyID: UUID) -> DastakV1CatalogueSKU? {
            guard let family = families.first(where: { $0.id == familyID }) else { return nil }
            return family.packs.first { $0.id == selectedPacks[familyID] } ?? family.product
        }

        mutating func selectPack(_ packID: UUID, in familyID: UUID) {
            guard families.contains(where: { $0.id == familyID && $0.packs.contains(where: { $0.id == packID }) }) else { return }
            selectedPacks[familyID] = packID
        }
    }
    private struct Key: Hashable {
        let category: UUID
        let subcategory: UUID
        let brand: String
        let variant: String?
        let name: String
    }

    static func families(_ products: [DastakV1CatalogueSKU]) -> [Family] {
        var result: [Family] = []
        var indices: [Key: Int] = [:]
        var seen = Set<UUID>()
        for product in products where seen.insert(product.id).inserted {
            let key = key(product)
            if let key, let index = indices[key] {
                result[index].packs.append(product)
            } else {
                if let key { indices[key] = result.count }
                result.append(Family(product: product, packs: [product]))
            }
        }
        return result
    }

    static func normalizedName(_ name: String, packSize: String) -> String {
        name.lowercased().replacingOccurrences(of: packSize.lowercased(), with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func sameFamily(_ a: DastakV1CatalogueSKU, _ b: DastakV1CatalogueSKU) -> Bool {
        guard a.id != b.id else { return true }
        guard let first = key(a), let second = key(b) else { return false }
        return first == second
    }

    private static func key(_ product: DastakV1CatalogueSKU) -> Key? {
        guard let brand = product.brand?.name, !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let name = normalizedName(product.name, packSize: product.packSize)
        guard !name.isEmpty else { return nil }
        return Key(category: product.categoryID, subcategory: product.subcategoryID,
                   brand: brand, variant: product.variant, name: name)
    }
}
