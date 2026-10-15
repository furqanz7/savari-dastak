import XCTest
@testable import DastakLiveTracking

final class OrderActivityTests: XCTestCase {
    func testAssignmentOnlyAppearsForConfirmedOrdersWithoutRider() {
        for status in ["PAID", "PREPARING"] {
            XCTAssertEqual(DastakOrderActivity.presentationStatus(orderStatus: status, trackingPhase: nil), status)
            XCTAssertEqual(DastakOrderActivity.presentationStatus(orderStatus: status, trackingPhase: nil, fulfilmentState: "PREPARING"), status)
            XCTAssertEqual(DastakOrderActivity.presentationStatus(orderStatus: status, trackingPhase: nil, fulfilmentState: "ASSIGNING_RIDER"), "ASSIGNING_RIDER")
            XCTAssertEqual(DastakOrderActivity.presentationStatus(orderStatus: status, trackingPhase: "SEARCHING_RIDER", fulfilmentState: "ASSIGNING_RIDER"), "ASSIGNING_RIDER")
            for phase in ["ASSIGNED", "EN_ROUTE_TO_PICKUPS", "PICKUP_IN_PROGRESS", "DELIVERY_RECOVERY"] {
                XCTAssertEqual(DastakOrderActivity.presentationStatus(orderStatus: status, trackingPhase: phase, fulfilmentState: "ASSIGNING_RIDER"), status)
            }
        }
        for status in ["MATCHING", "AWAITING_PAYMENT", "CANCELLED", "DELIVERED", "OUT_FOR_DELIVERY"] {
            XCTAssertEqual(DastakOrderActivity.presentationStatus(orderStatus: status, trackingPhase: nil, fulfilmentState: "ASSIGNING_RIDER"), status)
        }
        let state = DastakOrderActivity.ContentState(status: "ASSIGNING_RIDER", version: 3, updatedAt: 1)
        XCTAssertEqual(state.title, "Assigning your rider")
        XCTAssertFalse(state.canCallRider)
        XCTAssertFalse(state.terminal)
        XCTAssertEqual(state.stage, 1)
    }
    func testArrivalIsDistinctAndCallOnlyDuringLastMile() {
        let arrived = DastakOrderActivity.ContentState(status: "RIDER_ARRIVED", version: 3, updatedAt: 1)
        XCTAssertEqual(arrived.title, "Rider arrived")
        XCTAssertEqual(arrived.shortTitle, "At your door")
        XCTAssertFalse(arrived.terminal)
        XCTAssertTrue(arrived.canCallRider)
        XCTAssertEqual(arrived.journeyProgress, 1)
        for status in ["PREPARING", "PICKUP_IN_PROGRESS", "CANCELLED", "DELIVERED", "ENDED"] {
            XCTAssertFalse(DastakOrderActivity.ContentState(status: status, version: 1, updatedAt: 0).canCallRider)
        }
        XCTAssertTrue(DastakOrderActivity.ContentState(status: "OUT_FOR_DELIVERY", version: 1, updatedAt: 0).canCallRider)
    }
    func testNoBicycleAndCallLinkContainsNoPhone() {
        for status in ["PREPARING", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY", "RIDER_ARRIVED", "DELIVERED"] {
            XCTAssertNotEqual(DastakOrderActivity.ContentState(status: status, version: 1, updatedAt: 0).symbol, "bicycle")
        }
        let attributes = DastakOrderActivity(orderID: UUID().uuidString, accountID: "sample", orderNumber: "DSK-1", isFood: false)
        XCTAssertEqual(attributes.callURL?.query, "action=call-rider")
        XCTAssertEqual(attributes.callURL?.scheme, "com.dastak.app")
    }
    func testAllTerminalOutcomesStopProgress() {
        for status in ["DELIVERED", "UNAVAILABLE", "PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT", "CANCELLED", "DASTAK_FULFILMENT_FAILURE", "ENDED"] {
            let state = DastakOrderActivity.ContentState(status: status, version: 4, updatedAt: 100)
            XCTAssertTrue(state.terminal, status)
            XCTAssertNotEqual(state.title, "Finding your items", status)
        }
    }
    func testReservationNeverClaimsOrderIsPreparingOrPaid() {
        for status in ["CREATED", "MATCHING", "FULLY_SECURED", "AWAITING_PAYMENT"] {
            let state = DastakOrderActivity.ContentState(status: status, version: 1, updatedAt: 0)
            XCTAssertEqual(state.stage, 0)
            XCTAssertFalse(state.terminal)
        }
        XCTAssertEqual(DastakOrderActivity.ContentState(status: "OUT_FOR_DELIVERY", version: 3, updatedAt: 0).stage, 3)
    }
    func testPushWireFormatAndSafeDeepLink() throws {
        let data = Data(#"{"status":"DELIVERED","version":9,"updatedAt":1791970000}"#.utf8)
        let state = try JSONDecoder().decode(DastakOrderActivity.ContentState.self, from: data)
        XCTAssertEqual(state.title, "Delivered. Enjoy!")
        let attributes = DastakOrderActivity(orderID: UUID().uuidString, accountID: "sample", orderNumber: "DSK-1", isFood: true)
        XCTAssertEqual(attributes.url?.host, "order")
        XCTAssertEqual(attributes.serviceSymbol, "fork.knife")
        XCTAssertNil(DastakOrderActivity(orderID: "../bad", accountID: "", orderNumber: "", isFood: false).url)
    }
}
