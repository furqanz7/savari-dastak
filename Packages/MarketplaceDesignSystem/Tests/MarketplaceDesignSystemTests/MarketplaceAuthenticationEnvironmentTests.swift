import SwiftUI
import XCTest
@testable import MarketplaceDesignSystem

@MainActor
final class MarketplaceAuthenticationEnvironmentTests: XCTestCase {
    func testAuthenticationAdditionsAreOptIn() {
        let values = EnvironmentValues()
        XCTAssertNil(values.marketplaceAuthenticationBackdrop)
        XCTAssertNil(values.marketplaceAuthenticationFooter)
    }

    func testFooterAndBackdropRemainIndependent() {
        var values = EnvironmentValues()
        values.marketplaceAuthenticationFooter = { AnyView(Text("Weather credit")) }
        XCTAssertNotNil(values.marketplaceAuthenticationFooter)
        XCTAssertNil(values.marketplaceAuthenticationBackdrop)

        values.marketplaceAuthenticationBackdrop = { AnyView(Color.black) }
        values.marketplaceAuthenticationFooter = nil
        XCTAssertNil(values.marketplaceAuthenticationFooter)
        XCTAssertNotNil(values.marketplaceAuthenticationBackdrop)
    }
}
