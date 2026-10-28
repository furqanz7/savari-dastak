import XCTest

final class DastakMerchantTests: XCTestCase {
    func testPrivacyManifestIsPackagedInApplicationBundle() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, Bundle.main.bundleURL.standardizedFileURL)
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        let entries = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = try entries.map { try XCTUnwrap($0["NSPrivacyCollectedDataType"] as? String) }
        XCTAssertEqual(types.count, 17)
        XCTAssertEqual(Set(types).count, types.count)
        XCTAssertTrue(types.contains("NSPrivacyCollectedDataTypeOtherDataTypes"))
        XCTAssertFalse(types.contains("NSPrivacyCollectedDataTypePurchaseHistory"))
        XCTAssertFalse(types.contains("NSPrivacyCollectedDataTypeSearchHistory"))
        for entry in entries {
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                           ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
        let APIs = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = try XCTUnwrap(APIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }
}
