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
