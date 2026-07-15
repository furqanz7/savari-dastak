import Foundation
import MarketplaceFoundation
@testable import MarketplaceInfrastructure

actor FakeAuthenticationClient: AuthenticationClient {
    let restoredRoute: AccountRoute
    private var googleRedirectURL: URL?

    init(restoredRoute: AccountRoute) {
        self.restoredRoute = restoredRoute
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {}
    func signInWithGoogle(idToken: String) async throws {}
    func signInWithGoogle(redirectTo: URL) async throws {
        googleRedirectURL = redirectTo
    }
    func restoreAccount() async throws -> AccountRoute { restoredRoute }
    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {}
    func signOut() async throws {}

    func recordedGoogleRedirectURL() -> URL? {
        googleRedirectURL
    }
}

actor RecordingAuthenticationOperations: SupabaseAuthenticationOperations {
    enum BootstrapError: Error, Sendable {
        case transport
    }

    struct AppleCredentials: Equatable {
        let identityToken: String
        let nonce: String
    }

    struct BootstrapRequest: Equatable {
        let displayName: String
        let phoneNumber: String
        let key: IdempotencyKey
    }

    private let currentAccountID: UUID?
    private let profileAccountID: UUID?
    private let bootstrapResult: AccountBootstrapResult
    private let bootstrapError: BootstrapError?
    private var appleCredentials: AppleCredentials?
    private var googleIDToken: String?
    private var googleRedirectURL: URL?
    private var bootstrapRequest: BootstrapRequest?
    private var profileLookupAccountID: UUID?
    private var signOutCallCount = 0

    init(
        currentAccountID: UUID? = UUID(),
        profileAccountID: UUID? = nil,
        bootstrapResult: AccountBootstrapResult = AccountBootstrapResult(
            accountID: UUID(),
            phoneState: .unverified
        ),
        bootstrapError: BootstrapError? = nil
    ) {
        self.currentAccountID = currentAccountID
        self.profileAccountID = profileAccountID
        self.bootstrapResult = bootstrapResult
        self.bootstrapError = bootstrapError
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        appleCredentials = AppleCredentials(identityToken: identityToken, nonce: nonce)
    }

    func signInWithGoogle(idToken: String) async throws {
        googleIDToken = idToken
    }

    func signInWithGoogle(redirectTo: URL) async throws {
        googleRedirectURL = redirectTo
    }

    func currentAccountID() async -> UUID? {
        currentAccountID
    }

    func accountProfileID(for accountID: UUID) async throws -> UUID? {
        profileLookupAccountID = accountID
        return profileAccountID
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
        if let bootstrapError {
            throw bootstrapError
        }
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

    func recordedGoogleRedirectURL() -> URL? {
        googleRedirectURL
    }

    func recordedBootstrapRequest() -> BootstrapRequest? {
        bootstrapRequest
    }

    func recordedProfileLookupAccountID() -> UUID? {
        profileLookupAccountID
    }

    func recordedSignOutCallCount() -> Int {
        signOutCallCount
    }
}
