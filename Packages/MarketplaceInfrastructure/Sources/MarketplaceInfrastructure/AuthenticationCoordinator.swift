import Combine
import Foundation
import MarketplaceFoundation

private enum BackendProfileNormalization {
    static func displayName(_ value: String) -> String {
        var normalized = ""
        var pendingSpace = false

        for scalar in value.unicodeScalars {
            if isECMAScriptWhitespace(scalar) {
                pendingSpace = !normalized.isEmpty
            } else {
                if pendingSpace {
                    normalized.append(" ")
                    pendingSpace = false
                }
                normalized.unicodeScalars.append(scalar)
            }
        }

        return normalized
    }

    static func phoneNumber(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard
            let first = scalars.firstIndex(where: { !isECMAScriptWhitespace($0) }),
            let last = scalars.lastIndex(where: { !isECMAScriptWhitespace($0) })
        else {
            return ""
        }
        let end = scalars.index(after: last)
        return String(value[first..<end])
    }

    private static func isECMAScriptWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0009 ... 0x000D,
             0x0020,
             0x00A0,
             0x1680,
             0x2000 ... 0x200A,
             0x2028 ... 0x2029,
             0x202F,
             0x205F,
             0x3000,
             0xFEFF:
            return true
        default:
            return false
        }
    }
}

@MainActor
public final class AuthenticationCoordinator: ObservableObject {
    @Published public private(set) var route: AccountRoute = .signedOut
    @Published public private(set) var isRestoring = true
    @Published public private(set) var isProfileSubmissionInFlight = false
    @Published public private(set) var profileSubmissionError: AuthenticationClientError?

    private struct ProfilePayload: Equatable {
        let displayName: String
        let phoneNumber: String

        init(displayName: String, phoneNumber: String) throws {
            let normalizedName = BackendProfileNormalization.displayName(displayName)
            guard (1...80).contains(normalizedName.count) else {
                throw AuthenticationClientError.invalidProfileDisplayName
            }

            let normalizedPhone = BackendProfileNormalization.phoneNumber(phoneNumber)
            self.displayName = normalizedName
            self.phoneNumber = try E164PhoneNumber(normalizedPhone).rawValue
        }
    }

    private struct PendingProfileSubmission {
        let payload: ProfilePayload
        let key: IdempotencyKey
    }

    private let client: any AuthenticationClient
    private var pendingProfileSubmission: PendingProfileSubmission?

    public init(client: any AuthenticationClient) {
        self.client = client
    }

    public func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            route = try await client.restoreAccount()
        } catch {
            route = .signedOut
        }
    }

    public func signInWithApple(identityToken: String, nonce: String) async throws {
        route = .signedOut
        try await client.signInWithApple(identityToken: identityToken, nonce: nonce)
        route = try await client.restoreAccount()
    }

    public func signInWithGoogle(
        configuration: OAuthCallbackConfiguration = OAuthCallbackConfiguration(bundle: .main)
    ) async throws {
        route = .signedOut
        let callbackURL = try configuration.callbackURL()
        try await client.signInWithGoogle(redirectTo: callbackURL)
        route = try await client.restoreAccount()
    }

    public func completeProfile(
        displayName: String,
        phoneNumber: String
    ) async throws {
        guard !isProfileSubmissionInFlight else { return }

        let payload: ProfilePayload
        do {
            payload = try ProfilePayload(displayName: displayName, phoneNumber: phoneNumber)
        } catch let error as AuthenticationClientError {
            profileSubmissionError = error
            throw error
        }

        let submission: PendingProfileSubmission
        if let pendingProfileSubmission, pendingProfileSubmission.payload == payload {
            submission = pendingProfileSubmission
        } else {
            let key = IdempotencyKey(rawValue: UUID().uuidString)!
            submission = PendingProfileSubmission(payload: payload, key: key)
            pendingProfileSubmission = submission
        }

        profileSubmissionError = nil
        isProfileSubmissionInFlight = true
        defer { isProfileSubmissionInFlight = false }

        do {
            try await client.bootstrapAccount(
                displayName: payload.displayName,
                phoneNumber: payload.phoneNumber,
                key: submission.key
            )
        } catch {
            let typedError = error as? AuthenticationClientError ?? .bootstrapAmbiguousFailure
            guard typedError == .bootstrapAmbiguousFailure else {
                pendingProfileSubmission = nil
                profileSubmissionError = typedError
                throw typedError
            }
            try await reconcileAmbiguousProfileSubmission(orThrow: typedError)
            return
        }

        do {
            route = try await client.restoreAccount()
        } catch {
            let error = AuthenticationClientError.bootstrapAmbiguousFailure
            profileSubmissionError = error
            throw error
        }

        guard route.confirmsExistingProfile else {
            let error = AuthenticationClientError.bootstrapAmbiguousFailure
            profileSubmissionError = error
            throw error
        }
        pendingProfileSubmission = nil
    }

    public func signOut() async throws {
        try await client.signOut()
        pendingProfileSubmission = nil
        profileSubmissionError = nil
        route = .signedOut
    }

    private func reconcileAmbiguousProfileSubmission(
        orThrow error: AuthenticationClientError
    ) async throws {
        if let restoredRoute = try? await client.restoreAccount() {
            route = restoredRoute
            if restoredRoute.confirmsExistingProfile {
                pendingProfileSubmission = nil
                profileSubmissionError = nil
                return
            }
        }
        profileSubmissionError = error
        throw error
    }
}

private extension AccountRoute {
    var confirmsExistingProfile: Bool {
        switch self {
        case .pendingApproval, .suspended, .accessDenied, .active:
            return true
        case .signedOut, .needsProfile:
            return false
        }
    }
}

extension AuthenticationClientError {
    var profileSubmissionMessage: String {
        switch self {
        case .bootstrapAmbiguousFailure:
            return "Profile completion could not be confirmed. Retry the same details."
        case let .bootstrapRejected(_, _, message):
            return message
        case .invalidE164PhoneNumber:
            return "Use a valid E.164 phone number."
        case .invalidProfileDisplayName:
            return "Display name is required and must be 80 characters or fewer."
        case .oauthCallbackNotConfigured,
             .oauthCancelled,
             .oauthProviderUnavailable,
             .oauthSessionExpired,
             .oauthSignInFailed:
            return "Profile completion failed."
        case .unexpectedPhoneVerificationState:
            return "Profile completion returned an invalid phone state."
        }
    }

    var googleSignInMessage: String? {
        switch self {
        case .oauthCancelled:
            return nil
        case .oauthSessionExpired:
            return "Google sign-in expired. Try again."
        case .oauthProviderUnavailable:
            return "Google sign-in is temporarily unavailable. Try again later."
        case .oauthCallbackNotConfigured:
            return "Google sign-in is not configured."
        case .oauthSignInFailed,
             .bootstrapAmbiguousFailure,
             .bootstrapRejected,
             .invalidE164PhoneNumber,
             .invalidProfileDisplayName,
             .unexpectedPhoneVerificationState:
            return "Google sign-in could not be completed."
        }
    }
}
