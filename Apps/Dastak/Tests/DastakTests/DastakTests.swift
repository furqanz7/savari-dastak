import DastakDomain
import XCTest
@testable import Dastak

@MainActor
final class DastakTests: XCTestCase {
    func testApprovedPartnerAccessEnablesModeSwitch() async {
        let model = DastakRootModel(
            accessProvider: StubPartnerAccessProvider(result: .success(.approved))
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
            )
        )

        await model.refreshPartnerAccess()

        XCTAssertEqual(model.rootState.activeRoot, .customer)
        XCTAssertEqual(model.rootState.deliveryPartnerAccess, .unavailable)
        XCTAssertTrue(model.hasLoadedPartnerAccess)
        XCTAssertNotNil(model.errorMessage)
    }

    func testUnapprovedAccountCanOpenPartnerApplicationStatus() {
        let model = DastakRootModel(
            accessProvider: StubPartnerAccessProvider(result: .success(.pending))
        )

        model.select(.deliveryPartner)

        XCTAssertEqual(model.selectedRoot, .deliveryPartner)
        XCTAssertEqual(model.rootState.activeRoot, .customer)
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
