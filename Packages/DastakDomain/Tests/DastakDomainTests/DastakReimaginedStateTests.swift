import Foundation
import XCTest
@testable import DastakDomain

final class DastakReimaginedStateTests: XCTestCase {
    private let accountID = UUID()
    private let skuID = UUID()
    private let branchID = UUID()
    private let itemID = UUID()
    private let optionID = UUID()

    private var foodLine: DastakReimaginedFoodLine {
        .init(branchID: branchID, itemID: itemID, optionIDs: [optionID], quantity: 2)
    }

    private func signedIn() -> DastakReimaginedState {
        var state = DastakReimaginedState()
        state.send(.signedIn(accountID: accountID))
        return state
    }

    private func withShopping() -> DastakReimaginedState {
        var state = signedIn()
        state.send(.takeBucket)
        state.send(.setGroceryQuantity(skuID: skuID, quantity: 3))
        state.send(.selectService(.food))
        state.send(.setFoodQuantity(foodLine))
        return state
    }

    func testAuthenticationStartsAtGroceryEntrance() {
        XCTAssertEqual(DastakReimaginedState().environment, .outside)
        XCTAssertEqual(signedIn().environment, .groceryEntrance)
    }

    func testFoodCategoryFilterPreservesCanonicalReferencesAndShopping() {
        var state = withShopping()
        let shopping = state.shopping
        let filter = DastakReimaginedFoodCategoryFilter(label: "Meals", members: [.init(branchID: branchID, categoryID: UUID())])
        state.send(.selectFoodCategory(filter))
        XCTAssertEqual(state.food.foodCategoryFilter, filter)
        state.send(.selectService(.grocery))
        state.send(.selectFoodCategory(nil))
        XCTAssertEqual(state.food.foodCategoryFilter, filter)
        state.send(.selectService(.food))
        XCTAssertEqual(state.food.foodCategoryFilter, filter)
        state.send(.navigate(.home))
        XCTAssertNil(state.food.foodCategoryFilter)
        XCTAssertEqual(state.shopping, shopping)
    }

    func testCanonicalDestinationAndExplicitLocationState() {
        var state = signedIn()
        state.send(.openBrowseDestination("masalas"))
        state.send(.openLocation)
        XCTAssertTrue(state.locationOpen)
        state.send(.outsideInteraction)
        XCTAssertTrue(state.locationOpen)
        state.send(.closeLocation)
        XCTAssertFalse(state.locationOpen)
        state.send(.selectService(.food))
        state.send(.selectService(.grocery))
        XCTAssertEqual(state.grocery.view, .browse("masalas"))
    }

    func testExplicitBucketRequiredForExactSKU() {
        var state = signedIn()
        state.send(.setGroceryQuantity(skuID: skuID, quantity: 1))
        XCTAssertTrue(state.bucketPrompt)
        XCTAssertTrue(state.shopping.grocery.isEmpty)
        state.send(.takeBucket)
        state.send(.setGroceryQuantity(skuID: skuID, quantity: 1))
        XCTAssertEqual(state.shopping.grocery, [skuID: 1])
        XCTAssertFalse(state.bucketPrompt)
    }

    func testSwitchPreservesBothShoppingAndExploration() {
        var state = withShopping()
        state.send(.openRestaurant(branchID))
        state.send(.selectService(.grocery))
        let categoryID = UUID()
        state.send(.openCategory(categoryID))
        let shopping = state.shopping
        state.send(.selectService(.food))
        XCTAssertEqual(state.food.view, .restaurant(branchID))
        state.send(.selectService(.grocery))
        XCTAssertEqual(state.grocery.view, .category(categoryID))
        XCTAssertEqual(state.shopping, shopping)
    }

    func testHomeAndActiveServiceResetOnlyExploration() {
        var state = withShopping()
        let shopping = state.shopping
        state.send(.openRestaurant(branchID))
        state.send(.navigate(.home))
        XCTAssertEqual(state.food.view, .home)
        state.send(.selectService(.grocery))
        state.send(.openCategory(UUID()))
        state.send(.selectService(.grocery))
        XCTAssertEqual(state.grocery.view, .home)
        XCTAssertEqual(state.shopping, shopping)
        XCTAssertTrue(state.bucketAcquired)
    }

