import Foundation
import XCTest
@testable import MarketplaceFoundation

final class MoneyTests: XCTestCase {
    func testRupeePaiseRoundTripPreservesIntegerAmount() {
        XCTAssertEqual(Money(paise: 12_345).rupees, 123.45)
        XCTAssertEqual(Money(rupees: 123.45).paise, 12_345)
    }

    func testIdempotencyKeyRejectsEmptyValue() {
        XCTAssertNil(IdempotencyKey(rawValue: ""))
        XCTAssertNotNil(IdempotencyKey(rawValue: UUID().uuidString))
    }

    func testIdempotencyKeyRejectsWhitespaceOnlyValue() {
        XCTAssertNil(IdempotencyKey(rawValue: " \n\t "))
    }

    func testRupeesAboveIntMaxPaiseFailsBeforeIntConversionCanWrap() throws {
        let rupeesAboveIntMaxPaise = (Decimal(Int.max) + 1) / 100

        #if os(macOS)
        if ProcessInfo.processInfo.environment["MARKETPLACE_FOUNDATION_OVERFLOW_PROBE"] == "1" {
            _ = Money(rupees: rupeesAboveIntMaxPaise)
            exit(EXIT_SUCCESS)
        }

        let probe = Process()
        let testBundle = Bundle(for: MoneyTests.self)
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        probe.arguments = ["xctest", testBundle.bundleURL.path]
        probe.environment = ProcessInfo.processInfo.environment.merging(
            ["MARKETPLACE_FOUNDATION_OVERFLOW_PROBE": "1"],
            uniquingKeysWith: { _, newValue in newValue }
        )
        probe.standardOutput = Pipe()
        probe.standardError = Pipe()
        try probe.run()
        probe.waitUntilExit()

        XCTAssertNotEqual(
            probe.terminationStatus,
            0,
            "Expected the overflow probe to fail; bundle=\(testBundle.bundleURL.path), reason=\(probe.terminationReason.rawValue)."
        )
        #else
        throw XCTSkip("The precondition probe runs in the macOS SwiftPM test host.")
        #endif
    }
}
