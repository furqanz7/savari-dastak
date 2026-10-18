import Foundation
import MarketplaceInfrastructure

/// One loaded-catalogue filter for directory, browse-map and search routes.
/// Client filtering is never an authorization or completeness boundary.
enum DastakMerchantCataloguePresentation {
    static func products(_ snapshot: DastakV1MerchantCatalogueSnapshot, query: String, selectedOnly: Bool,
        pending: [UUID: Bool] = [:], typeID: UUID? = nil, categoryID: UUID? = nil, subcategoryID: UUID? = nil,
        map: DastakV1CatalogueBrowseMap? = nil, nodeKey: String? = nil) -> [DastakV1MerchantCatalogueSnapshot.SKU] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let categories = Dictionary(snapshot.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let subcategories = Dictionary(snapshot.subcategories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let types = Dictionary(snapshot.categoryTypes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let taxonomy = DastakV1CatalogueBrowseMap.Taxonomy(typeSlugs: types.mapValues(\.slug),
            categories: snapshot.categories.compactMap { category in category.categoryTypeID.map { .init(id: category.id, typeID: $0, slug: category.slug) } },
            subcategories: snapshot.subcategories.map { .init(id: $0.id, categoryID: $0.categoryID, slug: $0.slug) })
        let mapped = nodeKey.flatMap { map?.matchingSubcategories(nodeKey: $0, taxonomy: taxonomy) }
        return snapshot.skus.filter { sku in
            guard !selectedOnly || (pending[sku.id] ?? sku.selected) else { return false }
            // Search always covers all loaded products in the chosen scope,
            // not just whichever destination happened to be open beforehand.
            if query.isEmpty {
                guard typeID == nil || (sku.categoryTypeID ?? categories[sku.categoryID]?.categoryTypeID) == typeID,
                      categoryID == nil || sku.categoryID == categoryID,
                      subcategoryID == nil || sku.subcategoryID == subcategoryID else { return false }
                if nodeKey != nil { return mapped?[sku.subcategoryID] == sku.categoryID }
                return true
            }
            let category = categories[sku.categoryID], subcategory = subcategories[sku.subcategoryID]
            let type = (sku.categoryTypeID ?? category?.categoryTypeID).flatMap { types[$0] }
            let fields = [sku.name, sku.brandName, sku.variant, sku.packSize, sku.description,
                          category?.name, category?.slug, subcategory?.name, subcategory?.slug, type?.name, type?.slug]
            return (fields.compactMap { $0 } + sku.searchTerms).joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }
    static func showsResults(query: String, selectedOnly: Bool, hasDestination: Bool) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (selectedOnly && !hasDestination)
    }
    static func emptyMessage(query: String, selectedOnly: Bool, truncated: Bool, current: Bool) -> String {
        if !current { return "These last-known results could not be verified. Refresh before assuming the catalogue or storefront is empty." }
        if truncated { return "No matches in the loaded products. This catalogue is incomplete; other matching or selected products may be outside the loaded set." }
        if selectedOnly { return "No matching selected products in this loaded catalogue. Unsaved selections are included. Switch to All products to browse the library." }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No products were returned for this loaded category. Choose another category or refresh."
            : "No matches in the loaded catalogue. Try another product, brand, pack, variant or category."
    }
    static func validSnapshot(_ value: DastakV1MerchantCatalogueSnapshot) -> Bool {
        value.branch.branchVersion > 0 && value.branch.operationalState.version > 0
            && Set(value.skus.map(\.id)).count == value.skus.count
            && value.skus.allSatisfy { $0.selectionVersion >= 0 && $0.currencyCode == "INR" && $0.sellingPricePaise >= 0 }
    }
}
