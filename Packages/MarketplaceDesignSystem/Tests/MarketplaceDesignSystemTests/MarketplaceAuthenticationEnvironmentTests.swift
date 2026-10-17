import SwiftUI
import XCTest
@testable import MarketplaceDesignSystem

@MainActor
final class MarketplaceAuthenticationEnvironmentTests: XCTestCase {
    func testAuthenticationAdditionsAreOptIn() {
        let values = EnvironmentValues()
        XCTAssertNil(values.marketplaceAuthenticationBackdrop)
        XCTAssertNil(values.marketplaceAuthenticationFooter)
        XCTAssertNil(values.marketplaceAuthenticationDemoEntry)
        XCTAssertFalse(values.marketplaceDemonstration)
    }

    func testFooterAndBackdropRemainIndependent() {
        var values = EnvironmentValues()
        values.marketplaceAuthenticationFooter = { AnyView(Text("Weather credit")) }
        values.marketplaceAuthenticationDemoEntry = { AnyView(Text("Explore the demo")) }
        values.marketplaceDemonstration = true
        XCTAssertNotNil(values.marketplaceAuthenticationFooter)
        XCTAssertNil(values.marketplaceAuthenticationBackdrop)

        values.marketplaceAuthenticationBackdrop = { AnyView(Color.black) }
        values.marketplaceAuthenticationFooter = nil
        XCTAssertNil(values.marketplaceAuthenticationFooter)
        XCTAssertNotNil(values.marketplaceAuthenticationBackdrop)
        XCTAssertNotNil(values.marketplaceAuthenticationDemoEntry)
        XCTAssertTrue(values.marketplaceDemonstration)
    }
}
