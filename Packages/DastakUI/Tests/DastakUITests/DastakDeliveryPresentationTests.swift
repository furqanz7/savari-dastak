import Foundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakDeliveryPresentationTests: XCTestCase {
    func testHistoryUsesHumanFacingKindsWithoutInternalVersionLabels() {
        XCTAssertEqual(DastakDeliveryHistoryPresentation.kind("V1_DELIVERY"), "Delivery")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.kind("LEGACY_DELIVERY"), "Delivery")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.kind("RETURN"), "Return")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.kind("PARCEL"), "Parcel")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.kind("OTHER_WORK"), "Other Work")
    }

    func testHistoryDistinguishesCompletedCancelledAndReturnedWithoutInventingSuccess() {
        for outcome in ["COMPLETED", "DELIVERED", "RETURNED"] {
            XCTAssertEqual(DastakDeliveryHistoryPresentation.tone(outcome), .success)
        }
        for outcome in ["CANCELLED", "CANCELED"] {
            XCTAssertEqual(DastakDeliveryHistoryPresentation.outcome(outcome), "Cancelled")
            XCTAssertEqual(DastakDeliveryHistoryPresentation.tone(outcome), .cancelled)
        }
        XCTAssertEqual(DastakDeliveryHistoryPresentation.outcome("DELIVERED"), "Completed")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.outcome("RETURNED"), "Returned")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.tone("UNKNOWN"), .neutral)
        XCTAssertEqual(DastakDeliveryHistoryPresentation.outcome("UNKNOWN"), "Unknown")
    }

    func testHistoryPackageCountsUseCorrectPluralAndDoNotInventMissingCounts() {
        XCTAssertEqual(DastakDeliveryHistoryPresentation.packages(1), "1 package")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.packages(2), "2 packages")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.packages(0), "0 packages")
        XCTAssertNil(DastakDeliveryHistoryPresentation.packages(nil))
        XCTAssertNil(DastakDeliveryHistoryPresentation.packages(-1))
    }

    func testHistoryPayoutOnlyDisplaysSuppliedNonnegativeRecordedAmounts() {
        XCTAssertNil(DastakDeliveryHistoryPresentation.payout(nil))
        XCTAssertNil(DastakDeliveryHistoryPresentation.payout(-1))
        XCTAssertEqual(DastakDeliveryHistoryPresentation.payout(1500), "Recorded payout · ₹15.00")
        XCTAssertEqual(DastakDeliveryHistoryPresentation.payout(0), "Recorded payout · ₹0.00")
    }

    func testNextStopMapRejectsUnknownAndInvalidCoordinates() {
        for values: (Double?, Double?) in [(nil, 78), (12, nil), (.nan, 78), (91, 78), (12, 181)] {
            XCTAssertNil(DastakDeliveryDestination(title: "Pickup", name: "Merchant", address: "Store Road", latitude: values.0, longitude: values.1).coordinate)
        }
        XCTAssertNotNil(DastakDeliveryDestination(title: "Pickup", name: "Merchant", address: "Store Road", latitude: 12.6, longitude: 78.6).coordinate)
    }
    func testCustomerCallUsesOnlyValidInternationalTelephoneURLs() {
        XCTAssertEqual(DastakDeliveryPresentation.callURL("+919700000001")?.absoluteString, "tel:+919700000001")
        for value in ["+000000000", "919700000001", "+919700000001?x=1", "tel:+919700000001", "+٩١٩٧٠٠٠٠٠٠٠١"] {
            XCTAssertNil(DastakDeliveryPresentation.callURL(value))
        }
    }
    func testEveryDeliveryStageHasClearNextStep() {
        let stages: [DastakV1MissionStatus] = [.assigned, .enRouteToPickups, .pickupInProgress,
            .allPackagesPickedUp, .outForDelivery, .arrived, .deliveryRecovery]
        for stage in stages {
            XCTAssertFalse(DastakDeliveryPresentation.title(stage).isEmpty)
            XCTAssertFalse(DastakDeliveryPresentation.instruction(stage).isEmpty)
        }
        XCTAssertEqual(DastakDeliveryPresentation.step(.assigned), 0)
        XCTAssertEqual(DastakDeliveryPresentation.step(.pickupInProgress), 0)
        XCTAssertEqual(DastakDeliveryPresentation.step(.allPackagesPickedUp), 1)
        XCTAssertEqual(DastakDeliveryPresentation.step(.outForDelivery), 1)
        XCTAssertEqual(DastakDeliveryPresentation.step(.arrived), 2)
        XCTAssertNil(DastakDeliveryPresentation.step(.deliveryRecovery))
    }

    func testExpiredAndInvalidOffersCannotBeAccepted() {
        let now = ISO8601DateFormatter().date(from: "2026-09-08T00:00:00Z")!
        XCTAssertEqual(DastakDeliveryPresentation.secondsRemaining(until: "invalid", now: now), 0)
        XCTAssertEqual(DastakDeliveryPresentation.secondsRemaining(until: "2026-09-07T23:59:59Z", now: now), 0)
        XCTAssertEqual(DastakDeliveryPresentation.secondsRemaining(until: "2026-09-08T00:00:00Z", now: now), 0)
        XCTAssertEqual(DastakDeliveryPresentation.secondsRemaining(until: "2026-09-08T00:00:00.500Z", now: now), 1)
        XCTAssertEqual(DastakDeliveryPresentation.secondsRemaining(until: "2026-09-08T00:01:00Z", now: now), 60)
    }

    func testHandoffCodeUsesOnlyServerCompatibleDigits() {
        XCTAssertEqual(DastakDeliveryPresentation.code("12 34-56abc789", length: 6), "123456")
        XCTAssertEqual(DastakDeliveryPresentation.code("١٢٣４５６1234", length: 6), "1234")
        XCTAssertEqual(DastakDeliveryPresentation.code("12\n34", length: 4), "1234")
    }

    func testRecoveryNeverSuggestsNormalDeliveryOrPayment() {
        XCTAssertTrue(DastakDeliveryPresentation.instruction(.deliveryRecovery).contains("Operations"))
        XCTAssertTrue(DastakDeliveryPresentation.instruction(.arrived).contains("payment if due"))
    }
}
