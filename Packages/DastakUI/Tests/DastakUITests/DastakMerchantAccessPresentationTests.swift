import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakMerchantAccessPresentationTests: XCTestCase {
    func testEveryMerchantAccessStateHasOnePresentation() {
        XCTAssertEqual(resolve(.accessDenied, .notApplied), .application)
        XCTAssertEqual(resolve(.accessDenied, .rejected), .application)
        XCTAssertEqual(resolve(.accessDenied, .pending), .pending)
        XCTAssertEqual(resolve(.accessDenied, .approved), .approved)
        XCTAssertEqual(resolve(.pendingApproval, .notApplied), .pending)
        XCTAssertEqual(resolve(.suspended, .approved), .suspended)
    }

    func testLoadingAndFailureAreExplicit() {
        XCTAssertEqual(
            DastakMerchantAccessPresentation.resolve(
                route: .accessDenied,
                onboardingState: .notApplied,
                isLoading: true,
                hasLoadError: false
            ),
            .loading
        )
        XCTAssertEqual(
            DastakMerchantAccessPresentation.resolve(
                route: .accessDenied,
                onboardingState: .notApplied,
                isLoading: false,
                hasLoadError: true
            ),
            .loadFailure
        )
    }

    private func resolve(
        _ route: AccountRoute,
        _ onboardingState: MerchantOnboardingState
    ) -> DastakMerchantAccessPresentation {
        .resolve(
            route: route,
            onboardingState: onboardingState,
            isLoading: false,
            hasLoadError: false
        )
    }
}
