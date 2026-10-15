import Foundation
import XCTest
@testable import MarketplaceFoundation

@MainActor
final class DastakAppActionTests: XCTestCase {
    func testControlsUseConciseEnglishLabelsAndDistinctSymbols() {
        let actions: [DastakAppAction] = [.search, .grocery, .food, .basket, .tracking]
        XCTAssertEqual(actions.map(\.controlTitle), ["Search", "Grocery", "Food", "Basket", "Track Order"])
        XCTAssertEqual(Set(actions.map(\.controlSymbol)).count, 5)
        XCTAssertEqual(DastakAppAction.grocery.controlSymbol, "storefront")
        XCTAssertEqual(DastakAppAction.basket.controlSymbol, "basket")
        for action in actions {
            XCTAssertFalse(action.controlTitle.contains("Dastak"))
            XCTAssertLessThanOrEqual(action.controlTitle.count, 11)
            XCTAssertFalse(action.controlActionHint.isEmpty)
        }
    }

    func testAllActionsRoundTripThroughURLAndQuickAction() {
        for action in DastakAppAction.allCases {
            XCTAssertEqual(DastakAppAction(url: URL(string: "com.dastak.app://open/\(action.rawValue)")!), action)
            XCTAssertEqual(DastakAppAction(shortcutType: "com.dastak.app.quick.\(action.rawValue)"), action)
        }
    }

    func testRejectsUnknownActionsAndUntrustedURLs() {
        for text in ["https://open/food", "com.dastak.app://order/food", "com.dastak.app://open/pay",
                     "com.dastak.app://open/food?submit=1", "com.dastak.app://open/food/more",
                     "com.dastak.app://open/basket#submit"] {
            XCTAssertNil(DastakAppAction(url: URL(string: text)!))
        }
        XCTAssertNil(DastakAppAction(shortcutType: "other.quick.food"))
        XCTAssertNil(DastakAppAction(shortcutType: "com.dastak.app.quick.confirm"))
    }

    func testPendingActionSurvivesNewInboxAndConsumesOnce() throws {
        let suite = "DastakAppActionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let time = Date()
        DastakAppActionInbox(defaults: defaults).request(.food, now: time)
        let restored = DastakAppActionInbox(defaults: defaults)
        XCTAssertEqual(restored.peek(now: time), .food)
        XCTAssertEqual(restored.consume(now: time), .food)
        XCTAssertNil(restored.consume(now: time))
    }

    func testMostRecentExplicitActionWinsAndStaleOrFutureActionsExpire() throws {
        let suite = "DastakAppActionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let inbox = DastakAppActionInbox(defaults: defaults)
        let time = Date()
        inbox.request(.grocery, now: time)
        inbox.request(.tracking, now: time)
        XCTAssertEqual(inbox.consume(now: time), .tracking)
        inbox.request(.basket, now: time)
        XCTAssertNil(inbox.peek(now: time.addingTimeInterval(901)))
        XCTAssertNil(inbox.peek(now: time))
        inbox.request(.food, now: time.addingTimeInterval(20))
        XCTAssertNil(inbox.consume(now: time))
    }
}
