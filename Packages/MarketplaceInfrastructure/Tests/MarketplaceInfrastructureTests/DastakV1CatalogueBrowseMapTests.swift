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
    }

    func testMalformedMapCannotMatchProducts() throws {
        let json = #"{"version":1,"nodes":[{"key":"rice","parentKey":"missing","kind":"RAIL","label":"Rice","sortOrder":0,"sources":[]}]}"#
        let map = try JSONDecoder().decode(DastakV1CatalogueBrowseMap.self, from: Data(json.utf8))
        XCTAssertFalse(map.isValid)
        XCTAssertTrue(map.children(of: "missing").isEmpty)
    }
}
