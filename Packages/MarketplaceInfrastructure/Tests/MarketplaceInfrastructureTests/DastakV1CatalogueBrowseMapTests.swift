import Foundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakV1CatalogueBrowseMapTests: XCTestCase {
    func testRiceBasmatiAndPohaHaveDistinctSources() throws {
        let json = #"{"version":1,"nodes":[{"key":"staples","parentKey":null,"kind":"SECTION","label":"Staples","sortOrder":0,"sources":[]},{"key":"rice","parentKey":"staples","kind":"DESTINATION","label":"Rice","sortOrder":0,"sources":[{"typeSlug":"staples","categorySlug":"rice","subcategorySlug":null,"excludedCategorySlugs":[],"excludedSubcategorySlugs":["basmati","poha"]}]},{"key":"basmati","parentKey":"rice","kind":"RAIL","label":"Basmati Rice","sortOrder":0,"sources":[{"typeSlug":"staples","categorySlug":"rice","subcategorySlug":"basmati","excludedCategorySlugs":[],"excludedSubcategorySlugs":[]}]},{"key":"poha","parentKey":"rice","kind":"RAIL","label":"Poha & Puffed Rice","sortOrder":1,"sources":[{"typeSlug":"staples","categorySlug":"rice","subcategorySlug":"poha","excludedCategorySlugs":[],"excludedSubcategorySlugs":[]}]}]}"#
        let map = try JSONDecoder().decode(DastakV1CatalogueBrowseMap.self, from: Data(json.utf8))
        let typeID = UUID()
        let categoryID = UUID()
        let ordinaryID = UUID()
        let basmatiID = UUID()
        let pohaID = UUID()
        let taxonomy = DastakV1CatalogueBrowseMap.Taxonomy(
            typeSlugs: [typeID: "staples"],
            categories: [.init(id: categoryID, typeID: typeID, slug: "rice")],
            subcategories: [
                .init(id: ordinaryID, categoryID: categoryID, slug: "ordinary"),
                .init(id: basmatiID, categoryID: categoryID, slug: "basmati"),
                .init(id: pohaID, categoryID: categoryID, slug: "poha"),
            ]
        )

        XCTAssertTrue(map.isValid)
        XCTAssertEqual(map.children(of: "rice").map(\.key), ["basmati", "poha"])
        XCTAssertTrue(map.matches(nodeKey: "rice", categoryID: categoryID, subcategoryID: ordinaryID, taxonomy: taxonomy))
        XCTAssertFalse(map.matches(nodeKey: "rice", categoryID: categoryID, subcategoryID: basmatiID, taxonomy: taxonomy))
        XCTAssertFalse(map.matches(nodeKey: "rice", categoryID: categoryID, subcategoryID: pohaID, taxonomy: taxonomy))
        XCTAssertTrue(map.matches(nodeKey: "basmati", categoryID: categoryID, subcategoryID: basmatiID, taxonomy: taxonomy))
        XCTAssertFalse(map.matches(nodeKey: "basmati", categoryID: categoryID, subcategoryID: pohaID, taxonomy: taxonomy))
        XCTAssertTrue(map.matches(nodeKey: "poha", categoryID: categoryID, subcategoryID: pohaID, taxonomy: taxonomy))
        XCTAssertEqual(map.matchingSubcategories(nodeKey: "rice", taxonomy: taxonomy), [ordinaryID: categoryID])
        XCTAssertEqual(map.matchingSubcategories(nodeKey: "basmati", taxonomy: taxonomy), [basmatiID: categoryID])
        XCTAssertEqual(map.matchingSubcategories(nodeKey: "poha", taxonomy: taxonomy), [pohaID: categoryID])
        XCTAssertTrue(map.matchingSubcategories(nodeKey: "missing", taxonomy: taxonomy).isEmpty)
    }

    func testMalformedMapCannotMatchProducts() throws {
        let json = #"{"version":1,"nodes":[{"key":"rice","parentKey":"missing","kind":"RAIL","label":"Rice","sortOrder":0,"sources":[]}]}"#
        let map = try JSONDecoder().decode(DastakV1CatalogueBrowseMap.self, from: Data(json.utf8))
        XCTAssertFalse(map.isValid)
        XCTAssertTrue(map.children(of: "missing").isEmpty)
        XCTAssertTrue(map.matchingSubcategories(nodeKey: "rice", taxonomy: .init(typeSlugs: [:], categories: [], subcategories: [])).isEmpty)
    }

    func testLargeCatalogueResolvesSameCategoriesWithoutCartesianMapValidation() throws {
        let typeID = UUID()
        let categories = (0..<50).map { Taxonomy.Category(id: UUID(), typeID: typeID, slug: "category-\($0)") }
        let subcategories = categories.flatMap { category in
            (0..<8).map { Taxonomy.Subcategory(id: UUID(), categoryID: category.id, slug: "sub-\($0)") }
        }
        let taxonomy = Taxonomy(typeSlugs: [typeID: "grocery"], categories: categories, subcategories: subcategories)
        let source = DastakV1CatalogueBrowseMap.Source(typeSlug: "grocery", categorySlug: nil, subcategorySlug: "sub-0",
            excludedCategorySlugs: ["category-0"], excludedSubcategorySlugs: [])
        var nodes = [DastakV1CatalogueBrowseMap.Node(key: "section", parentKey: nil, kind: "SECTION", label: "Section", sortOrder: 0, sources: [])]
        nodes += (0..<100).map { .init(key: "destination-\($0)", parentKey: "section", kind: "DESTINATION", label: "Destination", sortOrder: $0, sources: [source]) }
        let map = DastakV1CatalogueBrowseMap(version: 1, nodes: nodes)
        let clock = ContinuousClock()
        let oldStart = clock.now
        let previous = Set(categories.filter { category in
            subcategories.contains { map.matches(nodeKey: "destination-99", categoryID: category.id, subcategoryID: $0.id, taxonomy: taxonomy) }
        }.map(\.id))
        let previousDuration = oldStart.duration(to: clock.now)
        let start = clock.now
        let resolved = map.matchingSubcategories(nodeKey: "destination-99", taxonomy: taxonomy)
        let duration = start.duration(to: clock.now)
        XCTAssertEqual(Set(resolved.values), previous)
        XCTAssertEqual(resolved.count, 49)
        print("Catalogue category lookup: previous=\(previousDuration), resolved=\(duration)")
    }
}

private typealias Taxonomy = DastakV1CatalogueBrowseMap.Taxonomy
