import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import Savari

@MainActor
final class AuthenticationCoordinatorTests: XCTestCase {
    func testNewProviderSessionMustCompletePhoneBeforeActiveRoute() async throws {
        let gateway = FakeAuthenticationClient(restoredRoute: .needsProfile)
        let coordinator = AuthenticationCoordinator(client: gateway)

        await coordinator.restore()

        XCTAssertEqual(coordinator.route, .needsProfile)
    }

    func testExistingBootstrappedAccountRestoresActiveRoute() async throws {
        let gateway = FakeAuthenticationClient(restoredRoute: .active)
        let coordinator = AuthenticationCoordinator(client: gateway)

        await coordinator.restore()

        XCTAssertEqual(coordinator.route, .active)
    }

    func testGooglePlaceholderFailsBeforeTokenReachesClient() async throws {
        let gateway = FakeAuthenticationClient(restoredRoute: .needsProfile)
        let coordinator = AuthenticationCoordinator(client: gateway)

        do {
            try await coordinator.signInWithGoogle(idToken: "google-token")
            XCTFail("Expected placeholder Google OAuth configuration to fail closed")
        } catch let error as AuthenticationClientError {
            XCTAssertEqual(error, .googleOAuthNotConfigured)
        }

        let callCount = await gateway.googleSignInCallCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(coordinator.route, .signedOut)
    }

    func testProfileCompletionUsesServerRouteBeforeBecomingActive() async throws {
        let gateway = FakeAuthenticationClient(restoredRoute: .active)
        let coordinator = AuthenticationCoordinator(client: gateway)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "profile-123"))

        try await coordinator.completeProfile(
            displayName: "Test User",
            phoneNumber: "+919876543210",
            key: key
        )

        XCTAssertEqual(coordinator.route, .active)
        let bootstrapCallCount = await gateway.bootstrapCallCount()
        XCTAssertEqual(bootstrapCallCount, 1)
    }
}

private actor FakeAuthenticationClient: AuthenticationClient {
    let restoredRoute: AccountRoute
    private var googleCalls = 0
    private var bootstrapCalls = 0

    init(restoredRoute: AccountRoute) {
        self.restoredRoute = restoredRoute
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {}

    func signInWithGoogle(idToken: String) async throws {
        googleCalls += 1
    }

    func restoreAccount() async throws -> AccountRoute {
        restoredRoute
    }

    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {
        bootstrapCalls += 1
    }

    func signOut() async throws {}

    func googleSignInCallCount() -> Int {
        googleCalls
    }

    func bootstrapCallCount() -> Int {
        bootstrapCalls
    }
}
