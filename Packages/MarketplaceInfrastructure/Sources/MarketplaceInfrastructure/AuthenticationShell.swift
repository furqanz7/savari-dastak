import AuthenticationServices
import CryptoKit
import Foundation
import MarketplaceFoundation
import Security
import SwiftUI

enum AppleSignInNonce {
    private static let characters = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
    )

    static func make(length: Int = 32) throws -> String {
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
                throw AuthenticationShellError.appleCredentialUnavailable
            }
            for byte in random where remaining > 0 && byte < characters.count {
                result.append(characters[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum AuthenticationShellError: Error {
    case appleCredentialUnavailable
}

@MainActor
private final class AuthenticationShellModel: ObservableObject {
    let coordinator: AuthenticationCoordinator?

    init(product: MarketplaceProduct, bundle: Bundle) {
        guard let configuration = try? BackendConfiguration.runtime(product: product, bundle: bundle) else {
            coordinator = nil
            return
        }
        coordinator = AuthenticationCoordinator(
            client: SupabaseAuthenticationClient(configuration: configuration)
        )
    }
}

public struct MarketplaceAuthenticationShell: View {
    private let applicationName: String
    @StateObject private var model: AuthenticationShellModel

    public init(
        applicationName: String,
        product: MarketplaceProduct,
        bundle: Bundle = .main
    ) {
        self.applicationName = applicationName
        _model = StateObject(
            wrappedValue: AuthenticationShellModel(product: product, bundle: bundle)
        )
    }

    public var body: some View {
        Group {
            if let coordinator = model.coordinator {
                AuthenticationRouteView(
                    applicationName: applicationName,
                    coordinator: coordinator
                )
            } else {
                VStack(spacing: 12) {
                    Text(applicationName).font(.title2).bold()
                    Text("Authentication unavailable")
                    Text("Backend configuration is missing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }
}

private struct AuthenticationRouteView: View {
    let applicationName: String
    @ObservedObject var coordinator: AuthenticationCoordinator

    @State private var displayName = ""
    @State private var phoneNumber = ""
    @State private var appleNonce: String?
    @State private var errorMessage: String?
    @State private var restored = false

    var body: some View {
        VStack(spacing: 16) {
            Text(applicationName).font(.title2).bold()

            switch coordinator.route {
            case .signedOut:
                signedOutView
            case .needsProfile:
                profileView
            case .active:
                activeView
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .task {
            guard !restored else { return }
            restored = true
            await coordinator.restore()
        }
    }

    private var signedOutView: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                do {
                    let nonce = try AppleSignInNonce.make()
                    appleNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = AppleSignInNonce.sha256(nonce)
                } catch {
                    errorMessage = "Apple sign-in is unavailable."
                }
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)

            Button("Continue with Google") {
                Task { await signInWithGoogle() }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
        }
    }

    private var profileView: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)
            phoneNumberField
            Text("Profile contact only. Not used for sign-in, recovery, or payments.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(coordinator.isProfileSubmissionInFlight ? "Completing profile" : "Complete profile") {
                Task { await completeProfile() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || coordinator.isProfileSubmissionInFlight
            )
        }
    }

    @ViewBuilder
    private var phoneNumberField: some View {
        #if os(iOS)
        TextField("Phone number (unverified)", text: $phoneNumber)
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
            .textFieldStyle(.roundedBorder)
        #else
        TextField("Phone number (unverified)", text: $phoneNumber)
            .textFieldStyle(.roundedBorder)
        #endif
    }

    private var activeView: some View {
        VStack(spacing: 12) {
            Text("Account active")
            Button("Sign out") {
                Task { await signOut() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func handleAppleCompletion(
        _ result: Result<ASAuthorization, any Error>
    ) {
        guard
            case let .success(authorization) = result,
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let identityToken = String(data: tokenData, encoding: .utf8),
            let nonce = appleNonce
        else {
            errorMessage = "Apple sign-in could not be completed."
            return
        }

        Task {
            do {
                errorMessage = nil
                try await coordinator.signInWithApple(identityToken: identityToken, nonce: nonce)
            } catch {
                errorMessage = "Apple sign-in could not be completed."
            }
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        do {
            errorMessage = nil
            try await coordinator.signInWithGoogle()
        } catch {
            errorMessage = "Google sign-in is not configured or could not be completed."
        }
    }

    @MainActor
    private func completeProfile() async {
        do {
            errorMessage = nil
            try await coordinator.completeProfile(
                displayName: displayName,
                phoneNumber: phoneNumber
            )
        } catch {
            errorMessage = coordinator.profileSubmissionError?.profileSubmissionMessage
                ?? "Profile completion failed."
        }
    }

    @MainActor
    private func signOut() async {
        do {
            errorMessage = nil
            try await coordinator.signOut()
        } catch {
            errorMessage = "Sign out failed."
        }
    }
}
