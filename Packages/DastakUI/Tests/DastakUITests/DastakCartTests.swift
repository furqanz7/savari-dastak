import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakCartTests: XCTestCase {
    func testCartAggregatesQuantityAndSubtotal() throws {
        var cart = DastakCart()
        let product = try fixtureProduct(
            productID: "11111111-1111-4111-8111-111111111111",
            storeID: "22222222-2222-4222-8222-222222222222",
            pricePaise: 12_500
        )

        XCTAssertEqual(cart.add(product), .added)
        XCTAssertEqual(cart.add(product), .added)
        XCTAssertEqual(cart.itemCount, 2)
        XCTAssertEqual(cart.subtotal, Money(paise: 25_000))
        XCTAssertEqual(cart.orderLines, [
            MerchantOrderLineInput(productID: product.productID, quantity: 2)
        ])
    }

    func testCartRejectsProductsFromAnotherStoreUntilExplicitReplacement() throws {
        var cart = DastakCart()
        let first = try fixtureProduct(
            productID: "11111111-1111-4111-8111-111111111111",
            storeID: "22222222-2222-4222-8222-222222222222"
        )
        let second = try fixtureProduct(
            productID: "33333333-3333-4333-8333-333333333333",
            storeID: "44444444-4444-4444-8444-444444444444"
        )

        XCTAssertEqual(cart.add(first), .added)
        XCTAssertEqual(cart.add(second), .differentStore)
        XCTAssertEqual(cart.entries.map(\.product.productID), [first.productID])

        cart.replaceStore(with: second)
        XCTAssertEqual(cart.entries.map(\.product.productID), [second.productID])
    }

    private func fixtureProduct(
        productID: String,
        storeID: String,
        pricePaise: Int = 10_000
    ) throws -> CatalogueProduct {
        let json = """
        {
          "productId": "\(productID)",
          "storeId": "\(storeID)",
          "categoryId": "55555555-5555-4555-8555-555555555555",
          "name": "Market item",
          "description": "Freshly stocked",
          "unitLabel": "1 unit",
          "price": {"paise": \(pricePaise)},
          "imageObjectPath": null,
          "availability": "in_stock",
          "catalogueKind": "general",
          "restrictedApprovalState": "not_applicable",
          "isActive": true
        }
        """
        return try JSONDecoder().decode(CatalogueProduct.self, from: Data(json.utf8))
    }
}
