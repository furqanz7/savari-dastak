import Foundation
import MarketplaceFoundation

public enum DastakV1BrowseLoadError: Error, Sendable {
    case invalidMap
    case invalidPagination
}

public struct DastakV1CatalogueBrowseMap: Decodable, Equatable, Sendable {
    public struct Source: Decodable, Equatable, Sendable {
        public let typeSlug: String
        public let categorySlug: String?
        public let subcategorySlug: String?
        public let excludedCategorySlugs: [String]
        public let excludedSubcategorySlugs: [String]
    }

    public struct Node: Decodable, Equatable, Identifiable, Sendable {
        public let key: String
        public let parentKey: String?
        public let kind: String
        public let label: String
        public let sortOrder: Int
        public let sources: [Source]
        public var id: String { key }
    }

    public let version: Int
    public let nodes: [Node]

    public var isValid: Bool {
        guard version > 0, !nodes.isEmpty else { return false }
        let byKey = Dictionary(nodes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        guard byKey.count == nodes.count else { return false }
        return nodes.allSatisfy { node in
            switch node.kind {
            case "SECTION": return node.parentKey == nil
            case "DESTINATION": return node.parentKey.flatMap { byKey[$0] }?.kind == "SECTION"
            case "RAIL": return node.parentKey.flatMap { byKey[$0] }?.kind == "DESTINATION"
            default: return false
            }
        }
    }

    public func children(of parentKey: String?) -> [Node] {
        guard isValid else { return [] }
        return nodes.filter { $0.parentKey == parentKey }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.key < $1.key : $0.sortOrder < $1.sortOrder }
    }

    public struct Taxonomy: Sendable {
        public struct Category: Sendable {
            public let id: UUID
            public let typeID: UUID
            public let slug: String
            public init(id: UUID, typeID: UUID, slug: String) {
                self.id = id; self.typeID = typeID; self.slug = slug
            }
        }
        public struct Subcategory: Sendable {
            public let id: UUID
            public let categoryID: UUID
            public let slug: String
            public init(id: UUID, categoryID: UUID, slug: String) {
                self.id = id; self.categoryID = categoryID; self.slug = slug
            }
        }
        public let typeSlugs: [UUID: String]
        public let categories: [UUID: Category]
        public let subcategories: [UUID: Subcategory]
        public init(typeSlugs: [UUID: String], categories: [Category], subcategories: [Subcategory]) {
            self.typeSlugs = typeSlugs
            self.categories = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.subcategories = Dictionary(subcategories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    public func matches(nodeKey: String, categoryID: UUID, subcategoryID: UUID, taxonomy: Taxonomy) -> Bool {
        guard isValid, let node = nodes.first(where: { $0.key == nodeKey }),
              let category = taxonomy.categories[categoryID],
              let subcategory = taxonomy.subcategories[subcategoryID],
              subcategory.categoryID == category.id,
              let typeSlug = taxonomy.typeSlugs[category.typeID] else { return false }
        return node.sources.contains { source in
            source.typeSlug == typeSlug &&
            (source.categorySlug == nil || source.categorySlug == category.slug) &&
            (source.subcategorySlug == nil || source.subcategorySlug == subcategory.slug) &&
            !source.excludedCategorySlugs.contains(category.slug) &&
            !source.excludedSubcategorySlugs.contains(subcategory.slug)
        }
    }
}

struct DastakV1CatalogueBrowseRequest: Encodable, Sendable {
    let operation = "catalogueBrowseMap"
}

// Existing test doubles may not implement the staged browse-map endpoint.
// Production clients above provide the real implementation.
public extension DastakV1CustomerClient {
    func catalogueBrowseMap(idempotencyKey: IdempotencyKey) async throws -> DastakV1CatalogueBrowseMap? { nil }
}

public extension DastakV1MerchantClient {
    func catalogueBrowseMap(idempotencyKey: IdempotencyKey) async throws -> DastakV1CatalogueBrowseMap? { nil }
}

public extension DastakV1AdminClient {
    func catalogueBrowseMap(idempotencyKey: IdempotencyKey) async throws -> DastakV1CatalogueBrowseMap? { nil }
}
