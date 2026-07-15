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
    func signInWithGoogle(redirectTo: URL) async throws
    func restoreAccount() async throws -> AccountRoute
    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws
    func signOut() async throws
}

public enum AuthenticationClientError: Error, Equatable, Sendable {
    case bootstrapAmbiguousFailure
    case bootstrapRejected(statusCode: Int, code: String?, message: String)
    case invalidE164PhoneNumber
    case invalidProfileDisplayName
    case oauthCallbackNotConfigured
    case unexpectedPhoneVerificationState
}

public struct OAuthCallbackConfiguration: Equatable, Sendable {
    public let scheme: String

    public init(scheme: String) {
        self.scheme = scheme
    }

    public init(bundle: Bundle) {
        let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = urlTypes?
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }
        scheme = schemes?.first ?? ""
    }

    public func validatedScheme() throws -> String {
        let normalized = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalized.isEmpty,
            URL(string: "\(normalized)://login-callback")?.scheme == normalized
        else {
            throw AuthenticationClientError.oauthCallbackNotConfigured
        }
        return normalized
    }

    public func callbackURL() throws -> URL {
        let scheme = try validatedScheme()
        guard let url = URL(string: "\(scheme)://login-callback") else {
            throw AuthenticationClientError.oauthCallbackNotConfigured
        }
        return url
    }
}

protocol SupabaseAuthenticationOperations: Sendable {
    func signInWithApple(identityToken: String, nonce: String) async throws
    func signInWithGoogle(idToken: String) async throws
    func signInWithGoogle(redirectTo: URL) async throws
    func currentAccountID() async -> UUID?
    func accountProfileID(for accountID: UUID) async throws -> UUID?
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

    public func signInWithGoogle(redirectTo: URL) async throws {
        try await operations.signInWithGoogle(redirectTo: redirectTo)
    }

    public func restoreAccount() async throws -> AccountRoute {
        guard let accountID = await operations.currentAccountID() else {
            return .signedOut
        }
        guard let profileAccountID = try await operations.accountProfileID(for: accountID) else {
            return .needsProfile
        }
        return profileAccountID == accountID ? .active : .needsProfile
    }

    public func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {
        let validatedPhoneNumber = try E164PhoneNumber(phoneNumber).rawValue
        let result: AccountBootstrapResult
        do {
            result = try await operations.bootstrapAccount(
                displayName: displayName,
                phoneNumber: validatedPhoneNumber,
                key: key
            )
        } catch let error as AuthenticationClientError {
            throw error
        } catch let error as FunctionsError {
            switch error {
            case let .httpError(statusCode, data):
                let payload = try? JSONDecoder().decode(BootstrapErrorEnvelope.self, from: data)
                throw AuthenticationClientError.bootstrapRejected(
                    statusCode: statusCode,
                    code: payload?.error.code,
                    message: payload?.error.message ?? "Profile completion was rejected."
                )
            case .relayError:
                throw AuthenticationClientError.bootstrapAmbiguousFailure
            }
        } catch {
            throw AuthenticationClientError.bootstrapAmbiguousFailure
        }
        guard result.phoneState == .unverified else {
            throw AuthenticationClientError.unexpectedPhoneVerificationState
        }
    }

    public func signOut() async throws {
        try await operations.signOut()
    }
}

private struct BootstrapErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }

    let error: Payload
}

extension SupabaseAuthenticationClient {
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

        init(
            configuration: BackendConfiguration,
            session: URLSession,
            accessToken: String
        ) {
            supabaseClient = SupabaseClient(
                supabaseURL: configuration.supabaseURL,
                supabaseKey: configuration.publishableKey,
                options: SupabaseClientOptions(
                    auth: .init(accessToken: { accessToken }),
                    global: .init(session: session)
                )
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

        func signInWithGoogle(redirectTo: URL) async throws {
            try await supabaseClient.auth.signInWithOAuth(
                provider: .google,
                redirectTo: redirectTo
            )
        }

        func currentAccountID() async -> UUID? {
            do {
                return try await supabaseClient.auth.session.user.id
            } catch AuthError.sessionMissing {
                return nil
            } catch {
                return nil
            }
        }

        func accountProfileID(for accountID: UUID) async throws -> UUID? {
            let accounts: [AccountIdentity] = try await supabaseClient
                .from("accounts")
                .select("id")
                .eq("id", value: accountID.uuidString)
                .limit(1)
                .execute()
                .value
            return accounts.first?.id
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
