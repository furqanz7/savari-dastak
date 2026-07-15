import Foundation
import XCTest
@testable import MarketplaceInfrastructure
import MarketplaceFoundation

final class BackendConfigurationTests: XCTestCase {
    func testConfigurationRetainsProductAndSupabaseValues() throws {
        let url = try XCTUnwrap(URL(string: "https://example.supabase.co"))
        let configuration = BackendConfiguration(
            product: "test-product",
            supabaseURL: url,
            publishableKey: "publishable-key"
        )

        XCTAssertEqual(configuration.product, "test-product")
        XCTAssertEqual(configuration.supabaseURL, url)
        XCTAssertEqual(configuration.publishableKey, "publishable-key")
    }
}
