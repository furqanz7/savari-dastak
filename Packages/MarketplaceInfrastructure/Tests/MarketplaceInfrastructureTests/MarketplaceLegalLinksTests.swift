import XCTest
@testable import MarketplaceInfrastructure

final class MarketplaceLegalLinksTests: XCTestCase {
    func testAcceptsPublicLegalAndSupportDestinations() {
        let links = MarketplaceLegalLinks(values: [
            MarketplaceLegalLinks.privacyPolicyKey: "https://dastak.example/privacy",
            MarketplaceLegalLinks.termsKey: "https://dastak.example/terms",
            MarketplaceLegalLinks.supportKey: "mailto:help@dastak.example",
        ])

        XCTAssertEqual(links.privacyPolicy?.absoluteString, "https://dastak.example/privacy")
        XCTAssertEqual(links.terms?.absoluteString, "https://dastak.example/terms")
        XCTAssertEqual(links.support?.absoluteString, "mailto:help@dastak.example")
    }

    func testRejectsInsecureOrPlaceholderDestinations() {
        let links = MarketplaceLegalLinks(values: [
            MarketplaceLegalLinks.privacyPolicyKey: "http://dastak.example/privacy",
            MarketplaceLegalLinks.termsKey: "",
            MarketplaceLegalLinks.supportKey: "javascript:alert(1)",
        ])

        XCTAssertNil(links.privacyPolicy)
        XCTAssertNil(links.terms)
        XCTAssertNil(links.support)
    }
}
