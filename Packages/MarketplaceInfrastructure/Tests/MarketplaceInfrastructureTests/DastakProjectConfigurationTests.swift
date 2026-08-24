import Foundation
import XCTest

final class DastakProjectConfigurationTests: XCTestCase {
    func testUniversalAppsDeclareSupportedOrientations() throws {
        let infoPlistURL = repositoryRoot
            .appendingPathComponent("Apps/Dastak/Supporting/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        let infoPlist = try XCTUnwrap(propertyList as? [String: Any])

        let iPhoneOrientations = try XCTUnwrap(
            infoPlist["UISupportedInterfaceOrientations"] as? [String]
        )
        let iPadOrientations = try XCTUnwrap(
            infoPlist["UISupportedInterfaceOrientations~ipad"] as? [String]
        )

        assertOrientations(
            iPhoneOrientations,
            equal: [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight"
            ]
        )
        assertOrientations(
            iPadOrientations,
            equal: [
                "UIInterfaceOrientationPortrait",
                "UIInterfaceOrientationPortraitUpsideDown",
                "UIInterfaceOrientationLandscapeLeft",
                "UIInterfaceOrientationLandscapeRight"
            ]
        )
    }

    func testCustomerLegalLinksUseFirstPartyHTTPSPages() throws {
        let defaultsURL = repositoryRoot
            .appendingPathComponent("Apps/Dastak/Configuration/Defaults.xcconfig")
        let defaults = try String(contentsOf: defaultsURL, encoding: .utf8)

        XCTAssertTrue(defaults.contains("MARKETPLACE_PRIVACY_POLICY_URL = https:/$()/dastak-customer.vercel.app/privacy"))
        XCTAssertTrue(defaults.contains("MARKETPLACE_TERMS_URL = https:/$()/dastak-customer.vercel.app/terms"))
        XCTAssertTrue(defaults.contains("MARKETPLACE_SUPPORT_URL = https:/$()/dastak-customer.vercel.app/support"))
        XCTAssertFalse(defaults.localizedCaseInsensitiveContains("mailto:"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func assertOrientations(
        _ actual: [String],
        equal expected: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(actual), expected, file: file, line: line)
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    }
}
