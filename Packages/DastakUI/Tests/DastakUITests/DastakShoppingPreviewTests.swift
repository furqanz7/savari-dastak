#if DEBUG
import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakShoppingPreviewTests: XCTestCase {
    func testPreviewReadsResolveProductsDishesAndUnresolvedEntry() async {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        await model.refreshWishlist()
        await model.resolveWishlistContents()
        XCTAssertEqual(model.wishlistRetailProducts.count, 1)
        XCTAssertEqual(model.wishlistMenuSelections.count, 1)
        XCTAssertEqual(model.unresolvedWishlistItemCount, 1)
        XCTAssertNil(model.wishlistRefreshFailure)
        XCTAssertNil(model.savedItemsRefreshFailure)
        XCTAssertTrue(model.cart.isEmpty)
    }

    func testPreviewUnresolvedRemovalIsInMemoryAndSurvivesSnapshotRefresh() async throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        await model.refreshWishlist()
        let missing = try XCTUnwrap(model.unresolvedWishlistItems.first)
        await model.removeWishlistItem(kind: missing.kind, itemID: missing.itemID)
        await model.refreshWishlist()
        XCTAssertEqual(model.wishlistItems.count, 2)
        XCTAssertEqual(model.unresolvedWishlistItemCount, 0)
        XCTAssertTrue(model.cart.isEmpty)
    }

    func testPreviewSearchResultsEmptyAndOfflineRetry() async {
        let model = DastakCustomerModel.preview(shoppingFixtures: true)
        model.searchText = "milk"
        await model.searchV1Catalogue()
        XCTAssertEqual(model.v1SearchResults.map(\.name), ["Fresh whole milk"])
        model.searchText = "no sample matches"
        await model.searchV1Catalogue()
        XCTAssertTrue(model.v1SearchResults.isEmpty)
        XCTAssertNil(model.v1SearchRefreshFailure)
        model.searchText = "offline"
        await model.searchV1Catalogue()
        XCTAssertEqual(model.v1SearchRefreshFailure, .offline)
        model.searchText = "eggs"
        await model.searchV1Catalogue()
        XCTAssertEqual(model.v1SearchResults.map(\.name), ["Farm eggs"])
        XCTAssertNil(model.v1SearchRefreshFailure)
    }

    func testPreviewHistoryAndReorderOnlyRebuildBasket() async throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        await model.refreshOrdersAndParcels()
        XCTAssertEqual(model.v1Orders.count, 2)
        XCTAssertNil(model.ordersAndParcelsRefreshFailure)
        let order = try XCTUnwrap(model.v1Orders.first { $0.displayOrderNumber == "SAMPLE-GROCERY" })
        let review = try XCTUnwrap(model.reviewReorder(order))
        let result = await model.reorderWithCurrentCatalogue(review)
        XCTAssertTrue(result.openedBasket)
        XCTAssertEqual(model.cart.itemCount, 1)
        XCTAssertNil(model.activeV1Order)
        XCTAssertNil(model.pendingCheckout)
    }

    func testFixtureRejectsEveryNonAllowlistedMutationAndWrongEndpoint() async {
        struct Request: Encodable, Sendable { let operation: String }
        struct Response: Decodable, Sendable { }
        let client = DastakShoppingPreviewClient()
        for (name, operation) in [("dastak-v1-orders", "submit"), ("dastak-v1-orders", "confirm"),
                                  ("customer-addresses", "save"), ("account-profile", "update"),
                                  ("payments", "charge"), ("unknown", "snapshot"), ("unknown", "set")] {
            do {
                let _: Response = try await client.invoke(name, request: Request(operation: operation), idempotencyKey: IdempotencyKey(rawValue: "preview-safety-test")!)
                XCTFail("Unexpectedly accepted \(name)/\(operation)")
            } catch { XCTAssertTrue(error is FunctionClientError) }
        }
    }

    func testMixedSampleReorderReviewPreservesBothBasketsUntilChosenReplacement() async throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let milk = try XCTUnwrap(model.knownCatalogueProducts.first { $0.packSize == "1 litre" })
        let menu = try XCTUnwrap(model.v1Restaurants.first)
        let dish = try XCTUnwrap(menu.categories.first?.items.first)
        for _ in 0..<2 {
            model.addToCart(milk)
            model.addFoodToCart(restaurant: menu, item: dish, optionIDs: [])
        }
        model.cartService = .grocery
        await model.refreshOrdersAndParcels()
        let mixed = try XCTUnwrap(model.v1Orders.first { $0.displayOrderNumber == "SAMPLE-MIXED" })
        let original = model.baskets
        XCTAssertEqual(original[.grocery].subtotal.paise, 13600)
        XCTAssertEqual(original[.food].subtotal.paise, 24000)
        XCTAssertNil(model.reviewReorder(mixed)) // Explicit service choice required.
        for service in DastakBasketService.allCases {
            let review = try XCTUnwrap(model.reviewReorder(mixed, service: service))
            XCTAssertTrue(review.requiresReplacement)
            XCTAssertEqual(model.baskets, original) // Reviewing/dismissing cannot commit.
        }
        let groceryReview = try XCTUnwrap(model.reviewReorder(mixed, service: .grocery))
        let groceryResult = await model.reorderWithCurrentCatalogue(groceryReview)
        XCTAssertTrue(groceryResult.openedBasket)
        XCTAssertEqual(model.baskets[.grocery].subtotal.paise, 6800)
        XCTAssertEqual(model.baskets[.food], original[.food])
        let grocery = model.baskets[.grocery]
        let foodReview = try XCTUnwrap(model.reviewReorder(mixed, service: .food))
        let foodResult = await model.reorderWithCurrentCatalogue(foodReview)
        XCTAssertTrue(foodResult.openedBasket)
        XCTAssertEqual(model.baskets[.food].subtotal.paise, 12000)
        XCTAssertEqual(model.baskets[.grocery], grocery)
        XCTAssertNil(model.pendingCheckout)
        XCTAssertNil(model.activeV1Order)
    }
}
#endif
