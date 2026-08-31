import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
import MarketplaceFoundation
import Supabase

public enum AccountRoute: String, Codable, Equatable, Sendable {
    case signedOut = "signed_out"
    case needsProfile = "needs_profile"
    case pendingApproval = "pending_approval"
    case suspended
    case accessDenied = "access_denied"
    case active
}

public enum MarketplaceApplicationAccess: String, Codable, Equatable, Sendable {
    case profileOnly = "profile_only"
    case dastakCustomer = "customer"
    case dastakMerchant = "merchant"
    case dastakDelivery = "delivery"
    case dastakAdmin = "admin"
}

public protocol AuthenticationClient: Sendable {
    func signInWithApple(identityToken: String, nonce: String) async throws
    func signInWithGoogle(idToken: String) async throws
    func signInWithGoogle(redirectTo: URL) async throws
    func suggestedDisplayName() async -> String?
    func restoreAccount() async throws -> AccountRoute
    func requestPhoneVerification(phoneNumber: String) async throws
    func verifyPhone(phoneNumber: String, code: String) async throws
    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws
    func signOut() async throws
}

public extension AuthenticationClient {
    func suggestedDisplayName() async -> String? { nil }
}

public enum AuthenticationClientError: Error, Equatable, Sendable {
    case bootstrapAmbiguousFailure
    case bootstrapRejected(statusCode: Int, code: String?, message: String)
    case invalidE164PhoneNumber
    case invalidProfileDisplayName
    case oauthCallbackNotConfigured
    case oauthCancelled
    case oauthProviderUnavailable
    case oauthSessionExpired
    case oauthSignInFailed
    case unexpectedPhoneVerificationState
}

enum OAuthSignInErrorMapper {
    static func map(_ error: any Error) -> AuthenticationClientError {
        if let error = error as? AuthenticationClientError {
            return error
        }

        #if canImport(AuthenticationServices)
        let webAuthenticationError = error as NSError
        if webAuthenticationError.domain == ASWebAuthenticationSessionErrorDomain {
            if webAuthenticationError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
                return .oauthCancelled
            }
            return .oauthSignInFailed
        }
        #endif

        guard let error = error as? AuthError else {
            return .oauthSignInFailed
        }

        switch error {
        case let .pkceGrantCodeExchange(message, providerError, providerCode):
            return classifyPKCE(
                message: message,
                providerError: providerError,
                providerCode: providerCode
            )
        case let .api(_, _, _, response) where (500...599).contains(response.statusCode):
            return .oauthProviderUnavailable
        default:
            return .oauthSignInFailed
        }
    }

    static func classifyPKCE(
        message: String,
        providerError: String?,
        providerCode: String?
    ) -> AuthenticationClientError {
        let normalizedMessage = message.lowercased()
        let normalizedProviderError = providerError?.lowercased()
        let normalizedProviderCode = providerCode?.lowercased()

        if normalizedProviderError == "access_denied"
            || normalizedProviderCode == "user_cancelled"
            || normalizedProviderCode == "user_canceled"
        {
            return .oauthCancelled
        }

        if normalizedMessage.contains("oauth state has expired")
            || normalizedProviderCode == "bad_oauth_state"
            || normalizedProviderCode == "oauth_state_expired"
        {
            return .oauthSessionExpired
        }

        if normalizedProviderError == "server_error"
            || normalizedProviderCode == "unexpected_failure"
        {
            return .oauthProviderUnavailable
        }

        return .oauthSignInFailed
    }
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
    func suggestedDisplayName() async -> String?
    func currentAccountID() async -> UUID?
    func accountProfileID(for accountID: UUID) async throws -> UUID?
    func resolveAppAccess(for requiredAccess: MarketplaceApplicationAccess) async throws -> AccountRoute
    func requestPhoneVerification(phoneNumber: String) async throws
    func verifyPhone(phoneNumber: String, code: String) async throws
    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        application: MarketplaceApplicationAccess,
        key: IdempotencyKey
    ) async throws -> AccountBootstrapResult
    func signOut() async throws
}

extension SupabaseAuthenticationOperations {
    func suggestedDisplayName() async -> String? { nil }
}

public struct SupabaseAuthenticationClient: AuthenticationClient {
    private let operations: any SupabaseAuthenticationOperations
    private let requiredAccess: MarketplaceApplicationAccess

    public init(
        configuration: BackendConfiguration,
        requiredAccess: MarketplaceApplicationAccess = .profileOnly
    ) {
        operations = LiveOperations(configuration: configuration)
        self.requiredAccess = requiredAccess
    }

    init(
        operations: any SupabaseAuthenticationOperations,
        requiredAccess: MarketplaceApplicationAccess = .profileOnly
    ) {
        self.operations = operations
        self.requiredAccess = requiredAccess
    }

    public func signInWithApple(identityToken: String, nonce: String) async throws {
        try await operations.signInWithApple(identityToken: identityToken, nonce: nonce)
    }

    public func signInWithGoogle(idToken: String) async throws {
        do {
            try await operations.signInWithGoogle(idToken: idToken)
        } catch {
            throw OAuthSignInErrorMapper.map(error)
        }
    }

    public func signInWithGoogle(redirectTo: URL) async throws {
        do {
            try await operations.signInWithGoogle(redirectTo: redirectTo)
        } catch {
            throw OAuthSignInErrorMapper.map(error)
        }
    }

    public func suggestedDisplayName() async -> String? {
        await operations.suggestedDisplayName()
    }

