import Supabase
import XCTest
@testable import MarketplaceInfrastructure

final class OrderEventClientTests: XCTestCase {
    func testDecodesMinimalOrderInvalidation() throws {
        let entityID = UUID(uuidString: "FC67D2B1-7D38-4E99-970E-C973049E4794")!
        let event = SupabaseOrderEventClient.decode([
            "event": .string("order_changed"),
            "payload": .object([
                "entityKind": .string("merchant_order"),
                "entityId": .string(entityID.uuidString.lowercased()),
                "stateVersion": .integer(4)
            ])
        ])

        XCTAssertEqual(
            event,
            OrderChangeEvent(
                entityKind: .merchantOrder,
                entityID: entityID,
                stateVersion: 4
            )
        )
    }

    func testRejectsUnknownOrMalformedInvalidations() {
        XCTAssertNil(SupabaseOrderEventClient.decode([:]))
        XCTAssertNil(SupabaseOrderEventClient.decode([
            "payload": .object([
                "entityKind": .string("ride"),
                "entityId": .string(UUID().uuidString),
                "stateVersion": .integer(1)
            ])
        ]))
        XCTAssertNil(SupabaseOrderEventClient.decode([
            "payload": .object([
                "entityKind": .string("parcel"),
                "entityId": .string("not-a-uuid"),
                "stateVersion": .integer(1)
            ])
        ]))
    }
}
