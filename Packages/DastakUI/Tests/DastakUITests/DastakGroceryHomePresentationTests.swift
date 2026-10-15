import XCTest
import MarketplaceInfrastructure
@testable import DastakUI

final class DastakGroceryHomePresentationTests: XCTestCase {
    func testGreetingMatchesWebBoundariesAndDoesNotInventAName() {
        for hour in [0, 4, 18, 23] {
            XCTAssertEqual(DastakGroceryHomePresentation.greeting(hour: hour, displayName: nil), "Good evening")
        }
        for hour in [5, 11] {
            XCTAssertEqual(DastakGroceryHomePresentation.greeting(hour: hour, displayName: "  Furqan  "), "Good morning, Furqan")
        }
        for hour in [12, 17] {
            XCTAssertEqual(DastakGroceryHomePresentation.greeting(hour: hour, displayName: "  "), "Good afternoon")
        }
    }

    @MainActor
    func testQuickPicksUseLoadedCanonicalRailsAndKeepDirectoryRoute() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let map = try XCTUnwrap(model.v1BrowseMap)
        let catalogue = try catalogueWithPhoto(model)
        let picks = DastakGroceryHomePresentation.quickPicks(map: map, catalogue: catalogue,
            products: model.v1BrowseProducts)
        XCTAssertEqual(picks, [.init(id: "dairy-breakfast", label: "Dairy & breakfast", destinationKey: "essentials",
                                    imageKeys: ["canonical/test/dairy.jpg"])])
        XCTAssertEqual(model.categories(forBrowseNode: picks[0].id).count, 1)
        XCTAssertFalse(model.products(forBrowseNode: picks[0].id).isEmpty)
        XCTAssertTrue(DastakGroceryHomePresentation.quickPicks(map: map, catalogue: catalogue, products: []).isEmpty)
    }

    @MainActor
    func testEmptyExcludedInvalidAndWrongCategoryRailsDoNotBecomeQuickPicks() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true)
        let catalogue = try catalogueWithPhoto(model)
        let excludedJSON = DastakCustomerModel.previewBrowseMapJSON.replacingOccurrences(
            of: "\"excludedSubcategorySlugs\":[]", with: "\"excludedSubcategorySlugs\":[\"dairy-breakfast\"]")
        let excluded = try JSONDecoder().decode(DastakV1CatalogueBrowseMap.self, from: Data(excludedJSON.utf8))
        XCTAssertTrue(DastakGroceryHomePresentation.quickPicks(map: excluded, catalogue: catalogue,
            products: model.v1BrowseProducts).isEmpty)
        let invalid = try JSONDecoder().decode(DastakV1CatalogueBrowseMap.self,
            from: Data("{\"version\":1,\"nodes\":[]}".utf8))
        XCTAssertTrue(DastakGroceryHomePresentation.quickPicks(map: invalid, catalogue: catalogue,
            products: model.v1BrowseProducts).isEmpty)
        let sku = try XCTUnwrap(model.v1BrowseProducts.first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sku)) as? [String: Any])
        object["categoryId"] = "99999999-9999-4999-8999-999999999999"
        let mismatch = try JSONDecoder().decode(DastakV1CatalogueSKU.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(DastakGroceryHomePresentation.quickPicks(map: try XCTUnwrap(model.v1BrowseMap),
            catalogue: catalogue, products: [mismatch]).isEmpty)
    }

    @MainActor
    func testQuickPicksStayStableRotateAndGiveEveryCandidateATurn() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(DastakCustomerModel.previewBrowseMapJSON.utf8)) as? [String: Any])
        var nodes = try XCTUnwrap(object["nodes"] as? [[String: Any]])
        let template = try XCTUnwrap(nodes.last)
        nodes.removeLast()
        for index in (0..<8).reversed() {
            var rail = template
            rail["key"] = "rail-\(index)"
            rail["sortOrder"] = index
            nodes.append(rail)
        }
        object["nodes"] = nodes
        let map = try JSONDecoder().decode(DastakV1CatalogueBrowseMap.self,
            from: JSONSerialization.data(withJSONObject: object))
        let catalogue = try catalogueWithPhoto(model)
        let time = Date(timeIntervalSince1970: 900 * 96 * 20_000)
        let picks = DastakGroceryHomePresentation.quickPicks(map: map,
            catalogue: catalogue, products: model.v1BrowseProducts, date: time)
        XCTAssertEqual(picks.count, 6)
        XCTAssertEqual(Set(picks.map(\.id)).count, 6)
        XCTAssertEqual(picks, DastakGroceryHomePresentation.quickPicks(map: map,
            catalogue: catalogue, products: Array(model.v1BrowseProducts.reversed()), date: time.addingTimeInterval(899)))
        let next = DastakGroceryHomePresentation.quickPicks(map: map,
            catalogue: catalogue, products: model.v1BrowseProducts, date: time.addingTimeInterval(900))
        XCTAssertNotEqual(picks.map(\.id), next.map(\.id))
        XCTAssertEqual(Set((picks + next).map(\.id)), Set((0..<8).map { "rail-\($0)" }))
        XCTAssertTrue(DastakGroceryHomePresentation.quickPicks(map: map,
            catalogue: try XCTUnwrap(model.v1Catalogue), products: model.v1BrowseProducts, limit: 0).isEmpty)
    }

    @MainActor
    func testPhotosUseMatchingProductsAndDedicatedSubcategoryBackup() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true)
        let map = try XCTUnwrap(model.v1BrowseMap)
        var sku = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(model.v1BrowseProducts[0])) as? [String: Any])
        sku["imageKey"] = "canonical/test/milk.jpg"
        let product = try JSONDecoder().decode(DastakV1CatalogueSKU.self, from: JSONSerialization.data(withJSONObject: sku))
        let picks = DastakGroceryHomePresentation.quickPicks(map: map,
            catalogue: try catalogueWithPhoto(model), products: [product])
        XCTAssertEqual(picks.first?.imageKeys, ["canonical/test/milk.jpg", "canonical/test/dairy.jpg"])
        let backup = DastakGroceryHomePresentation.quickPicks(map: map,
            catalogue: try XCTUnwrap(model.v1Catalogue), products: [product])
        XCTAssertEqual(backup.first?.imageKeys, ["canonical/test/milk.jpg"])
        XCTAssertTrue(DastakGroceryHomePresentation.quickPicks(map: map,
            catalogue: try XCTUnwrap(model.v1Catalogue), products: model.v1BrowseProducts).isEmpty)
    }

    @MainActor
    func testApprovedPreviewPhotosIncludeSubcategoriesBeyondTheLoadedSKUPage() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true)
        let map = try XCTUnwrap(model.v1BrowseMap)
        let catalogue = try catalogueWithPhoto(model, preview: true)
        let picks = DastakGroceryHomePresentation.quickPicks(map: map, catalogue: catalogue, products: [])
        XCTAssertEqual(picks.first?.id, "dairy-breakfast")
        XCTAssertEqual(picks.first?.imageKeys, ["canonical/test/preview.jpg", "canonical/test/dairy.jpg"])
    }

    @MainActor
    func testSharedDepartmentArtworkCannotMasqueradeAsASubcategoryPhoto() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true)
        let catalogue = try catalogueWithPhoto(model)
        let object = try JSONEncoder().encode(catalogue)
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: object) as? [String: Any])
        var subcategories = try XCTUnwrap(dictionary["subcategories"] as? [[String: Any]])
        subcategories[0]["imageKey"] = "canonical/taxonomy/breakfast-instant.png"
        dictionary["subcategories"] = subcategories
        let shared = try JSONDecoder().decode(DastakV1CatalogueSnapshot.self,
            from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertTrue(DastakGroceryHomePresentation.quickPicks(map: try XCTUnwrap(model.v1BrowseMap),
            catalogue: shared, products: model.v1BrowseProducts).isEmpty)
    }

    @MainActor
    private func catalogueWithPhoto(_ model: DastakCustomerModel, preview: Bool = false) throws -> DastakV1CatalogueSnapshot {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(model.v1Catalogue))) as? [String: Any])
        var subcategories = try XCTUnwrap(object["subcategories"] as? [[String: Any]])
        subcategories[0]["imageKey"] = "canonical/test/dairy.jpg"
        if preview { subcategories[0]["previewImageKeys"] = ["canonical/test/preview.jpg"] }
        object["subcategories"] = subcategories
        return try JSONDecoder().decode(DastakV1CatalogueSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