    public func restoreAccount() async throws -> AccountRoute {
        guard let accountID = await operations.currentAccountID() else {
            return .signedOut
        }
        guard let profileAccountID = try await operations.accountProfileID(for: accountID) else {
            return .needsProfile
        }
        guard profileAccountID == accountID else {
            return .needsProfile
        }
        guard requiredAccess != .profileOnly else {
            return .active
        }
        return try await operations.resolveAppAccess(for: requiredAccess)
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
                application: requiredAccess,
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
        guard result.phoneState == .verified else {
            throw AuthenticationClientError.unexpectedPhoneVerificationState
        }
    }

    public func requestPhoneVerification(phoneNumber: String) async throws {
        try await operations.requestPhoneVerification(
            phoneNumber: try E164PhoneNumber(phoneNumber).rawValue
        )
    }

    public func verifyPhone(phoneNumber: String, code: String) async throws {
        try await operations.verifyPhone(
            phoneNumber: try E164PhoneNumber(phoneNumber).rawValue,
            code: code
        )
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

        private struct CheckoutProfile: Decodable {
            let displayName: String
            let phoneNumber: String

            private enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case phoneNumber = "phone_number"
            }
        }

        private struct AppAccessRequest: Encodable {
            let application: String
        }

        private struct AppAccessResponse: Decodable {
            let route: AccountRoute
        }

        private let supabaseClient: SupabaseClient

        init(configuration: BackendConfiguration) {
            supabaseClient = SupabaseClient(
                supabaseURL: configuration.supabaseURL,
                supabaseKey: configuration.publishableKey,
                options: SupabaseClientOptions(
                    auth: .init(emitLocalSessionAsInitialSession: true)
                )
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
                    auth: .init(
                        emitLocalSessionAsInitialSession: true,
                        accessToken: { accessToken }
                    ),
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

        func suggestedDisplayName() async -> String? {
            guard let user = try? await supabaseClient.auth.session.user else { return nil }
            for key in ["full_name", "name"] {
                guard let rawName = user.userMetadata[key]?.stringValue else { continue }
                let normalized = rawName
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if (1...80).contains(normalized.count) { return normalized }
            }
            return nil
        }

        func linkIdentity(
            provider: MarketplaceOAuthProvider,
            redirectTo: URL
        ) async throws {
            try await supabaseClient.auth.linkIdentity(
                provider: provider == .apple ? .apple : .google,
                scopes: provider == .apple ? "name email" : nil,
                redirectTo: redirectTo
            )
        }

        func reauthenticate(
            provider: MarketplaceOAuthProvider,
            redirectTo: URL
        ) async throws {
            let original = try await supabaseClient.auth.session
            let refreshed = try await supabaseClient.auth.signInWithOAuth(
                provider: provider == .apple ? .apple : .google,
                redirectTo: redirectTo,
                scopes: provider == .apple ? "name email" : nil,
                queryParams: [("prompt", provider == .google ? "select_account" : "login")]
            )
            guard refreshed.user.id == original.user.id else {
                _ = try? await supabaseClient.auth.setSession(
                    accessToken: original.accessToken,
                    refreshToken: original.refreshToken
                )
                throw MarketplaceAuthenticatedServicesError.identityMismatch
            }
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

        func currentAccessToken() async throws -> String? {
            do {
                return try await supabaseClient.auth.session.accessToken
            } catch AuthError.sessionMissing {
                return nil
            }
        }

        func checkoutCustomer() async throws -> MarketplaceCheckoutCustomer? {
            let user: User
            do {
                user = try await supabaseClient.auth.session.user
            } catch AuthError.sessionMissing {
                return nil
            }

            let profiles: [CheckoutProfile] = try await supabaseClient
                .from("accounts")
                .select("display_name,phone_number")
                .eq("id", value: user.id.uuidString)
                .limit(1)
                .execute()
                .value
            guard let profile = profiles.first else { return nil }
            return MarketplaceCheckoutCustomer(
                displayName: profile.displayName,
                email: user.email,
                phoneNumber: profile.phoneNumber
            )
        }

        func uploadObject(
            bucket: String,
            path: String,
            data: Data,
            contentType: String,
            cacheControl: String
        ) async throws {
            try await supabaseClient.storage
                .from(bucket)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(
                        cacheControl: cacheControl,
                        contentType: contentType,
                        upsert: false
                    )
                )
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

        func resolveAppAccess(
            for requiredAccess: MarketplaceApplicationAccess
        ) async throws -> AccountRoute {
            guard requiredAccess != .profileOnly else {
                return .active
            }
            let response: AppAccessResponse = try await supabaseClient.functions.invoke(
                "resolve-app-access",
                options: FunctionInvokeOptions(
                    body: AppAccessRequest(application: requiredAccess.rawValue)
                )
            )
            return response.route
        }

        func bootstrapAccount(
            displayName: String,
            phoneNumber: String,
            application: MarketplaceApplicationAccess,
            key: IdempotencyKey
        ) async throws -> AccountBootstrapResult {
            try await supabaseClient.functions.invoke(
                "bootstrap-account",
                options: FunctionInvokeOptions(
                    headers: ["X-Idempotency-Key": key.rawValue],
                    body: AccountBootstrapRequest(
                        application: application == .profileOnly ? "customer" : application.rawValue,
                        displayName: displayName,
                        phoneNumber: phoneNumber
                    )
                )
            )
        }

        func signOut() async throws {
            try await supabaseClient.auth.signOut(scope: .local)
        }

        func requestPhoneVerification(phoneNumber: String) async throws {
            try await supabaseClient.auth.update(user: UserAttributes(phone: phoneNumber))
        }

        func verifyPhone(phoneNumber: String, code: String) async throws {
            _ = try await supabaseClient.auth.verifyOTP(
                phone: phoneNumber,
                token: code,
                type: .phoneChange
            )
        }
    }
}
