import XCTest
@testable import DastakUI

@MainActor
final class DastakNotificationInboxTests: XCTestCase {
    func testClearRemovesDeliveredNotificationsAndResetsBadge() {
        var deliveredNotificationsRemoved = false
        var badgeReset = false
        let inbox = DastakNotificationInbox(
            removeDeliveredNotifications: {
                deliveredNotificationsRemoved = true
            },
            resetBadge: {
                badgeReset = true
            }
        )

        inbox.clear()

        XCTAssertTrue(deliveredNotificationsRemoved)
        XCTAssertTrue(badgeReset)
    }
}
