import Foundation
import XCTest

final class DastakProjectConfigurationTests: XCTestCase {
    func testCustomerReleaseDoesNotDeclareOnlinePaymentSDKConfiguration() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("Apps/Dastak/Supporting/CustomerPartner-Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertNil(info["DastakRazorpayPaymentMode"])
        let urlTypes = try XCTUnwrap(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertFalse(schemes.contains(where: { $0.hasPrefix("razorpay-") }))
        XCTAssertEqual(info["LSApplicationQueriesSchemes"] as? [String], ["com.dastak.merchant"])
        let package = try String(contentsOf: repositoryRoot.appendingPathComponent("Packages/DastakUI/Package.swift"), encoding: .utf8)
        XCTAssertFalse(package.contains("razorpay-customui-pod"))
        XCTAssertFalse(package.contains("RazorpayCustomUI"))
    }

    func testCustomerPrivacyManifestCoversLaunchDataWithoutTracking() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("Apps/Dastak/Supporting/PrivacyInfo.xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        let entries = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = try entries.map { try XCTUnwrap($0["NSPrivacyCollectedDataType"] as? String) }
        XCTAssertEqual(types.count, Set(types).count)
        XCTAssertEqual(Set(types), Set([
            "CoarseLocation", "Name", "EmailAddress", "PhoneNumber", "PhysicalAddress", "PreciseLocation",
            "PhotosorVideos", "CustomerSupport", "OtherUserContent", "UserID", "DeviceID", "PurchaseHistory",
            "PaymentInfo", "OtherFinancialInfo", "ProductInteraction", "PerformanceData", "OtherDiagnosticData"
        ].map { "NSPrivacyCollectedDataType" + $0 }))
        for entry in entries {
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            let type = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String)
            let purposes = try XCTUnwrap(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])
            let expected = type == "NSPrivacyCollectedDataTypePurchaseHistory"
                ? ["NSPrivacyCollectedDataTypePurposeAppFunctionality", "NSPrivacyCollectedDataTypePurposeProductPersonalization"]
                : ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
            XCTAssertEqual(Set(purposes), Set(expected))
        }
    }

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

    func testMerchantManifestMatchesApprovedOperationalCollectionWithoutCustomerPersonalization() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Apps/Dastak/Supporting/Merchant/PrivacyInfo.xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        let entries = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = try entries.map { try XCTUnwrap($0["NSPrivacyCollectedDataType"] as? String) }
        XCTAssertEqual(types.count, Set(types).count)
        XCTAssertEqual(Set(types), Set([
            "CoarseLocation", "Name", "EmailAddress", "PhoneNumber", "PhysicalAddress", "PreciseLocation",
            "PhotosorVideos", "CustomerSupport", "OtherUserContent", "UserID", "DeviceID", "OtherDataTypes",
            "PaymentInfo", "OtherFinancialInfo", "ProductInteraction", "PerformanceData", "OtherDiagnosticData"
        ].map { "NSPrivacyCollectedDataType" + $0 }))
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

    func testOnlyMerchantTargetPackagesTheMerchantSpecificManifest() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Apps/Dastak/Dastak.xcodeproj/project.pbxproj"))
        let project = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let objects = try XCTUnwrap(project["objects"] as? [String: [String: Any]])
        var merchantCount = 0
        for target in objects.values where target["isa"] as? String == "PBXNativeTarget" {
            let name = try XCTUnwrap(target["name"] as? String)
            let phases = try XCTUnwrap(target["buildPhases"] as? [String])
            let paths = phases.compactMap { objects[$0] }
                .filter { $0["isa"] as? String == "PBXResourcesBuildPhase" }
                .flatMap { $0["files"] as? [String] ?? [] }
                .compactMap { objects[$0]?["fileRef"] as? String }
                .compactMap { objects[$0]?["path"] as? String }
                .filter { $0.hasSuffix("PrivacyInfo.xcprivacy") }
            if name == "DastakMerchant" {
                merchantCount += 1
                XCTAssertEqual(paths, ["Merchant/PrivacyInfo.xcprivacy"])
            } else {
                XCTAssertFalse(paths.contains("Merchant/PrivacyInfo.xcprivacy"), name)
                if name == "Dastak" || name == "DastakAdmin" {
                    XCTAssertEqual(paths, ["PrivacyInfo.xcprivacy"], name)
                }
            }
        }
        XCTAssertEqual(merchantCount, 1)
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
