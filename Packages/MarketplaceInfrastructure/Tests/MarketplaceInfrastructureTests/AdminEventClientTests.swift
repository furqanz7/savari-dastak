import Supabase
import XCTest
@testable import MarketplaceInfrastructure

final class AdminEventClientTests: XCTestCase {
    func testDecodesWorkspaceInvalidationWithoutRecordData() {
        let event = SupabaseAdminEventClient.decode([
            "event": .string("admin_changed"),
            "payload": .object([
                "workspaces": .array([
                    .string("liveOrders"),
                    .string("commandCenter"),
                    .string("liveOrders")
                ])
            ])
        ])

        XCTAssertEqual(event?.workspaces, ["liveOrders", "commandCenter"])
    }

    func testRejectsMissingOrEmptyWorkspaceInvalidation() {
        XCTAssertNil(SupabaseAdminEventClient.decode([:]))
        XCTAssertNil(SupabaseAdminEventClient.decode([
            "payload": .object(["workspaces": .array([])])
        ]))
    }
}
