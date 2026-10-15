import XCTest
@testable import MarketplaceDesignSystem

final class MarketplaceHapticsPolicyTests: XCTestCase {
    func testSemanticImpactReplacesFallbackTapRegardlessOfOrder() {
        for events: [MarketplaceHapticEvent] in [[.tap, .itemAdded], [.itemAdded, .tap], [.tap, .basketPickup, .tap]] {
            var batch = MarketplaceHapticBatch()
            events.forEach { batch.enqueue($0) }
            XCTAssertEqual(batch.take(enabled: true, active: true), events.contains(.basketPickup) ? .basketPickup : .itemAdded)
            XCTAssertNil(batch.take(enabled: true, active: true))
        }
    }
    func testErrorAndWarningCannotBeMaskedBySuccessOrTap() {
        var batch = MarketplaceHapticBatch()
        [.tap, .error, .success, .warning].forEach { batch.enqueue($0) }
        XCTAssertEqual(batch.take(enabled: true, active: true), .error)
        batch.enqueue(.tap); batch.enqueue(.warning)
        XCTAssertEqual(batch.take(enabled: true, active: true), .warning)
    }
    func testDisabledAndBackgroundEventsAreDiscardedNotReplayed() {
        var batch = MarketplaceHapticBatch()
        batch.enqueue(.success)
        XCTAssertNil(batch.take(enabled: false, active: true))
        XCTAssertNil(batch.take(enabled: true, active: true))
        batch.enqueue(.basketPickup)
        XCTAssertNil(batch.take(enabled: true, active: false))
        XCTAssertNil(batch.take(enabled: true, active: true))
    }
}

@MainActor
final class MarketplaceHapticsScopeTests: XCTestCase {
    func testOnePulseForTapAndBasketMutationAndSeparateLaterAction() async throws {
        var events: [MarketplaceHapticEvent] = []
        let scope = MarketplaceHapticScope(output: { events.append($0) }, enabled: { true }, foreground: { true })
        scope.isActive = true
        scope.play(.tap); scope.play(.itemAdded); scope.play(.tap)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(events, [.itemAdded])
        scope.play(.itemRemoved)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(events, [.itemAdded, .itemRemoved])
    }
    func testScopeInactiveAndPreferenceOffStaySilent() async throws {
        var events: [MarketplaceHapticEvent] = []
        var enabled = true
        let scope = MarketplaceHapticScope(output: { events.append($0) }, enabled: { enabled }, foreground: { true })
        scope.play(.tap)
        scope.isActive = true; enabled = false; scope.play(.success)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(events.isEmpty)
    }
    func testBackgroundOrPreferenceChangeBeforeDeliveryDropsQueuedFeedback() async throws {
        var events: [MarketplaceHapticEvent] = []
        var enabled = true, foreground = true
        let scope = MarketplaceHapticScope(output: { events.append($0) }, enabled: { enabled }, foreground: { foreground })
        scope.isActive = true; scope.play(.itemAdded); foreground = false
        try await Task.sleep(for: .milliseconds(80))
        foreground = true; scope.play(.success); enabled = false
        try await Task.sleep(for: .milliseconds(80))
        enabled = true; scope.play(.tap); scope.isActive = false
        try await Task.sleep(for: .milliseconds(80))
        scope.isActive = true
        XCTAssertTrue(events.isEmpty)
    }
}
