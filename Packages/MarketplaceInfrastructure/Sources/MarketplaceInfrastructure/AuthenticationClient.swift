import Foundation
import MarketplaceFoundation
import Supabase

public enum AccountRoute: Equatable, Sendable {
    case signedOut
    case needsProfile
    case active
}

public protocol AuthenticationClient: Sendable {
    func signInWithApple(identityToken: String, nonce: String) async throws
    func signInWithGoogle(idToken: String) async throws
    func restoreAccount() async throws -> AccountRoute
    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws
    func signOut() async throws
}

public enum AuthenticationClientError: Error, Equatable, Sendable {
    case googleOAuthNotConfigured
    case unexpectedPhoneVerificationState
}

public struct GoogleOAuthConfiguration: Equatable, Sendable {
    public static let notConfiguredClientID = "com.googleusercontent.apps.not-configured"

    public let reversedClientID: String

    public init(reversedClientID: String) {
        self.reversedClientID = reversedClientID
    }

    public init(bundle: Bundle) {
        let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = urlTypes?
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }
        reversedClientID = schemes?
            .first(where: { $0.hasPrefix("com.googleusercontent.apps.") })
            ?? Self.notConfiguredClientID
    }

    public func validatedReversedClientID() throws -> String {
        let normalized = reversedClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalized.isEmpty,
            normalized != Self.notConfiguredClientID,
            normalized.hasPrefix("com.googleusercontent.apps.")
        else {
            throw AuthenticationClientError.googleOAuthNotConfigured
        }
        return normalized
    }
}

protocol SupabaseAuthenticationOperations: Sendable {
    func signInWithApple(identityToken: String, nonce: String) async throws
    func signInWithGoogle(idToken: String) async throws
    func hasProviderSession() async -> Bool
    func hasAccountProfile() async throws -> Bool
    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws -> AccountBootstrapResult
    func signOut() async throws
}

public struct SupabaseAuthenticationClient: AuthenticationClient {
    private let operations: any SupabaseAuthenticationOperations

    public init(configuration: BackendConfiguration) {
        operations = LiveOperations(configuration: configuration)
    }

    init(operations: any SupabaseAuthenticationOperations) {
        self.operations = operations
    }

    public func signInWithApple(identityToken: String, nonce: String) async throws {
        try await operations.signInWithApple(identityToken: identityToken, nonce: nonce)
    }

    public func signInWithGoogle(idToken: String) async throws {
        try await operations.signInWithGoogle(idToken: idToken)
    }

    public func restoreAccount() async throws -> AccountRoute {
        guard await operations.hasProviderSession() else {
            return .signedOut
        }
        return try await operations.hasAccountProfile() ? .active : .needsProfile
    }

    public func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {
        let result = try await operations.bootstrapAccount(
            displayName: displayName,
            phoneNumber: phoneNumber,
            key: key
        )
        guard result.phoneState == .unverified else {
            throw AuthenticationClientError.unexpectedPhoneVerificationState
        }
    }

    public func signOut() async throws {
        try await operations.signOut()
    }
}

private extension SupabaseAuthenticationClient {
    actor LiveOperations: SupabaseAuthenticationOperations {
        private struct AccountIdentity: Decodable {
            let id: UUID
        }

        private let supabaseClient: SupabaseClient

        init(configuration: BackendConfiguration) {
            supabaseClient = SupabaseClient(
                supabaseURL: configuration.supabaseURL,
                supabaseKey: configuration.publishableKey
            )
        }

        func signInWithApple(identityToken: String, nonce: String) async throws {
            try await supabaseClient.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: nonce
                )
            )
        }

        func signInWithGoogle(idToken: String) async throws {
            try await supabaseClient.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken
                )
            )
        }

        func hasProviderSession() async -> Bool {
            do {
                _ = try await supabaseClient.auth.session
                return true
            } catch AuthError.sessionMissing {
                return false
            } catch {
                return false
            }
        }

        func hasAccountProfile() async throws -> Bool {
            let accounts: [AccountIdentity] = try await supabaseClient
                .from("accounts")
                .select("id")
                .limit(1)
                .execute()
                .value
            return !accounts.isEmpty
        }

        func bootstrapAccount(
            displayName: String,
            phoneNumber: String,
            key: IdempotencyKey
        ) async throws -> AccountBootstrapResult {
            try await supabaseClient.functions.invoke(
                "bootstrap-account",
                options: FunctionInvokeOptions(
                    headers: ["X-Idempotency-Key": key.rawValue],
                    body: AccountBootstrapRequest(
                        displayName: displayName,
                        phoneNumber: phoneNumber
                    )
                )
            )
        }

        func signOut() async throws {
            try await supabaseClient.auth.signOut()
        }
    }
}
