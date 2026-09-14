import Foundation
import XCTest
@testable import DastakUI

final class DastakMerchantRestaurantMenuTests: XCTestCase {
    func testImageInspectorAcceptsARealDecodedPNG() throws {
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))

        let result = try XCTUnwrap(DastakMerchantImageInspector.inspect(png))

        XCTAssertEqual(result.contentType, "image/png")
        XCTAssertEqual(result.extension, "png")
    }

    func testImageInspectorRejectsSpoofedAndOversizedFiles() {
        XCTAssertNil(DastakMerchantImageInspector.inspect(Data("not an image".utf8)))
        XCTAssertNil(DastakMerchantImageInspector.inspect(Data(repeating: 0, count: 5 * 1_024 * 1_024 + 1)))
    }

    func testOptionalExtraPriceAcceptsZeroButRejectsSubPaiseAndNegativeValues() {
        XCTAssertEqual(DastakMerchantPriceParser.optionalNonnegativePaise(from: "0"), 0)
        XCTAssertEqual(DastakMerchantPriceParser.optionalNonnegativePaise(from: "12.50"), 1_250)
        XCTAssertNil(DastakMerchantPriceParser.optionalNonnegativePaise(from: "0.001"))
        XCTAssertNil(DastakMerchantPriceParser.optionalNonnegativePaise(from: "-1"))
    }
}
