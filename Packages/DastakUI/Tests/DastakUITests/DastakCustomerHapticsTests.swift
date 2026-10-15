#if DEBUG
import XCTest
import MarketplaceDesignSystem
@testable import DastakUI

@MainActor
final class DastakCustomerHapticsTests: XCTestCase {
    func testGroceryPromptPickupAddRemoveAndNoOpEvents() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let product = try XCTUnwrap(model.knownCatalogueProducts.first)
        var events: [MarketplaceHapticEvent] = []
        model.hapticFeedback = { events.append($0) }
        model.addShoppingProduct(product)
        model.addShoppingProduct(product)
        XCTAssertEqual(events, [.warning, .warning])
        model.pickUpBasket(.grocery); model.pickUpBasket(.grocery)
        model.addShoppingProduct(product)
        model.decrementCartItem(product.id)
        model.decrementCartItem(product.id)
        XCTAssertEqual(events, [.warning, .warning, .basketPickup, .itemAdded, .itemRemoved])
        XCTAssertTrue(model.cart.isEmpty)
    }

    func testFoodFeedbackUsesFoodBasketAndQuantityLimitWarns() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let restaurant = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(restaurant.categories.first?.items.first)
        var events: [MarketplaceHapticEvent] = []
        model.hapticFeedback = { events.append($0) }
        model.addShoppingFood(restaurant: restaurant, item: dish, optionIDs: [])
        model.pickUpBasket(.food)
        model.addShoppingFood(restaurant: restaurant, item: dish, optionIDs: [])
        let entry = try XCTUnwrap(model.baskets[.food].foodEntries.first)
        model.incrementFoodCartItem(entry.id); model.decrementFoodCartItem(entry.id)
        XCTAssertEqual(events, [.warning, .basketPickup, .itemAdded, .itemAdded, .itemRemoved])
        events = []
        for _ in 1..<DastakCart.maximumQuantity { model.incrementFoodCartItem(entry.id) }
        model.incrementFoodCartItem(entry.id)
        XCTAssertEqual(events.last, .warning)
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        model.clearCart()
        XCTAssertEqual(events.last, .itemRemoved)
    }

    func testRefreshRestorationAndEmptyClearDoNotGenerateFeedback() async {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        var events: [MarketplaceHapticEvent] = []
        model.hapticFeedback = { events.append($0) }
        await model.refreshV1Catalogue()
        await model.refreshAreaAvailability(force: true)
        await model.restoreCartStorage()
        model.clearCart()
        XCTAssertTrue(events.isEmpty)
    }
}
#endif
