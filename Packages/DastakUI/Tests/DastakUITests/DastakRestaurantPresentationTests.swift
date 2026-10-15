import XCTest
import MarketplaceInfrastructure
@testable import DastakUI

final class DastakRestaurantPresentationTests: XCTestCase {
    private func categories() throws -> [DastakV1RestaurantMenuCategory] {
        try JSONDecoder().decode([DastakV1RestaurantMenuCategory].self, from: Data("""
        [{"id":"11111111-1111-4111-8111-111111111111","name":"Hot drinks","sortOrder":1,"status":"ACTIVE","version":1,"items":[]},
         {"id":"22222222-2222-4222-8222-222222222222","name":"Cold drinks","sortOrder":2,"status":"ACTIVE","version":1,"items":[]}]
        """.utf8))
    }

    func testCategoryJumpResolvesRequestedSectionWithoutFilteringMenu() throws {
        let categories = try categories()
        XCTAssertEqual(DastakRestaurantPresentation.menuCategoryScrollTarget(categories, categoryID: categories[1].id), categories[1].id)
        XCTAssertEqual(categories.map(\.name), ["Hot drinks", "Cold drinks"])
    }

    func testRepeatedCategoryJumpKeepsResolvingSameSection() throws {
        let categories = try categories()
        for _ in 0..<3 {
            XCTAssertEqual(DastakRestaurantPresentation.menuCategoryScrollTarget(categories, categoryID: categories[0].id), categories[0].id)
        }
    }

    func testStaleCategorySelectionAndEmptyMenuRemainSafe() throws {
        let categories = try categories()
        XCTAssertNil(DastakRestaurantPresentation.menuCategoryScrollTarget(categories, categoryID: UUID()))
        XCTAssertNil(DastakRestaurantPresentation.menuCategoryScrollTarget([], categoryID: UUID()))
    }

    func testCustomerFacingNameWinsEvenWhenOrganizationNameDiffers() {
        for name in ["Craft", "Internal Business", "Registered Foods Pvt Ltd"] {
            XCTAssertEqual(DastakRestaurantPresentation.customerFacingName(name: name, branchName: " Craft \n"), "Craft")
        }
    }

    func testMissingStorefrontNameFallsBackLikeWeb() {
        for branch in ["", " \n "] {
            XCTAssertEqual(DastakRestaurantPresentation.customerFacingName(name: "Craft", branchName: branch), "Craft")
        }
    }

    func testAccessibilityUsesOneCustomerNameAndRetainsClosedStatus() {
        XCTAssertEqual(DastakRestaurantPresentation.accessibilityLabel(name: "Craft", branchName: "Craft", status: "Accepting orders"), "Craft, Accepting orders")
        XCTAssertEqual(DastakRestaurantPresentation.accessibilityLabel(name: "Internal Business", branchName: "Craft", status: "Store closed"), "Craft, Store closed")
    }

    @MainActor
    func testFoodBasketUsesCustomerFacingNameWithoutChangingRestaurantIdentity() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let item = try XCTUnwrap(menu.categories.first?.items.first)
        var cart = DastakCart()
        XCTAssertEqual(cart.addFood(restaurant: menu.restaurant, item: item, optionIDs: []), .added)
        let entry = try XCTUnwrap(cart.foodEntries.first)
        XCTAssertEqual(entry.restaurantName, "Sample branch")
        XCTAssertEqual(entry.restaurantBranchID, menu.restaurant.branchID)
        XCTAssertEqual(entry.item.id, item.id)
        XCTAssertEqual(entry.unitPricePaise, item.basePricePaise)
    }
}
