import DastakDomain
import MarketplaceFoundation
import UIKit
import XCTest
@testable import Dastak

@MainActor
final class DastakTests: XCTestCase {
    func testHomeWidgetLinksReachExistingCustomerRoutes() {
        for destination in DastakWidgetDestination.allCases {
            XCTAssertEqual(DastakAppAction(url: destination.url)?.rawValue, destination.rawValue,
                           "A widget must open its advertised screen through the validated customer router")
        }
    }

    func testPolishedControlSymbolsExistOnIOS() {
        for action in DastakAppAction.allCases {
            XCTAssertNotNil(UIImage(systemName: action.controlSymbol), "Missing symbol for \(action.rawValue)")
        }
    }
    func testAppIconQuickActionsIncludeSearchAndKeepExactlyFourEntries() throws {
        let items = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.compactMap { $0["UIApplicationShortcutItemTitle"] as? String },
                       ["Search", "Grocery", "Food", "Track Order"])
        XCTAssertEqual(items.compactMap { $0["UIApplicationShortcutItemType"] as? String },
                       ["search", "grocery", "food", "tracking"].map { "com.dastak.app.quick.\($0)" })
        XCTAssertEqual(items.first?["UIApplicationShortcutItemIconSymbolName"] as? String, "magnifyingglass")
    }

    func testSearchShortcutIsExportedAndDiscoverable() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Metadata.appintents/extract.actionsdata")
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let shortcuts = try XCTUnwrap(metadata["autoShortcuts"] as? [[String: Any]])
        XCTAssertEqual(shortcuts.count, 5)
        XCTAssertEqual(shortcuts.first?["actionIdentifier"] as? String, "SearchDastakIntent")
        XCTAssertEqual((shortcuts.first?["shortTitle"] as? [String: Any])?["key"] as? String, "Search")
        let actions = try XCTUnwrap(metadata["actions"] as? [String: [String: Any]])
        let search = try XCTUnwrap(actions["SearchDastakIntent"])
        XCTAssertEqual(search["isDiscoverable"] as? Bool, true)
        XCTAssertEqual((search["visibilityMetadata"] as? [String: Any])?["assistantOnly"] as? Bool, false)
        XCTAssertEqual((search["parameters"] as? [Any])?.count, 0)
    }

    func testSearchShortcutKeepsStableIdentifierAndSpecificDiscoveryPhrases() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Metadata.appintents/extract.actionsdata")
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let shortcuts = try XCTUnwrap(metadata["autoShortcuts"] as? [[String: Any]])
        let search = try XCTUnwrap(shortcuts.first { $0["actionIdentifier"] as? String == "SearchDastakIntent" })
        let phrases = try XCTUnwrap(search["phraseTemplates"] as? [[String: Any]]).compactMap { $0["key"] as? String }
        XCTAssertTrue(phrases.contains("Open search in ${applicationName}"))
        XCTAssertTrue(phrases.contains("Search products in ${applicationName}"))
        XCTAssertEqual(Set(shortcuts.compactMap { $0["actionIdentifier"] as? String }),
            ["SearchDastakIntent", "OpenDastakGroceryIntent", "OpenDastakFoodIntent", "OpenDastakBasketIntent", "TrackDastakOrderIntent"])
    }

    func testPrivacyManifestIsPackagedInApplicationBundle() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, Bundle.main.bundleURL.standardizedFileURL)
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        XCTAssertNotNil(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let APIs = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = try XCTUnwrap(APIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }

    func testMerchantAppRouteUsesInstalledAppThenAppStoreFallback() {
        XCTAssertEqual(
            DastakMerchantAppRoute.destination(isAppInstalled: true).scheme,
            "com.dastak.merchant"
        )
        XCTAssertEqual(
            DastakMerchantAppRoute.destination(isAppInstalled: false).scheme,
            "itms-apps"
        )
    }

    func testApprovedPartnerAccessEnablesModeSwitch() async {
        let model = DastakRootModel(
            accessProvider: StubPartnerAccessProvider(result: .success(.approved)),
            selectionStore: StubRootSelectionStore()
        )

        await model.refreshPartnerAccess()
        model.select(.deliveryPartner)

        XCTAssertEqual(model.selectedRoot, .deliveryPartner)
        XCTAssertEqual(model.rootState.activeRoot, .deliveryPartner)
        XCTAssertTrue(model.hasLoadedPartnerAccess)
        XCTAssertNil(model.errorMessage)
    }

    func testPartnerAccessFailureRemainsInCustomerMode() async {
        let model = DastakRootModel(
            accessProvider: StubPartnerAccessProvider(
                result: .failure(TestAccessError.unavailable)
            ),
            selectionStore: StubRootSelectionStore()
        )

        await model.refreshPartnerAccess()

        XCTAssertEqual(model.rootState.activeRoot, .customer)
        XCTAssertEqual(model.rootState.deliveryPartnerAccess, .unavailable)
        XCTAssertTrue(model.hasLoadedPartnerAccess)
        XCTAssertNotNil(model.errorMessage)
    }

    func testUnapprovedAccountCanOpenPartnerApplicationStatus() {
        let model = DastakRootModel(
            accessProvider: StubPartnerAccessProvider(result: .success(.pending)),
            selectionStore: StubRootSelectionStore()
        )

        model.select(.deliveryPartner)

        XCTAssertEqual(model.selectedRoot, .deliveryPartner)
        XCTAssertEqual(model.rootState.activeRoot, .customer)
    }

    func testRestoresDeliveryPartnerModeAfterRelaunch() async {
        let store = StubRootSelectionStore(storedRoot: .deliveryPartner)
        let model = DastakRootModel(
            accessProvider: StubPartnerAccessProvider(result: .success(.approved)),
            selectionStore: store
        )

        XCTAssertEqual(model.selectedRoot, .deliveryPartner)

        await model.refreshPartnerAccess()

        XCTAssertEqual(model.selectedRoot, .deliveryPartner)
        XCTAssertEqual(model.rootState.activeRoot, .deliveryPartner)
    }

    func testRestoresCustomerModeAfterRelaunch() {
        let model = DastakRootModel(
            accessProvider: StubPartnerAccessProvider(result: .success(.approved)),
            selectionStore: StubRootSelectionStore(storedRoot: .customer)
        )

        XCTAssertEqual(model.selectedRoot, .customer)
        XCTAssertEqual(model.rootState.activeRoot, .customer)
    }

    func testModeSwitchesArePersistedImmediately() {
        let store = StubRootSelectionStore()
        let model = DastakRootModel(
            accessProvider: StubPartnerAccessProvider(result: .success(.approved)),
            selectionStore: store
        )

        model.select(.deliveryPartner)
        XCTAssertEqual(store.storedRoot, .deliveryPartner)

        model.select(.customer)
        XCTAssertEqual(store.storedRoot, .customer)
    }
}

@MainActor
private final class StubRootSelectionStore: DastakRootSelectionStoring {
    var storedRoot: DastakAppRoot?

    init(storedRoot: DastakAppRoot? = nil) {
        self.storedRoot = storedRoot
    }

    func load() -> DastakAppRoot? {
        storedRoot
    }

    func save(_ root: DastakAppRoot) {
        storedRoot = root
    }
}

private struct StubPartnerAccessProvider: DeliveryPartnerAccessProviding {
    let result: Result<DeliveryPartnerAccess, TestAccessError>

    func currentAccess() async throws -> DeliveryPartnerAccess {
        try result.get()
    }
}

private enum TestAccessError: Error {
    case unavailable
}
