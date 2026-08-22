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
}
