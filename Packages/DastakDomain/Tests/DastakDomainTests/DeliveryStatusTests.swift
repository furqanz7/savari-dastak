import XCTest
@testable import DastakDomain

final class DeliveryStatusTests: XCTestCase {
    func testMerchantOrderCannotBeAssignedBeforeReady() {
        XCTAssertFalse(
            DeliveryStatus.merchantAccepted.canTransition(
                to: .assigned,
                for: .merchantOrder
            )
        )
        XCTAssertTrue(
            DeliveryStatus.ready.canTransition(
                to: .assigned,
                for: .merchantOrder
            )
        )
    }

    func testPaidStateUsesKindSpecificPath() {
        XCTAssertTrue(
            DeliveryStatus.paid.canTransition(to: .assigned, for: .parcel)
        )
        XCTAssertFalse(
            DeliveryStatus.paid.canTransition(to: .assigned, for: .merchantOrder)
        )
        XCTAssertTrue(
            DeliveryStatus.paid.canTransition(
                to: .merchantAccepted,
                for: .merchantOrder
            )
        )
    }

    func testParcelRequiresPickupBeforeDelivery() {
        XCTAssertFalse(
            DeliveryStatus.assigned.canTransition(to: .delivered, for: .parcel)
        )
        XCTAssertTrue(
            DeliveryStatus.enRouteToPickup.canTransition(to: .pickedUp, for: .parcel)
        )
        XCTAssertTrue(
            DeliveryStatus.pickedUp.canTransition(to: .inTransit, for: .parcel)
        )
    }

    func testMerchantOrderRequiresArrivalAtStoreBeforePickup() {
        XCTAssertFalse(
            DeliveryStatus.enRouteToPickup.canTransition(
                to: .pickedUp,
                for: .merchantOrder
            )
        )
        XCTAssertTrue(
            DeliveryStatus.enRouteToPickup.canTransition(
                to: .atStore,
                for: .merchantOrder
            )
        )
        XCTAssertTrue(
            DeliveryStatus.atStore.canTransition(to: .pickedUp, for: .merchantOrder)
        )
    }

    func testRestrictedHandoffRequiresMerchantReturn() {
        XCTAssertTrue(
            DeliveryStatus.inTransit.canTransition(
                to: .returningToMerchant,
                for: .merchantOrder
            )
        )
        XCTAssertFalse(
            DeliveryStatus.inTransit.canTransition(
                to: .returningToMerchant,
                for: .parcel
            )
        )
        XCTAssertTrue(
            DeliveryStatus.returningToMerchant.canTransition(
                to: .cancelled,
                for: .merchantOrder
            )
        )
    }
}