    func testTypingDoesNotAlterMainPanelUntilSubmit() {
        var state = signedIn()
        let categoryID = UUID()
        state.send(.openCategory(categoryID))
        state.send(.openDetail(skuID))
        state.send(.openSearch)
        state.send(.typeSearch("  milk  "))
        XCTAssertEqual(state.grocery.view, .category(categoryID))
        XCTAssertEqual(state.grocery.detailID, skuID)
        state.send(.submitSearch)
        XCTAssertEqual(state.grocery.view, .search("milk"))
        XCTAssertNil(state.grocery.detailID)
    }

    func testExplicitReviewReturnAndFailurePreserveShopping() {
        var state = withShopping()
        state.send(.selectService(.grocery))
        let shopping = state.shopping
        state.send(.reviewShopping)
        XCTAssertEqual(state.environment, .groceryCounter)
        let reviewing = state
        state.send(.checkoutFailed)
        XCTAssertEqual(state, reviewing)
        state.send(.continueShopping)
        XCTAssertEqual(state.environment, .groceryEntrance)
        XCTAssertEqual(state.shopping, shopping)
    }

    func testOutsideAndSoonInteractionsAreInert() {
        var state = withShopping()
        let original = state
        state.send(.outsideInteraction)
        state.send(.selectSoonService)
        XCTAssertEqual(state, original)
    }

    func testSuccessfulCheckoutConsumesOnlyItsServiceAndKeepsOrderVisible() {
        var state = withShopping()
        let orderID = UUID()
        state.send(.checkoutSucceeded(service: .food, orderID: orderID, purchased: state.shopping))
        XCTAssertEqual(state.shopping.grocery, [skuID: 3])
        XCTAssertTrue(state.shopping.food.isEmpty)
        XCTAssertEqual(state.environment, .foodEntrance)
        state.send(.selectService(.grocery))
        state.send(.navigate(.profile))
        XCTAssertEqual(state.activeOrder, .init(id: orderID, service: .food))
    }

    func testSignOutAndDifferentAccountsIsolateShopping() {
        var state = withShopping()
        state.send(.signedOut)
        XCTAssertEqual(state, DastakReimaginedState())
        state = withShopping()
        state.send(.signedIn(accountID: UUID()))
        XCTAssertEqual(state.shopping, .init())
        XCTAssertFalse(state.bucketAcquired)
    }

    func testLateCheckoutResponsePreservesNewItems() {
        var state = withShopping()
        let purchased = state.shopping
        var line = foodLine
        line.quantity = 4
        state.send(.setFoodQuantity(line))
        state.send(.checkoutSucceeded(service: .food, orderID: UUID(), purchased: purchased))
        XCTAssertEqual(state.shopping.food.first?.quantity, 2)
        XCTAssertEqual(state.shopping.grocery, purchased.grocery)
    }

    func testFoodOptionsAreDistinctAndEmptyCartReturnsToEntrance() {
        var state = withShopping()
        state.send(.setFoodQuantity(.init(branchID: branchID, itemID: itemID, optionIDs: [UUID()], quantity: 1)))
        XCTAssertEqual(state.shopping.food.count, 2)
        XCTAssertEqual(state.environment, .foodApproachingCounter)
        let lines = state.shopping.food
        for var line in lines {
            line.quantity = 0
            state.send(.setFoodQuantity(line))
        }
        XCTAssertEqual(state.environment, .foodEntrance)
        XCTAssertEqual(state.shopping.grocery, [skuID: 3])
    }

    func testRestoredShoppingAcquiresBucketAndSameSessionDoesNotReset() {
        var state = DastakReimaginedState()
        state.send(.signedIn(accountID: accountID, shopping: .init(grocery: [skuID: 2], food: [foodLine])))
        XCTAssertTrue(state.bucketAcquired)
        let restored = state
        state.send(.signedIn(accountID: accountID))
        XCTAssertEqual(state, restored)
    }

    func testNegativeQuantityRejectedAndProductTypeIsAFilter() {
        var state = signedIn()
        state.send(.takeBucket)
        let original = state
        state.send(.setGroceryQuantity(skuID: skuID, quantity: -1))
        XCTAssertEqual(state, original)
        let subcategoryID = UUID()
        let productTypeID = UUID()
        state.send(.setProductType(subcategoryID: subcategoryID, productTypeID: productTypeID))
        XCTAssertEqual(state.grocery.productTypeFilters, [subcategoryID: productTypeID])
        XCTAssertEqual(state.grocery.view, .home)
    }
}
