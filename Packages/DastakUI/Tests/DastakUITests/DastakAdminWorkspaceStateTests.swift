import Foundation
import XCTest
@testable import DastakUI

final class DastakAdminWorkspaceStateTests: XCTestCase {
    func testFailurePreservesLastSuccessfulRefreshUntilRecovery() {
        let firstSuccess = Date(timeIntervalSince1970: 1_000)
        let recoveredAt = Date(timeIntervalSince1970: 3_000)
        var state = DastakAdminWorkspaceState()

        state.recordSuccess(.operationalSafety, at: firstSuccess)
        state.recordFailure(
            DastakAdminWorkspaceIssue(
                workspace: .operationalSafety,
                message: "Safety controls could not be refreshed.",
                occurredAt: Date(timeIntervalSince1970: 2_000)
            )
        )

        XCTAssertEqual(
            state.lastSuccessfulRefresh[.operationalSafety],
            firstSuccess,
            "A transient failure must not erase the timestamp of still-visible data."
        )
        XCTAssertNotNil(state.issues[.operationalSafety])

        state.recordSuccess(.operationalSafety, at: recoveredAt)
        XCTAssertNil(state.issues[.operationalSafety])
        XCTAssertEqual(state.lastSuccessfulRefresh[.operationalSafety], recoveredAt)
    }

    func testWorkspaceFailuresRemainIndependent() {
        var state = DastakAdminWorkspaceState()
        state.recordFailure(
            DastakAdminWorkspaceIssue(
                workspace: .catalogue,
                message: "Catalogue unavailable.",
                occurredAt: Date()
            )
        )
        state.recordSuccess(.commandCenter, at: Date(timeIntervalSince1970: 4_000))

        XCTAssertNotNil(state.issues[.catalogue])
        XCTAssertNil(state.issues[.commandCenter])
        XCTAssertEqual(
            state.lastSuccessfulRefresh[.commandCenter],
            Date(timeIntervalSince1970: 4_000)
        )
    }

    func testBeginningRefreshClearsWarningWithoutDiscardingLastGoodData() {
        let lastSuccess = Date(timeIntervalSince1970: 5_000)
        var state = DastakAdminWorkspaceState()

        state.recordSuccess(.commandCenter, at: lastSuccess)
        state.recordFailure(
            DastakAdminWorkspaceIssue(
                workspace: .commandCenter,
                message: "Command center could not be refreshed.",
                occurredAt: Date(timeIntervalSince1970: 6_000)
            )
        )

        state.beginRefresh(.commandCenter)

        XCTAssertNil(state.issues[.commandCenter])
        XCTAssertEqual(state.lastSuccessfulRefresh[.commandCenter], lastSuccess)
    }
}
