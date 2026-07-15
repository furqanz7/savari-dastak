import Foundation
import MarketplaceFoundation
@testable import MarketplaceInfrastructure

actor FakeAuthenticationClient: AuthenticationClient {
    let restoredRoute: AccountRoute

    init(restoredRoute: AccountRoute) {
        self.restoredRoute = restoredRoute
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {}
    func signInWithGoogle(idToken: String) async throws {}
    func restoreAccount() async throws -> AccountRoute { restoredRoute }
    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {}
    func signOut() async throws {}
}

actor RecordingAuthenticationOperations: SupabaseAuthenticationOperations {
    struct AppleCredentials: Equatable {
        let identityToken: String
        let nonce: String
    }

    struct BootstrapRequest: Equatable {
        let displayName: String
        let phoneNumber: String
        let key: IdempotencyKey
    }

    private let providerSessionExists: Bool
    private let accountExists: Bool
    private let bootstrapResult: AccountBootstrapResult
    private var appleCredentials: AppleCredentials?
    private var googleIDToken: String?
    private var bootstrapRequest: BootstrapRequest?
    private var signOutCallCount = 0

    init(
        providerSessionExists: Bool = true,
        accountExists: Bool = false,
        bootstrapResult: AccountBootstrapResult = AccountBootstrapResult(
            accountID: UUID(),
            phoneState: .unverified
        )
    ) {
        self.providerSessionExists = providerSessionExists
        self.accountExists = accountExists
        self.bootstrapResult = bootstrapResult
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        appleCredentials = AppleCredentials(identityToken: identityToken, nonce: nonce)
    }

    func signInWithGoogle(idToken: String) async throws {
        googleIDToken = idToken
    }

    func hasProviderSession() async -> Bool {
        providerSessionExists
    }

    func hasAccountProfile() async throws -> Bool {
        accountExists
    }

    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws -> AccountBootstrapResult {
        bootstrapRequest = BootstrapRequest(
            displayName: displayName,
            phoneNumber: phoneNumber,
            key: key
        )
        return bootstrapResult
    }

    func signOut() async throws {
        signOutCallCount += 1
    }

    func recordedAppleCredentials() -> AppleCredentials? {
        appleCredentials
    }

    func recordedGoogleIDToken() -> String? {
        googleIDToken
    }

    func recordedBootstrapRequest() -> BootstrapRequest? {
        bootstrapRequest
    }

    func recordedSignOutCallCount() -> Int {
        signOutCallCount
    }
}
