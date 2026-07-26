import AuthenticationServices
import CryptoKit
import Foundation
import MarketplaceFoundation
import Security
import SwiftUI

public struct MarketplaceSignOutAction: @unchecked Sendable {
    private let action: @MainActor () async -> Void

    public init(action: @escaping @MainActor () async -> Void) {
        self.action = action
    }

    @MainActor
    public func callAsFunction() async {
        await action()
    }
}

private struct MarketplaceSignOutEnvironmentKey: EnvironmentKey {
    static let defaultValue = MarketplaceSignOutAction(action: {})
}

public extension EnvironmentValues {
    var marketplaceSignOut: MarketplaceSignOutAction {
        get { self[MarketplaceSignOutEnvironmentKey.self] }
        set { self[MarketplaceSignOutEnvironmentKey.self] = newValue }
    }
}

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
    let functionClient: (any FunctionClient)?

    init(
        product: MarketplaceProduct,
        bundle: Bundle,
        requiredAccess: MarketplaceApplicationAccess
    ) {
        guard let configuration = try? BackendConfiguration.runtime(product: product, bundle: bundle) else {
            coordinator = nil
            functionClient = nil
            return
        }
        let operations = SupabaseAuthenticationClient.LiveOperations(
            configuration: configuration
        )
        coordinator = AuthenticationCoordinator(
            client: SupabaseAuthenticationClient(
                operations: operations,
                requiredAccess: requiredAccess
            )
        )
        functionClient = SupabaseFunctionClient(
            configuration: configuration,
            accessTokenProvider: {
                try await operations.currentAccessToken()
            }
        )
    }
}

public struct MarketplaceAuthenticationShell: View {
    private let applicationName: String
    private let showsPersistentSignOut: Bool
    private let activeContent: (any FunctionClient) -> AnyView
    @StateObject private var model: AuthenticationShellModel

    public init(
        applicationName: String,
        product: MarketplaceProduct,
        requiredAccess: MarketplaceApplicationAccess = .profileOnly,
        showsPersistentSignOut: Bool = true,
        bundle: Bundle = .main
    ) {
        self.init(
            applicationName: applicationName,
            product: product,
            requiredAccess: requiredAccess,
            showsPersistentSignOut: showsPersistentSignOut,
            bundle: bundle,
            activeContent: { _ in DefaultMarketplaceActiveView() }
        )
    }

    public init<Content: View>(
        applicationName: String,
        product: MarketplaceProduct,
        requiredAccess: MarketplaceApplicationAccess = .profileOnly,
        showsPersistentSignOut: Bool = true,
        bundle: Bundle = .main,
        @ViewBuilder activeContent: @escaping (any FunctionClient) -> Content
    ) {
        self.applicationName = applicationName
        self.showsPersistentSignOut = showsPersistentSignOut
        self.activeContent = { functionClient in
            AnyView(activeContent(functionClient))
        }
        _model = StateObject(
            wrappedValue: AuthenticationShellModel(
                product: product,
                bundle: bundle,
                requiredAccess: requiredAccess
            )
        )
    }

    public var body: some View {
        Group {
            if let coordinator = model.coordinator,
               let functionClient = model.functionClient
            {
                AuthenticationRouteView(
                    applicationName: applicationName,
                    coordinator: coordinator,
                    showsPersistentSignOut: showsPersistentSignOut,
                    activeContent: activeContent(functionClient)
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

private struct DefaultMarketplaceActiveView: View {
    var body: some View {
        Text("Account active")
    }
}

private struct AuthenticationRouteView: View {
    let applicationName: String
    @ObservedObject var coordinator: AuthenticationCoordinator
    let showsPersistentSignOut: Bool
    let activeContent: AnyView

    @State private var displayName = ""
    @State private var phoneNumber = ""
    @State private var appleNonce: String?
    @State private var errorMessage: String?
    @State private var restored = false

    var body: some View {
        Group {
            if coordinator.route == .active {
                activeView
            } else {
                authenticationView
            }
        }
        .task {
            guard !restored else { return }
            restored = true
            await coordinator.restore()
        }
    }

    private var authenticationView: some View {
        VStack(spacing: 16) {
            Text(applicationName).font(.title2).bold()

            switch coordinator.route {
            case .signedOut:
                signedOutView
            case .needsProfile:
                profileView
            case .pendingApproval:
                restrictedView(
                    title: "Approval pending",
                    message: "This account is waiting for approval to use this app."
                )
            case .suspended:
                restrictedView(
                    title: "Account suspended",
                    message: "This account cannot use this app right now."
                )
            case .accessDenied:
                restrictedView(
                    title: "Access denied",
                    message: "This account does not have access to this app."
                )
            case .active:
                EmptyView()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
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
        Group {
            if showsPersistentSignOut {
                persistentSignOutView
            } else {
                activeContent
                    .environment(
                        \.marketplaceSignOut,
                        MarketplaceSignOutAction { await signOut() }
                    )
            }
        }
    }

    private var persistentSignOutView: some View {
        VStack(spacing: 0) {
            activeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Divider()
            HStack {
                Spacer()
                Button("Sign out") {
                    Task { await signOut() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private func restrictedView(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
        } catch let error as AuthenticationClientError {
            errorMessage = error.googleSignInMessage
        } catch {
            errorMessage = AuthenticationClientError.oauthSignInFailed.googleSignInMessage
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
