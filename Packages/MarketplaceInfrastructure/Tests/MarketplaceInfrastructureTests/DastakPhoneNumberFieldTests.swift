@testable import MarketplaceInfrastructure
import XCTest

final class DastakPhoneNumberFieldTests: XCTestCase {
    func testParsesAnIndianE164NumberIntoReadOnlyCodeAndNationalNumber() {
        let parts = DastakPhoneNumberParts.parse("+919876543210")

        XCTAssertEqual(parts.country.regionCode, "IN")
        XCTAssertEqual(parts.country.dialCode, "+91")
        XCTAssertEqual(parts.nationalNumber, "9876543210")
    }

    func testCanonicalNumberRemovesFormattingAndKeepsSelectedCode() {
        let number = DastakPhoneNumberParts.canonical(
            country: .init(regionCode: "BD", dialCode: "+880"),
            nationalNumber: "017 1234-5678"
        )

        XCTAssertEqual(number, "+88001712345678")
    }

    func testSharedCallingCodeHonoursPreferredRegion() {
        let parts = DastakPhoneNumberParts.parse("+14165550123", preferredRegionCode: "CA")

        XCTAssertEqual(parts.country.regionCode, "CA")
        XCTAssertEqual(parts.nationalNumber, "4165550123")
    }

    func testCanonicalNumberCannotExceedE164MaximumLength() {
        let number = DastakPhoneNumberParts.canonical(
            country: .india,
            nationalNumber: "12345678901234567890"
        )

        XCTAssertEqual(number, "+911234567890123")
    }

    func testValidatorAcceptsARealIndianMobileNumber() {
        XCTAssertEqual(
            DastakPhoneNumberValidator.canonicalE164("+919876543210"),
            "+919876543210"
        )
    }

    func testValidatorRejectsAnImpossibleIndianNumber() {
        XCTAssertFalse(DastakPhoneNumberValidator.isValidE164("+910000000000"))
    }

    func testValidatorRequiresCanonicalE164Input() {
        XCTAssertNil(DastakPhoneNumberValidator.canonicalE164("+91 98765 43210"))
    }
}
