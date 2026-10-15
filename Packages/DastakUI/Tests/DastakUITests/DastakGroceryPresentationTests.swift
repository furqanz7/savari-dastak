import Foundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakGroceryPresentationTests: XCTestCase {
    func testShelfQuantityUsesExactAddedSizeAndReturnsToEmptyAfterRemoval() throws {
        let large = try sku(pack: "1 L", price: 5400)
        let small = try sku(pack: "200 ml", price: 1700)
        let family = try XCTUnwrap(DastakGroceryPresentation.families([large, small]).first)
        var cart = DastakCart()
        XCTAssertEqual(DastakGroceryPresentation.shelfBasketSelection(family, cart: cart).quantity, 0)
        _ = cart.add(small); _ = cart.add(small)
        var selected = DastakGroceryPresentation.shelfBasketSelection(family, cart: cart)
        XCTAssertEqual(selected.product.id, small.id)
        XCTAssertEqual(selected.product.sellingPricePaise, 1700)
        XCTAssertEqual(selected.quantity, 2)
        XCTAssertFalse(selected.hasMultipleSizes)
        cart.decrement(small.id)
        XCTAssertEqual(DastakGroceryPresentation.shelfBasketSelection(family, cart: cart).quantity, 1)
        cart.decrement(small.id)
        selected = DastakGroceryPresentation.shelfBasketSelection(family, cart: cart)
        XCTAssertEqual(selected.quantity, 0)
        XCTAssertEqual(selected.product.id, large.id)
    }

    func testShelfCombinesOnlySameFamilyAndRequiresSizeChoiceForMixedPacks() throws {
        let small = try sku(pack: "200 ml"), large = try sku(pack: "1 L")
        let other = try sku(name: "Farm eggs")
        let family = try XCTUnwrap(DastakGroceryPresentation.families([small, large, other]).first)
        var cart = DastakCart()
        _ = cart.add(small); _ = cart.add(large); _ = cart.add(large); _ = cart.add(other)
        let selected = DastakGroceryPresentation.shelfBasketSelection(family, cart: cart)
        XCTAssertEqual(selected.quantity, 3)
        XCTAssertTrue(selected.hasMultipleSizes)
    }
    func testSelectedSoldOutPackReplacesAddWithoutASeparateStockList() {
        XCTAssertEqual(DastakGroceryPresentation.purchaseTitle(stockQuantity: 0), "Out of stock")
        XCTAssertEqual(DastakGroceryPresentation.purchaseTitle(stockQuantity: 5), "ADD")
    }

    func testUnconfirmedStockDoesNotInventAnOutOfStockAction() {
        XCTAssertEqual(DastakGroceryPresentation.purchaseTitle(stockQuantity: nil), "ADD")
    }

    func testGroupedShelfStillOpensSizePickerWhenSoldOut() {
        XCTAssertEqual(DastakGroceryPresentation.purchaseTitle(stockQuantity: 0, chooseSize: true), "Choose size")
        XCTAssertEqual(DastakGroceryPresentation.purchaseTitle(stockQuantity: 5, chooseSize: true), "Choose size")
    }

    @MainActor
    func testChangingSelectedSizeChangesStockActionForExactSKU() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: true)
        let family = try XCTUnwrap(DastakGroceryPresentation.families(model.activeProducts).first)
        let smaller = try XCTUnwrap(family.packs.last)
        var deck = DastakGroceryPresentation.DetailDeck(initial: family.product, products: model.activeProducts)
        let quantities = [family.product.id: 0, smaller.id: 5]
        let initial = try XCTUnwrap(deck.selectedProduct(in: family.id))
        XCTAssertEqual(DastakGroceryPresentation.purchaseTitle(stockQuantity: quantities[initial.id]), "Out of stock")
        deck.selectPack(smaller.id, in: family.id)
        let selected = try XCTUnwrap(deck.selectedProduct(in: family.id))
        XCTAssertEqual(DastakGroceryPresentation.purchaseTitle(stockQuantity: quantities[selected.id]), "ADD")
        XCTAssertEqual(deck.selectedFamilyID, family.id)
        XCTAssertEqual(selected.price, smaller.price)
    }

    func testSearchIdentifiesSameNamePacksSeparately() throws {
        let small = try sku(pack: "500 ml", name: "Milk")
        let large = try sku(pack: "1 litre", name: "Milk")
        XCTAssertEqual(DastakGroceryPresentation.searchPackDescription(small), "500 ml")
        XCTAssertEqual(DastakGroceryPresentation.searchAccessibilityIdentity(small), "Milk, 500 ml")
        XCTAssertEqual(DastakGroceryPresentation.searchAccessibilityIdentity(large), "Milk, 1 litre")
        XCTAssertNotEqual(DastakGroceryPresentation.searchAccessibilityIdentity(small),
                          DastakGroceryPresentation.searchAccessibilityIdentity(large))
    }

    func testSearchIdentityIncludesVariantAndTrimsBlankMetadata() throws {
        let chocolate = try sku(pack: " 500 ml ", variant: " Chocolate ", name: "Milk")
        XCTAssertEqual(DastakGroceryPresentation.searchPackDescription(chocolate), "Chocolate · 500 ml")
        XCTAssertEqual(DastakGroceryPresentation.searchAccessibilityIdentity(chocolate), "Milk, Chocolate · 500 ml")
        let plain = try sku(pack: "500 ml", variant: " \n ", name: "Milk")
        XCTAssertEqual(DastakGroceryPresentation.searchPackDescription(plain), "500 ml")
        let missing = try sku(pack: " ", name: "Milk")
        XCTAssertEqual(DastakGroceryPresentation.searchPackDescription(missing), "")
        XCTAssertEqual(DastakGroceryPresentation.searchAccessibilityIdentity(missing), "Milk")
    }

    @MainActor
    func testDebugPanelFixturesExercisePacksAndClosedRestaurantsWithoutLiveRequests() throws {
        let model = DastakCustomerModel.preview(panelFixtures: true)
        let families = DastakGroceryPresentation.families(model.activeProducts)
        XCTAssertEqual(families.first?.packs.count, 2)
        XCTAssertEqual(model.v1Restaurants.count, 2)
        XCTAssertNil(model.restaurantIssue(try XCTUnwrap(model.v1Restaurants.first)))
        XCTAssertEqual(model.restaurantIssue(try XCTUnwrap(model.v1Restaurants.last)), "Store closed")
        XCTAssertEqual(model.v1Restaurants.first?.categories.first?.items.count, 1)
    }

    private func sku(_ id: UUID = UUID(), pack: String = "500 ml", brand: String? = "Amul",
                     variant: String? = nil, category: UUID? = nil, subcategory: UUID? = nil,
                     price: Int = 2800, name: String? = nil) throws -> DastakV1CatalogueSKU {
        let fixed = "11111111-1111-4111-8111-111111111111"
        var object: [String: Any] = ["id": id.uuidString, "categoryId": category?.uuidString ?? fixed,
            "subcategoryId": subcategory?.uuidString ?? fixed, "name": name ?? "Amul Milk \(pack)",
            "slug": "milk", "packSize": pack, "listPricePaise": price, "sellingPricePaise": price,
            "currencyCode": "INR", "logisticsAttributes": [:]]
        if let brand { object["brand"] = ["id": fixed, "name": brand, "slug": "brand"] }
        if let variant { object["variant"] = variant }
        return try JSONDecoder().decode(DastakV1CatalogueSKU.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testPackCardsCollapseWithoutLosingExactSKUPriceOrOrder() throws {
        let small = try sku(), large = try sku(pack: "1 L", price: 5400)
        let groups = DastakGroceryPresentation.families([small, large, small])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, small.id)
        XCTAssertEqual(groups[0].packs.map(\.id), [small.id, large.id])
        XCTAssertEqual(groups[0].packs.map(\.sellingPricePaise), [2800, 5400])
        XCTAssertTrue(DastakDetailProduct(small).sameFamily(as: DastakDetailProduct(large)))
    }

    func testDetailDeckHasOnePagePerFamilyAndOpensRequestedPack() throws {
        let small = try sku(pack: "200 ml", price: 1700), large = try sku(pack: "1 L", price: 5400)
        let eggs = try sku(pack: "6 pieces", name: "Farm eggs")
        let deck = DastakGroceryPresentation.DetailDeck(initial: large, products: [small, large, eggs, small])
        XCTAssertEqual(deck.families.map(\.id), [small.id, eggs.id])
        XCTAssertEqual(deck.families[0].packs.map(\.id), [small.id, large.id])
        XCTAssertEqual(deck.selectedFamilyID, small.id)
        XCTAssertEqual(deck.selectedProduct(in: small.id)?.id, large.id)
        XCTAssertEqual(deck.selectedProduct(in: small.id)?.sellingPricePaise, 5400)
    }

    func testSelectingSizeKeepsPageAndExactPriceAndRemembersItWhenReturning() throws {
        let small = try sku(pack: "200 ml", price: 1700), large = try sku(pack: "1 L", price: 5400)
        let eggs = try sku(pack: "6 pieces", name: "Farm eggs")
        var deck = DastakGroceryPresentation.DetailDeck(initial: large, products: [large, small, eggs])
        deck.selectPack(small.id, in: large.id)
        XCTAssertEqual(deck.selectedFamilyID, large.id)
        XCTAssertEqual(deck.selectedProduct(in: large.id)?.id, small.id)
        XCTAssertEqual(deck.selectedProduct(in: large.id)?.sellingPricePaise, 1700)
        deck.selectPack(eggs.id, in: large.id)
        XCTAssertEqual(deck.selectedProduct(in: large.id)?.id, small.id)
        deck.selectedFamilyID = eggs.id
        deck.selectedFamilyID = large.id
        XCTAssertEqual(deck.selectedProduct(in: large.id)?.id, small.id)
        XCTAssertEqual(deck.families.count, 2)
    }

    func testDetailDeckIncludesMissingInitialPackAndKeepsTaxonomyBoundaries() throws {
        let initial = try sku(), otherCategory = try sku(category: UUID())
        let deck = DastakGroceryPresentation.DetailDeck(initial: initial, products: [otherCategory])
        XCTAssertEqual(deck.families.map(\.id), [initial.id])
        XCTAssertEqual(deck.selectedProduct(in: initial.id)?.id, initial.id)
        XCTAssertNil(deck.selectedProduct(in: UUID()))
    }

    func testBrandVariantAndTaxonomyBoundariesAreNeverPackOptions() throws {
        let base = try sku()
        for other in [try sku(brand: "Other"), try sku(variant: "Chocolate"),
                      try sku(category: UUID()), try sku(subcategory: UUID()), try sku(name: "Other milk")] {
            XCTAssertEqual(DastakGroceryPresentation.families([base, other]).count, 2)
            XCTAssertFalse(DastakDetailProduct(base).sameFamily(as: DastakDetailProduct(other)))
        }
    }

    func testUnbrandedAndBlankBrandProductsRemainExactSeparateSKUs() throws {
        for brand: String? in [nil, "", " "] {
            let first = try sku(brand: brand), second = try sku(pack: "1 L", brand: brand)
            XCTAssertEqual(DastakGroceryPresentation.families([first, second, first]).count, 2)
            XCTAssertFalse(DastakDetailProduct(first).sameFamily(as: DastakDetailProduct(second)))
            XCTAssertTrue(DastakDetailProduct(first).sameFamily(as: DastakDetailProduct(first)))
        }
    }

    func testSearchResultOrderingAndEmptyInputRemainUnchanged() throws {
        XCTAssertTrue(DastakGroceryPresentation.families([]).isEmpty)
        let large = try sku(pack: "1 L"), small = try sku(), eggs = try sku(name: "Eggs")
        let groups = DastakGroceryPresentation.families([large, eggs, small])
        XCTAssertEqual(groups.map(\.id), [large.id, eggs.id])
        XCTAssertEqual(groups[0].packs.map(\.id), [large.id, small.id])
    }

    func testEmptyNormalizedNamesCannotInventAFamily() throws {
        let first = try sku(name: "500 ml"), other = try sku(pack: "1 L", name: "1 L")
        XCTAssertEqual(DastakGroceryPresentation.families([first, other]).count, 2)
        XCTAssertFalse(DastakDetailProduct(first).sameFamily(as: DastakDetailProduct(other)))
    }
}
