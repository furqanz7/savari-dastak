import XCTest
@testable import DastakDomain

final class DastakAppRootStateTests: XCTestCase {
    func testMainAppDefaultsToCustomer() {
        let state = DastakAppRootState(application: .customerAndPartner)

        XCTAssertEqual(state.activeRoot, .customer)
        XCTAssertEqual(state.availableRoots, [.customer])
    }

    func testApprovedPartnerCanEnterPartnerRoot() throws {
        var state = DastakAppRootState(
            application: .customerAndPartner,
            deliveryPartnerAccess: .approved
        )

        try state.select(.deliveryPartner)

        XCTAssertEqual(state.activeRoot, .deliveryPartner)
        XCTAssertEqual(state.availableRoots, [.customer, .deliveryPartner])
    }

    func testUnapprovedPartnerCannotEnterPartnerRoot() {
        var state = DastakAppRootState(
            application: .customerAndPartner,
            deliveryPartnerAccess: .pending
        )

        XCTAssertThrowsError(try state.select(.deliveryPartner)) { error in
            XCTAssertEqual(error as? DastakAppRootError, .accessDenied)
        }
        XCTAssertEqual(state.activeRoot, .customer)
    }

    func testPartnerApprovalRemovalReturnsToCustomer() throws {
        var state = DastakAppRootState(
            application: .customerAndPartner,
            deliveryPartnerAccess: .approved
        )
        try state.select(.deliveryPartner)

        state.updateDeliveryPartnerAccess(.suspended)

        XCTAssertEqual(state.activeRoot, .customer)
        XCTAssertEqual(state.availableRoots, [.customer])
    }

    func testMainAppCannotEnterMerchantOrAdminRoots() {
        var state = DastakAppRootState(application: .customerAndPartner)

        XCTAssertThrowsError(try state.select(.merchant))
        XCTAssertThrowsError(try state.select(.admin))
        XCTAssertEqual(state.activeRoot, .customer)
    }

    func testDedicatedAppsExposeOnlyTheirOwnRoot() {
        let merchant = DastakAppRootState(application: .merchant)
        let admin = DastakAppRootState(application: .admin)

        XCTAssertEqual(merchant.activeRoot, .merchant)
        XCTAssertEqual(merchant.availableRoots, [.merchant])
        XCTAssertEqual(admin.activeRoot, .admin)
        XCTAssertEqual(admin.availableRoots, [.admin])
    }
}
