import Foundation
import MarketplaceInfrastructure

/// Web-equivalent discovery destinations, using the existing native catalogue only.
enum DastakGroceryHomePresentation {
    struct QuickPick: Identifiable, Equatable {
        let id: String
        let label: String
        let destinationKey: String
        let imageKeys: [String]
    }

    static func greeting(hour: Int, displayName: String?) -> String {
        let greeting = (5..<12).contains(hour) ? "Good morning"
            : (12..<18).contains(hour) ? "Good afternoon" : "Good evening"
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? greeting : "\(greeting), \(name)"
    }

    static func quickPicks(map: DastakV1CatalogueBrowseMap,
                          catalogue: DastakV1CatalogueSnapshot,
                          products: [DastakV1CatalogueSKU], limit: Int = 6, date: Date = .now) -> [QuickPick] {
        guard limit > 0, map.isValid, let types = catalogue.categoryTypes else { return [] }
        let taxonomy = DastakV1CatalogueBrowseMap.Taxonomy(
            typeSlugs: Dictionary(types.map { ($0.id, $0.slug) }, uniquingKeysWith: { first, _ in first }),
            categories: catalogue.categories.compactMap { category in
                category.categoryTypeID.map { .init(id: category.id, typeID: $0, slug: category.slug) }
            }, subcategories: catalogue.subcategories.map { .init(id: $0.id, categoryID: $0.categoryID, slug: $0.slug) })
        let loaded = Dictionary(grouping: products, by: \.subcategoryID)
        let ordered = map.nodes.sorted { ($0.sortOrder, $0.key) < ($1.sortOrder, $1.key) }
        let children = Dictionary(grouping: ordered, by: { $0.parentKey ?? "" })
        var result: [QuickPick] = []
        for section in children[""] ?? [] where section.kind == "SECTION" {
            for destination in children[section.key] ?? [] where destination.kind == "DESTINATION" {
                for rail in children[destination.key] ?? [] where rail.kind == "RAIL" {
                    let scope = map.matchingSubcategories(nodeKey: rail.key, taxonomy: taxonomy)
                    let matchingProducts = scope.flatMap { subcategory, category in
                        (loaded[subcategory] ?? []).filter { $0.categoryID == category }
                    }.sorted { $0.id.uuidString < $1.id.uuidString }
                    let populatedSubcategories = Set(matchingProducts.map(\.subcategoryID))
                    // The server's approved preview photos cover the full taxonomy,
                    // including products beyond the initial 250-SKU page.
                    let subcategories = catalogue.subcategories.filter {
                        scope[$0.id] == $0.categoryID &&
                        (populatedSubcategories.contains($0.id) || ($0.previewImageKeys?.contains {
                            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        } == true))
                    }
                        .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
                    var seen = Set<String>()
                    let images = (subcategories.flatMap { $0.previewImageKeys ?? [] }
                                  + matchingProducts.compactMap(\.imageKey)
                                  + subcategories.compactMap(\.imageKey))
                        .filter {
                            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                            !$0.hasPrefix("canonical/taxonomy/") && seen.insert($0).inserted
                        }
                    guard !images.isEmpty else { continue }
                    result.append(QuickPick(id: rail.key, label: rail.label, destinationKey: destination.key,
                                            imageKeys: Array(images.prefix(4))))
                }
            }
        }
        // Shuffle the full eligible pool once per UTC day, then rotate a window
        // every 15 minutes. Every candidate gets a turn; Swift's randomized
        // Hasher and random render-time shuffles would make the row jump around.
        let interval = Int64(max(0, date.timeIntervalSince1970) / 900)
        let day = interval / 96
        let shuffled = result.sorted {
            let left = stableRank("\(day)|\($0.id)"), right = stableRank("\(day)|\($1.id)")
            return left == right ? $0.id < $1.id : left < right
        }
        guard !shuffled.isEmpty else { return [] }
        let step = shuffled.count > limit ? limit : 1
        let start = Int(interval % 96) * step % shuffled.count
        return (0..<min(limit, shuffled.count)).map { shuffled[(start + $0) % shuffled.count] }
    }

    private static func stableRank(_ value: String) -> UInt64 {
        var hash = value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        hash = (hash ^ (hash >> 33)) &* 0xff51afd7ed558ccd
        hash = (hash ^ (hash >> 33)) &* 0xc4ceb9fe1a85ec53
        return hash ^ (hash >> 33)
    }
}
