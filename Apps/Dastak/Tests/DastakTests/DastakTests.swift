import DastakDomain
import XCTest
@testable import Dastak

@MainActor
final class DastakTests: XCTestCase {
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
