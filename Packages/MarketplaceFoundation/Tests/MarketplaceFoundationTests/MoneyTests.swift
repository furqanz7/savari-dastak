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
}
