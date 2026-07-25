import XCTest
@testable import DastakDomain

final class RefundEligibilityTests: XCTestCase {
    func testMerchantOrderRefundRulesAreStageBased() {
        XCTAssertEqual(RefundEligibility(status: .paid).decision, .full)
        XCTAssertEqual(
            RefundEligibility(status: .merchantAccepted).decision,
            .ownerOrMerchantFailure
        )
        XCTAssertEqual(
            RefundEligibility(status: .pickedUp).decision,
            .deliveryFeeRetainedUnlessFault
        )
    }

    func testTerminalDeliveryIsNotRefundable() {
        XCTAssertEqual(
            RefundEligibility(status: .delivered).decision,
            .notRefundable
        )
    }
}
