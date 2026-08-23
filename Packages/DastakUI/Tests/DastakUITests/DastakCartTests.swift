import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakCartTests: XCTestCase {
    func testCanonicalCartAggregatesQuantityAndAuthoritativeSubtotal() throws {
        var cart = DastakCart()
        let product = try fixtureProduct(
            productID: "11111111-1111-4111-8111-111111111111",
            pricePaise: 12_500
        )

        XCTAssertEqual(cart.add(product), .added)
        XCTAssertEqual(cart.add(product), .added)
        XCTAssertEqual(cart.itemCount, 2)
        XCTAssertEqual(cart.subtotal, Money(paise: 25_000))
        XCTAssertEqual(cart.orderLines, [
            DastakV1OrderLineInput(skuID: product.id, quantity: 2)
        ])
    }

    func testCanonicalCartAllowsMixedSKUsWithoutMerchantStoreIdentity() throws {
        var cart = DastakCart()
        let first = try fixtureProduct(
            productID: "11111111-1111-4111-8111-111111111111"
        )
        let second = try fixtureProduct(
            productID: "33333333-3333-4333-8333-333333333333"
        )

        XCTAssertEqual(cart.add(first), .added)
        XCTAssertEqual(cart.add(second), .added)
        XCTAssertEqual(cart.entries.map(\.product.id), [first.id, second.id])
    }

    func testCanonicalCartCapsOneSKUQuantity() throws {
        var cart = DastakCart()
        let product = try fixtureProduct(
            productID: "11111111-1111-4111-8111-111111111111"
        )

        for _ in 0..<DastakCart.maximumQuantity {
            XCTAssertEqual(cart.add(product), .added)
        }
        XCTAssertEqual(cart.add(product), .quantityLimit)
        XCTAssertEqual(cart.itemCount, DastakCart.maximumQuantity)
    }

    func testMixedFoodAndRetailCartKeepsOneParentSubmissionAndServerIdentities() throws {
        var cart = DastakCart()
        let product = try fixtureProduct(productID: "11111111-1111-4111-8111-111111111111", pricePaise: 10_000)
        let restaurant = try fixtureRestaurant(branchID: "77777777-7777-4777-8777-777777777777")
        let item = try XCTUnwrap(restaurant.categories.first?.items.first)
        let option = try XCTUnwrap(item.optionGroups.first?.options.first)

        XCTAssertEqual(cart.add(product), .added)
        XCTAssertEqual(cart.addFood(restaurant: restaurant.restaurant, item: item, optionIDs: [option.id]), .added)
        XCTAssertEqual(cart.itemCount, 2)
        XCTAssertEqual(cart.subtotal, Money(paise: 15_000))
        XCTAssertEqual(cart.restaurantBranchID, restaurant.restaurant.branchID)
        XCTAssertEqual(cart.orderLines.map(\.lineType), ["RETAIL_SKU", "FOOD_MENU_ITEM"])
    }

    func testFoodCartRejectsASecondRestaurantWithoutMerging() throws {
        var cart = DastakCart()
        let first = try fixtureRestaurant(branchID: "77777777-7777-4777-8777-777777777777")
        let second = try fixtureRestaurant(branchID: "88888888-8888-4888-8888-888888888888")
        let firstItem = try XCTUnwrap(first.categories.first?.items.first)
        let secondItem = try XCTUnwrap(second.categories.first?.items.first)

        XCTAssertEqual(cart.addFood(restaurant: first.restaurant, item: firstItem, optionIDs: []), .added)
        XCTAssertEqual(cart.addFood(restaurant: second.restaurant, item: secondItem, optionIDs: []), .differentRestaurant)
        XCTAssertEqual(cart.foodEntries.count, 1)
        XCTAssertEqual(cart.restaurantBranchID, first.restaurant.branchID)
    }

    private func fixtureProduct(
        productID: String,
        pricePaise: Int = 10_000
    ) throws -> DastakV1CatalogueSKU {
        let json = """
        {
          "id":"\(productID)",
          "categoryId":"55555555-5555-4555-8555-555555555555",
          "subcategoryId":"66666666-6666-4666-8666-666666666666",
          "brand":null,
          "name":"Market item",
          "slug":"market-item-\(productID.prefix(4))",
          "variant":null,
          "packSize":"1 unit",
          "description":"Freshly stocked",
          "imageKey":null,
          "barcode":null,
          "listPricePaise":\(pricePaise),
          "sellingPricePaise":\(pricePaise),
          "currencyCode":"INR",
          "logisticsAttributes":{}
        }
        """
        return try JSONDecoder().decode(DastakV1CatalogueSKU.self, from: Data(json.utf8))
    }

    private func fixtureRestaurant(branchID: String) throws -> DastakV1RestaurantMenu {
        let json = """
        {
          "restaurant":{
            "organizationId":"99999999-9999-4999-8999-999999999999",
            "branchId":"\(branchID)","name":"Dastak Cafe","branchName":"Main Road",
            "imageKey":null,"description":null,"serviceZoneId":null,
            "acceptingOrders":true,"isOpen":true,"branchStatus":"ACTIVE",
            "merchantType":"RESTAURANT_CAFE","softActiveOrderThreshold":5,"activeOrderCount":0
          },
          "categories":[{
            "id":"55555555-5555-4555-8555-555555555555","name":"Drinks",
            "description":null,"sortOrder":1,"status":"ACTIVE","version":1,
            "items":[{
              "id":"66666666-6666-4666-8666-666666666666","name":"Coffee",
              "description":null,"imageKey":null,"basePricePaise":4500,
              "currencyCode":"INR","taxRateBps":0,"logisticsAttributes":{},
              "status":"ACTIVE","version":1,"optionGroups":[{
                "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Size",
                "selectionType":"SINGLE","minimumSelections":0,"maximumSelections":1,
                "sortOrder":1,"status":"ACTIVE","version":1,"options":[{
                  "id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","name":"Large",
                  "priceDeltaPaise":500,"sortOrder":1,"status":"ACTIVE","version":1
                }]
              }]
            }]
          }]
        }
        """
        return try JSONDecoder().decode(DastakV1RestaurantMenu.self, from: Data(json.utf8))
    }
}
