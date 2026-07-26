import XCTest
@testable import DastakUI

final class DastakMerchantPriceParserTests: XCTestCase {
    func testParsesWholeAndFractionalRupeesWithoutRounding() throws {
        XCTAssertEqual(try DastakMerchantPriceParser.paise(from: "1"), 100)
        XCTAssertEqual(try DastakMerchantPriceParser.paise(from: "49.95"), 4_995)
    }

    func testRejectsSubPaiseNonPositiveAndOversizedPrices() {
        XCTAssertThrowsError(try DastakMerchantPriceParser.paise(from: "1.001"))
        XCTAssertThrowsError(try DastakMerchantPriceParser.paise(from: "0"))
        XCTAssertThrowsError(try DastakMerchantPriceParser.paise(from: "-2"))
        XCTAssertThrowsError(try DastakMerchantPriceParser.paise(from: "1000000.01"))
    }
}
