#if DEBUG
import XCTest
import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakBasketEditingTests: XCTestCase {
    func testActiveOrderHidesBothEmptyPickedUpBasketDocks() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        for service in [DastakBasketService.grocery, .food] {
            XCTAssertFalse(model.showsBasketDock(service))
            model.pickUpBasket(service)
            XCTAssertTrue(model.showsBasketDock(service))
        }
        // History has not refreshed yet; the authoritative focused snapshot must suffice.
        XCTAssertTrue(model.v1Orders.isEmpty)
        for status in [DastakV1OrderStatus.created, .matching, .fullySecured, .awaitingPayment,
                       .paid, .preparing, .pickupInProgress, .outForDelivery] {
            model.focusV1Order(try basketDockOrder(status))
            XCTAssertFalse(model.showsBasketDock(.grocery), status.rawValue)
            XCTAssertFalse(model.showsBasketDock(.food), status.rawValue)
        }
    }

    func testTerminalOrderRestoresDocksWithoutLosingEitherBasket() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        model.addToCart(try XCTUnwrap(model.knownCatalogueProducts.first))
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(menu.categories.first?.items.first)
        model.addFoodToCart(restaurant: menu, item: dish, optionIDs: [])
        let baskets = model.baskets
        model.focusV1Order(try basketDockOrder(.outForDelivery))
        XCTAssertFalse(model.showsBasketDock(.grocery))
        XCTAssertFalse(model.showsBasketDock(.food))
        XCTAssertEqual(model.baskets, baskets)
        for status in [DastakV1OrderStatus.delivered, .unavailable, .paymentExpired,
                       .cancelledPrepayment, .cancelled, .fulfilmentFailure] {
            model.focusV1Order(try basketDockOrder(status))
            XCTAssertTrue(model.showsBasketDock(.grocery), status.rawValue)
            XCTAssertTrue(model.showsBasketDock(.food), status.rawValue)
            XCTAssertEqual(model.baskets, baskets)
        }
    }

    private func basketDockOrder(_ status: DastakV1OrderStatus) throws -> DastakV1OrderSnapshot {
        try JSONDecoder().decode(DastakV1OrderSnapshot.self, from: Data("""
        {"id":"11111111-1111-4111-8111-111111111111",
         "displayOrderNumber":"DOCK-TEST","orderType":"RETAIL_ONLY",
         "status":"\(status.rawValue)","version":1,
         "price":{"snapshotKind":"FINAL_PAYABLE","subtotalPaise":10000,
           "deliveryFeePaise":0,"platformFeePaise":200,"discountPaise":0,
           "taxPaise":0,"totalPaise":10200,"currencyCode":"INR"},
         "lines":[],"createdAt":"2026-10-15T09:00:00Z","updatedAt":"2026-10-15T09:00:00Z"}
        """.utf8))
    }

    func testShoppingRequiresPickupAndDoesNotAutoAddPromptedProduct() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first)
        XCTAssertFalse(model.hasGroceryBasket)
        model.addShoppingProduct(milk)
        XCTAssertTrue(model.groceryBasketPrompt)
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        model.pickUpGroceryBasket()
        XCTAssertTrue(model.hasGroceryBasket)
        XCTAssertFalse(model.groceryBasketPrompt)
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        model.addShoppingProduct(milk)
        XCTAssertEqual(model.baskets[.grocery].itemCount, 1)
        model.clearCart()
        XCTAssertTrue(model.hasGroceryBasket)
    }

    func testExistingGroceryBasketAlreadyCountsAsPickedUp() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first)
        model.addToCart(milk) // Existing/recovered/reordered contents must stay usable.
        XCTAssertTrue(model.hasGroceryBasket)
        model.addShoppingProduct(milk)
        XCTAssertEqual(model.baskets[.grocery].itemCount, 2)
        XCTAssertFalse(model.groceryBasketPrompt)
        model.clearCart()
        XCTAssertTrue(model.hasGroceryBasket)
    }

    func testFoodRequiresItsOwnPickupWithoutAutoAddingOrPickingUpGrocery() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(menu.categories.first?.items.first)
        model.addShoppingFood(restaurant: menu, item: dish, optionIDs: [])
        XCTAssertTrue(model.baskets[.food].isEmpty)
        XCTAssertEqual(model.basketPrompt?.service, .food)
        model.pickUpBasket(.food)
        XCTAssertTrue(model.hasBasket(.food))
        XCTAssertTrue(model.baskets[.food].isEmpty)
        XCTAssertNil(model.basketPrompt)
        XCTAssertNil(model.basketFlight?.productID)
        model.addShoppingFood(restaurant: menu, item: dish, optionIDs: [])
        XCTAssertEqual(model.baskets[.food].itemCount, 1)
        XCTAssertEqual(model.basketFlight?.productID, dish.id)
        XCTAssertEqual(model.basketFlight?.service, .food)
        XCTAssertFalse(model.hasGroceryBasket)
        XCTAssertFalse(model.groceryBasketPrompt)
    }

    func testEveryBlockedAttemptRestartsFiveSecondNoticeAndOlderExpiryCannotDismissIt() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first)
        let start = Date()
        model.addShoppingProduct(milk)
        let first = try XCTUnwrap(model.basketPrompt)
        XCTAssertEqual(first.expiresAt.timeIntervalSince(start), 5, accuracy: 0.1)
        model.expireBasketPrompt(id: first.id, now: first.expiresAt.addingTimeInterval(-0.01))
        XCTAssertEqual(model.basketPrompt?.id, first.id)
        model.addShoppingProduct(milk)
        let second = try XCTUnwrap(model.basketPrompt)
        XCTAssertNotEqual(first.id, second.id)
        model.expireBasketPrompt(id: first.id, now: second.expiresAt)
        XCTAssertEqual(model.basketPrompt?.id, second.id)
        model.expireBasketPrompt(id: second.id, now: second.expiresAt)
        XCTAssertNil(model.basketPrompt)
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        model.addShoppingProduct(milk)
        XCTAssertNotNil(model.basketPrompt)
    }

    func testEachSuccessfulAddEmitsExactProductAndRejectedAddDoesNotFly() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first)
        model.pickUpBasket(.grocery)
        let pickup = model.basketFlight?.id
        model.addShoppingProduct(milk)
        XCTAssertNotEqual(model.basketFlight?.id, pickup)
        XCTAssertEqual(model.basketFlight?.productID, milk.id)
        XCTAssertEqual(model.basketFlight?.imageKey, milk.imageKey)
        let first = model.basketFlight?.id
        model.addShoppingProduct(milk)
        XCTAssertNotEqual(model.basketFlight?.id, first)
        for _ in 0..<DastakCart.maximumQuantity { model.addShoppingProduct(milk) }
        let last = model.basketFlight?.id
        model.addShoppingProduct(milk)
        XCTAssertEqual(model.basketFlight?.id, last)
        XCTAssertEqual(model.baskets[.grocery].itemCount, DastakCart.maximumQuantity)
    }

    func testDetailCartRouteRetainsRequestedService() {
        var requested: [DastakBasketService] = []
        let open = DastakOpenCartAction { requested.append($0) }
        open(.grocery)
        open(.food)
        XCTAssertEqual(requested, [.grocery, .food])
    }

    func testGroceryQuantityAndLastUnitRemovalPreserveFood() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first { $0.packSize == "1 litre" })
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(menu.categories.first?.items.first)
        model.addFoodToCart(restaurant: menu, item: dish, optionIDs: [])
        let food = model.baskets[.food]
        model.addToCart(milk)
        model.addToCart(milk)
        XCTAssertEqual(model.baskets[.grocery].itemCount, 2)
        XCTAssertEqual(model.baskets[.grocery].subtotal.paise, 13600)
        model.decrementCartItem(milk.id)
        XCTAssertEqual(model.baskets[.grocery].itemCount, 1)
        XCTAssertEqual(model.baskets[.grocery].subtotal.paise, 6800)
        model.decrementCartItem(milk.id)
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        XCTAssertEqual(model.baskets[.food], food)
        XCTAssertNil(model.pendingCheckout)
        XCTAssertNil(model.activeV1Order)
    }

    func testFoodQuantityAndLastUnitRemovalPreserveGrocery() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first { $0.packSize == "1 litre" })
        model.addToCart(milk)
        let grocery = model.baskets[.grocery]
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(menu.categories.first?.items.first)
        model.addFoodToCart(restaurant: menu, item: dish, optionIDs: [])
        let id = try XCTUnwrap(model.baskets[.food].foodEntries.first?.id)
        model.incrementFoodCartItem(id)
        XCTAssertEqual(model.baskets[.food].itemCount, 2)
        XCTAssertEqual(model.baskets[.food].subtotal.paise, 24000)
        model.decrementFoodCartItem(id)
        XCTAssertEqual(model.baskets[.food].subtotal.paise, 12000)
        model.decrementFoodCartItem(id)
        XCTAssertTrue(model.baskets[.food].isEmpty)
        XCTAssertEqual(model.baskets[.grocery], grocery)
    }

    func testPackSelectionUsesExactSKUWithoutSilentReplacement() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let large = try XCTUnwrap(model.knownCatalogueProducts.first { $0.packSize == "1 litre" })
        let small = try XCTUnwrap(model.knownCatalogueProducts.first { $0.packSize == "500 ml" })
        XCTAssertTrue(DastakGroceryPresentation.sameFamily(large, small))
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(menu.categories.first?.items.first)
        model.addFoodToCart(restaurant: menu, item: dish, optionIDs: [])
        let food = model.baskets[.food]
        model.addToCart(large)
        model.addToCart(small)
        XCTAssertEqual(model.cart.entries.map(\.id), [large.id, small.id])
        XCTAssertEqual(model.cart.subtotal.paise, 10300)
        model.decrementCartItem(large.id)
        XCTAssertEqual(model.cart.orderLines.map(\.skuID), [small.id])
        XCTAssertEqual(model.cart.entries.first?.product.packSize, "500 ml")
        XCTAssertEqual(model.cart.subtotal.paise, 3500)
        XCTAssertEqual(model.baskets[.food], food)
    }

    func testQuantityLimitsAndDecrementRecoveryStayServiceScoped() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first { $0.packSize == "1 litre" })
        for _ in 0..<DastakCart.maximumQuantity { model.addToCart(milk) }
        let grocery = model.baskets[.grocery]
        model.addToCart(milk)
        XCTAssertEqual(model.baskets[.grocery], grocery)
        XCTAssertNotNil(model.cartErrorMessage)
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(menu.categories.first?.items.first)
        model.addFoodToCart(restaurant: menu, item: dish, optionIDs: [])
        let id = try XCTUnwrap(model.cart.foodEntries.first?.id)
        for _ in 1..<DastakCart.maximumQuantity { model.incrementFoodCartItem(id) }
        let food = model.baskets[.food]
        model.incrementFoodCartItem(id)
        XCTAssertEqual(model.baskets[.food], food)
        XCTAssertNotNil(model.cartErrorMessage)
        model.decrementFoodCartItem(id)
        XCTAssertEqual(model.baskets[.food].itemCount, 98)
        XCTAssertNil(model.cartErrorMessage)
        XCTAssertEqual(model.baskets[.grocery], grocery)
    }

    func testMinusPublishesBasketChangesAfterSwitchingServices() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first { $0.packSize == "1 litre" })
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(menu.categories.first?.items.first)
        model.addToCart(milk)
        model.addToCart(milk)
        model.addFoodToCart(restaurant: menu, item: dish, optionIDs: [])
        let foodID = try XCTUnwrap(model.baskets[.food].foodEntries.first?.id)
        model.incrementFoodCartItem(foodID)

        var changes: [DastakCustomerBaskets] = []
        let observation = model.$baskets.dropFirst().sink { changes.append($0) }
        defer { observation.cancel() }
        model.cartService = .grocery
        XCTAssertTrue(model.canEditCurrentCart)
        model.decrementCartItem(milk.id)
        model.decrementCartItem(milk.id)
        model.cartService = .food
        XCTAssertTrue(model.canEditCurrentCart)
        model.decrementFoodCartItem(foodID)
        model.decrementFoodCartItem(foodID)

        XCTAssertEqual(changes.map { $0[.grocery].itemCount }, [1, 0, 0, 0])
        XCTAssertEqual(changes.map { $0[.food].itemCount }, [2, 2, 1, 0])
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        XCTAssertTrue(model.baskets[.food].isEmpty)
        XCTAssertNil(model.pendingCheckout)
        XCTAssertNil(model.activeV1Order)
    }
}
#endif
