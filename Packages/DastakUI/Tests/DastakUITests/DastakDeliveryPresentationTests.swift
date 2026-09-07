import Foundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakDeliveryPresentationTests: XCTestCase {
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
