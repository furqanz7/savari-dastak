import Foundation
import MarketplaceFoundation
import XCTest
@testable import DastakDomain

final class DomainContractTests: XCTestCase {
    func testSupportedDeliveryMethodsMatchApprovedLaunchScope() {
        XCTAssertEqual(
            Set(DeliveryMethod.allCases),
            Set([.bike, .auto])
        )
    }

    func testMerchantLineContainsOnlyProductAndQuantity() throws {
        let line = MerchantOrderLine(productID: UUID(), quantity: 2)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(line))
                as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), Set(["productId", "quantity"]))
    }

    func testCreateMerchantOrderSendsOnlyAuthoritativeQuoteID() throws {
        let request = CreateMerchantOrderRequest(quoteID: UUID())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
                as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), Set(["quoteId"]))
    }

    func testSnapshotCarriesAuthoritativeVersionAndPrice() {
        let snapshot = DeliverySnapshot(
            id: UUID(),
            kind: .parcel,
            status: .assigned,
            paymentState: .paid,
            selectedMethod: .bike,
            price: DeliveryPriceSnapshot(
                itemSubtotal: nil,
                deliveryFee: Money(paise: 4_500),
                total: Money(paise: 4_500)
            ),
            pickup: GeoPoint(latitude: 12.6819, longitude: 78.6200),
            dropoff: GeoPoint(latitude: 12.6900, longitude: 78.6300),
            counterpart: DeliveryCounterpartDisplay(
                displayName: "Customer",
                phoneNumber: nil
            ),
            assignmentDeadline: Date(timeIntervalSince1970: 60),
            stateVersion: 4
        )

        XCTAssertEqual(snapshot.stateVersion, 4)
        XCTAssertEqual(snapshot.price.total, Money(paise: 4_500))
        XCTAssertNil(snapshot.counterpart?.phoneNumber)
    }

    func testRefundStateIsSeparateFromDeliveryStatus() {
        XCTAssertEqual(
            DeliveryPaymentState.refundPending.rawValue,
            "refund_pending"
        )
    }
}
