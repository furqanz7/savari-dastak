import Foundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakV1OrderPresentationTests: XCTestCase {
    func testEveryLifecycleStateHasCustomerCopyAndPurposefulSymbol() {
        let statuses: [DastakV1OrderStatus] = [
            .created, .matching, .fullySecured, .awaitingPayment, .paid, .preparing,
            .pickupInProgress, .outForDelivery, .delivered, .unavailable,
            .paymentExpired, .cancelledPrepayment, .fulfilmentFailure,
        ]

        for status in statuses {
            XCTAssertFalse(DastakV1OrderPresentation.title(status).isEmpty)
            XCTAssertFalse(DastakV1OrderPresentation.message(status).isEmpty)
            XCTAssertFalse(DastakV1OrderPresentation.symbol(status).isEmpty)
        }
    }

    func testFailureAndExpiryCopyDoesNotPromiseAnIncorrectNoChargeState() {
        XCTAssertTrue(
            DastakV1OrderPresentation.assurance(.fulfilmentFailure)
                .contains("Payment protection")
        )
        XCTAssertFalse(
            DastakV1OrderPresentation.assurance(.fulfilmentFailure)
                .contains("No charge")
        )
        XCTAssertEqual(
            DastakV1OrderPresentation.symbol(.paymentExpired),
            "clock.badge.exclamationmark"
        )
    }

    func testActiveOrderClassificationIncludesEveryLivePostPaymentState() {
        XCTAssertTrue(DastakV1OrderPresentation.isActive(.paid))
        XCTAssertTrue(DastakV1OrderPresentation.isActive(.preparing))
        XCTAssertTrue(DastakV1OrderPresentation.isActive(.pickupInProgress))
        XCTAssertTrue(DastakV1OrderPresentation.isActive(.outForDelivery))
        XCTAssertFalse(DastakV1OrderPresentation.isActive(.fulfilmentFailure))
        XCTAssertFalse(DastakV1OrderPresentation.isActive(.delivered))
    }

    func testJourneyProgressUsesCustomerVisibleStages() {
        XCTAssertEqual(DastakV1OrderPresentation.journeyStep(.matching), 0)
        XCTAssertEqual(DastakV1OrderPresentation.journeyStep(.preparing), 2)
        XCTAssertEqual(DastakV1OrderPresentation.journeyStep(.outForDelivery), 4)
        XCTAssertEqual(DastakV1OrderPresentation.journeyStep(.delivered), 5)
        XCTAssertNil(DastakV1OrderPresentation.journeyStep(.paymentExpired))
        XCTAssertEqual(
            DastakV1OrderPresentation.journeyLabel(.outForDelivery),
            "On the way"
        )
    }

    func testMatchingCopyKeepsInternalMerchantAndWaveDetailsPrivate() {
        let copy = DastakV1OrderPresentation.message(.matching).lowercased()
        XCTAssertTrue(copy.contains("every exact item"))
        XCTAssertFalse(copy.contains("merchant"))
        XCTAssertFalse(copy.contains("wave"))
    }

    func testRestaurantOptionsAndImmutableAddressAreHumanReadable() throws {
        let line = try JSONDecoder().decode(
            DastakV1OrderLine.self,
            from: Data(
                """
                {
                  "id":"11111111-1111-4111-8111-111111111111",
                  "lineType":"FOOD_MENU_ITEM",
                  "menuItemId":"22222222-2222-4222-8222-222222222222",
                  "name":"Filter Coffee","quantity":1,"unitPricePaise":5000,
                  "lineTotalPaise":5000,"status":"ORDERED",
                  "foodSelection":{"options":[{
                    "id":"33333333-3333-4333-8333-333333333333",
                    "groupId":"44444444-4444-4444-8444-444444444444",
                    "groupName":"Size","name":"Large","priceDeltaPaise":500
                  }]}
                }
                """.utf8
            )
        )
        let address = DastakV1DeliveryAddressInput(
            label: "Home", line1: "1 Launch Road", line2: "First floor",
            landmark: "Near the park", city: "Vaniyambadi", state: "Tamil Nadu",
            postalCode: "635751", latitude: 12.6819, longitude: 78.6201,
            instructions: "Ring once"
        )

        XCTAssertEqual(DastakV1OrderPresentation.optionSummary(line), "Large")
        XCTAssertEqual(
            DastakV1OrderPresentation.addressLine(address),
            "First floor, 1 Launch Road, Near the park, Vaniyambadi, Tamil Nadu, 635751"
        )
        XCTAssertEqual(
            DastakV1OrderPresentation.phoneNumber("+919876543210"),
            "+91 98765 43210"
        )
    }

    func testOrderHistorySupportsSearchDeliveryDurationAndReorderEligibility() throws {
        let order = try JSONDecoder().decode(
            DastakV1OrderSnapshot.self,
            from: Data(
                """
                {
                  "id":"11111111-1111-4111-8111-111111111111",
                  "displayOrderNumber":"DV1-0042","orderType":"RETAIL_ONLY",
                  "status":"DELIVERED","version":4,
                  "price":{"snapshotKind":"FINAL_PAYABLE","subtotalPaise":10000,
                    "deliveryFeePaise":0,"platformFeePaise":200,"discountPaise":0,
                    "taxPaise":0,"totalPaise":10200,"currencyCode":"INR"},
                  "lines":[{"id":"22222222-2222-4222-8222-222222222222",
                    "lineType":"RETAIL_SKU","skuId":"33333333-3333-4333-8333-333333333333",
                    "name":"Filter Coffee","packSize":"250 g","quantity":2,
                    "unitPricePaise":5000,"lineTotalPaise":10000,"status":"DELIVERED"}],
                  "submittedAt":"2026-08-24T09:00:00Z",
                  "deliveredAt":"2026-08-24T09:21:00Z",
                  "createdAt":"2026-08-24T09:00:00Z","updatedAt":"2026-08-24T09:21:00Z"
                }
                """.utf8
            )
        )

        XCTAssertEqual(DastakV1OrderPresentation.deliveredDuration(order), "Delivered in 21 min")
        XCTAssertEqual(DastakV1OrderPresentation.itemCount(order), 2)
        XCTAssertTrue(DastakV1OrderPresentation.searchText(order).contains("filter coffee"))
        XCTAssertTrue(DastakV1OrderPresentation.canReorder(.delivered))
        XCTAssertFalse(DastakV1OrderPresentation.canReorder(.preparing))
    }
}
