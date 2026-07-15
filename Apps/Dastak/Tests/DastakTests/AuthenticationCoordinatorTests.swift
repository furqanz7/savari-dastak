import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import Dastak

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
            try await coordinator.signInWithGoogle(
                configuration: GoogleOAuthConfiguration(
                    reversedClientID: GoogleOAuthConfiguration.notConfiguredClientID
                )
            )
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

        try await coordinator.completeProfile(
            displayName: "Test User",
            phoneNumber: "+919876543210"
        )

        XCTAssertEqual(coordinator.route, .active)
        let bootstrapCallCount = await gateway.bootstrapCallCount()
        XCTAssertEqual(bootstrapCallCount, 1)
    }

    func testProviderExchangeFailureFromActiveRouteResetsToSignedOut() async throws {
        let gateway = FakeAuthenticationClient(
            restoredRoute: .active,
            shouldFailAppleSignIn: true
        )
        let coordinator = AuthenticationCoordinator(client: gateway)

        await coordinator.restore()
        XCTAssertEqual(coordinator.route, .active)

        do {
            try await coordinator.signInWithApple(identityToken: "apple-token", nonce: "nonce")
            XCTFail("Expected the provider exchange to fail")
        } catch {
            XCTAssertEqual(coordinator.route, .signedOut)
        }
    }

    func testProfileLookupFailureAfterProviderExchangeResetsToSignedOut() async throws {
        let gateway = FakeAuthenticationClient(restoredRoute: .active)
        let coordinator = AuthenticationCoordinator(client: gateway)

        await coordinator.restore()
        XCTAssertEqual(coordinator.route, .active)
        await gateway.setRestoreFailure()

        do {
            try await coordinator.signInWithApple(identityToken: "apple-token", nonce: "nonce")
            XCTFail("Expected the profile lookup to fail")
        } catch {
            XCTAssertEqual(coordinator.route, .signedOut)
        }
    }

    func testProfileBootstrapFailureKeepsNeedsProfileRoute() async throws {
        let gateway = FakeAuthenticationClient(
            restoredRoute: .needsProfile,
            shouldFailBootstrap: true
        )
        let coordinator = AuthenticationCoordinator(client: gateway)

        await coordinator.restore()
        XCTAssertEqual(coordinator.route, .needsProfile)

        do {
            try await coordinator.completeProfile(
                displayName: "Test User",
                phoneNumber: "+919876543210"
            )
            XCTFail("Expected profile bootstrap to fail")
        } catch {
            XCTAssertEqual(coordinator.route, .needsProfile)
        }
    }

    func testProfileRestoreFailureAfterBootstrapKeepsNeedsProfileRoute() async throws {
        let gateway = FakeAuthenticationClient(restoredRoute: .needsProfile)
        let coordinator = AuthenticationCoordinator(client: gateway)

        await coordinator.restore()
        XCTAssertEqual(coordinator.route, .needsProfile)
        await gateway.setRestoreFailure()

        do {
            try await coordinator.completeProfile(
                displayName: "Test User",
                phoneNumber: "+919876543210"
            )
            XCTFail("Expected the post-bootstrap profile restore to fail")
        } catch {
            XCTAssertEqual(coordinator.route, .needsProfile)
        }
    }

    func testProfileCompletionRejectsMalformedE164BeforeCallingClient() async throws {
        let gateway = FakeAuthenticationClient(restoredRoute: .needsProfile)
        let coordinator = AuthenticationCoordinator(client: gateway)

        await coordinator.restore()
        XCTAssertEqual(coordinator.route, .needsProfile)

        do {
            try await coordinator.completeProfile(
                displayName: "Test User",
                phoneNumber: "+91 9876543210"
            )
            XCTFail("Expected malformed E.164 input to fail")
        } catch let error as AuthenticationClientError {
            XCTAssertEqual(error, .invalidE164PhoneNumber)
        }

        let bootstrapCallCount = await gateway.bootstrapCallCount()
        XCTAssertEqual(bootstrapCallCount, 0)
        XCTAssertEqual(coordinator.route, .needsProfile)
    }
}

private actor FakeAuthenticationClient: AuthenticationClient {
    let restoredRoute: AccountRoute
    private let shouldFailAppleSignIn: Bool
    private let shouldFailBootstrap: Bool
    private var shouldFailRestore = false
    private var googleCalls = 0
    private var bootstrapCalls = 0

    init(
        restoredRoute: AccountRoute,
        shouldFailAppleSignIn: Bool = false,
        shouldFailBootstrap: Bool = false
    ) {
        self.restoredRoute = restoredRoute
        self.shouldFailAppleSignIn = shouldFailAppleSignIn
        self.shouldFailBootstrap = shouldFailBootstrap
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        guard !shouldFailAppleSignIn else {
            throw TestAuthenticationError.providerExchangeFailed
        }
    }

    func signInWithGoogle(idToken: String) async throws {
        googleCalls += 1
    }

    func signInWithGoogle(redirectTo: URL) async throws {
        googleCalls += 1
    }

    func restoreAccount() async throws -> AccountRoute {
        guard !shouldFailRestore else {
            throw TestAuthenticationError.profileLookupFailed
        }
        return restoredRoute
    }

    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {
        bootstrapCalls += 1
        guard !shouldFailBootstrap else {
            throw TestAuthenticationError.profileBootstrapFailed
        }
    }

    func signOut() async throws {}

    func googleSignInCallCount() -> Int {
        googleCalls
    }

    func bootstrapCallCount() -> Int {
        bootstrapCalls
    }

    func setRestoreFailure() {
        shouldFailRestore = true
    }
}

private enum TestAuthenticationError: Error, Sendable {
    case providerExchangeFailed
    case profileLookupFailed
    case profileBootstrapFailed
}
