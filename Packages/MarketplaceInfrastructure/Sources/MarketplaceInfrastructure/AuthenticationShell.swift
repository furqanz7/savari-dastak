import AuthenticationServices
import CryptoKit
import Foundation
import MarketplaceFoundation
import Security
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    let services: MarketplaceAuthenticatedServices?

    init(
        product: MarketplaceProduct,
        bundle: Bundle,
        requiredAccess: MarketplaceApplicationAccess
    ) {
        guard let configuration = try? BackendConfiguration.runtime(product: product, bundle: bundle) else {
            coordinator = nil
            services = nil
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
        let functionClient = SupabaseFunctionClient(
            configuration: configuration,
            accessTokenProvider: {
                try await operations.currentAccessToken()
            }
        )
        services = MarketplaceAuthenticatedServices(
            functions: functionClient,
            accountIDProvider: {
                guard let accountID = await operations.currentAccountID() else {
                    throw MarketplaceAuthenticatedServicesError.authenticationRequired
                }
                return accountID
            },
            objectUploader: { bucket, path, data, contentType, cacheControl in
                try await operations.uploadObject(
                    bucket: bucket,
                    path: path,
                    data: data,
                    contentType: contentType,
                    cacheControl: cacheControl
                )
            },
            checkoutCustomerProvider: {
                try await operations.checkoutCustomer()
            }
        )
    }
}

public struct MarketplaceAuthenticationShell: View {
    private let applicationName: String
    private let product: MarketplaceProduct
    private let requiredAccess: MarketplaceApplicationAccess
    private let showsPersistentSignOut: Bool
    private let activeContent: (MarketplaceAuthenticatedServices) -> AnyView
    private let restrictedContent: ((AccountRoute, MarketplaceAuthenticatedServices) -> AnyView)?
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
            activeContent: { _ in AnyView(DefaultMarketplaceActiveView()) },
            restrictedContent: nil
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
        self.init(
            applicationName: applicationName,
            product: product,
            requiredAccess: requiredAccess,
            showsPersistentSignOut: showsPersistentSignOut,
            bundle: bundle,
            activeContent: { services in AnyView(activeContent(services.functions)) },
            restrictedContent: nil
        )
    }

    public init<Content: View, RestrictedContent: View>(
        applicationName: String,
        product: MarketplaceProduct,
        requiredAccess: MarketplaceApplicationAccess,
        showsPersistentSignOut: Bool = true,
        bundle: Bundle = .main,
        @ViewBuilder authenticatedServicesContent: @escaping (
            MarketplaceAuthenticatedServices
        ) -> Content,
        @ViewBuilder restrictedContent: @escaping (
            AccountRoute,
            MarketplaceAuthenticatedServices
        ) -> RestrictedContent
    ) {
        self.init(
            applicationName: applicationName,
            product: product,
            requiredAccess: requiredAccess,
            showsPersistentSignOut: showsPersistentSignOut,
            bundle: bundle,
            activeContent: { services in AnyView(authenticatedServicesContent(services)) },
            restrictedContent: { route, services in
                AnyView(restrictedContent(route, services))
            }
        )
    }

    private init(
        applicationName: String,
        product: MarketplaceProduct,
        requiredAccess: MarketplaceApplicationAccess,
        showsPersistentSignOut: Bool,
        bundle: Bundle,
        activeContent: @escaping (MarketplaceAuthenticatedServices) -> AnyView,
        restrictedContent: ((AccountRoute, MarketplaceAuthenticatedServices) -> AnyView)?
    ) {
        self.applicationName = applicationName
        self.product = product
        self.requiredAccess = requiredAccess
        self.showsPersistentSignOut = showsPersistentSignOut
        self.activeContent = activeContent
        self.restrictedContent = restrictedContent
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
               let services = model.services
            {
                AuthenticationRouteView(
                    applicationName: applicationName,
                    product: product,
                    requiredAccess: requiredAccess,
                    coordinator: coordinator,
                    showsPersistentSignOut: showsPersistentSignOut,
                    activeContent: activeContent(services),
                    restrictedContent: restrictedContent.map { content in
                        { route in content(route, services) }
                    }
                )
            } else {
                ShellUnavailableView(applicationName: applicationName)
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
    let product: MarketplaceProduct
    let requiredAccess: MarketplaceApplicationAccess
    @ObservedObject var coordinator: AuthenticationCoordinator
    let showsPersistentSignOut: Bool
    let activeContent: AnyView
    let restrictedContent: ((AccountRoute) -> AnyView)?

    @State private var displayName = ""
    @State private var phoneNumber = ""
    @State private var appleNonce: String?
    @State private var errorMessage: String?
    @State private var restored = false

    var body: some View {
        Group {
            if coordinator.isRestoring {
                restoreView
            } else if coordinator.route == .active {
                activeView
            } else if product == .dastak {
                dastakAuthenticationView
            } else {
                authenticationView
            }
        }
        .task {
            guard !restored else { return }
            restored = true
            await coordinator.restore()
            if product == .dastak, coordinator.route == .needsProfile, phoneNumber.isEmpty {
                phoneNumber = "+91"
            }
        }
        .onChange(of: coordinator.route) { route in
            if product == .dastak, route == .needsProfile, phoneNumber.isEmpty {
                phoneNumber = "+91"
            }
        }
    }

    private var restoreView: some View {
        if product == .dastak {
            return AnyView(dastakRestoreView)
        }

        return AnyView(
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.06).ignoresSafeArea()
            ProgressView()
                .tint(.white)
                .accessibilityLabel("Restoring account")
        }
        )
    }

    private var dastakRestoreView: some View {
        ZStack {
            dastakCanvas.ignoresSafeArea()
            VStack(spacing: 18) {
                DastakAuthWordmark(size: 38)
                ProgressView()
                    .tint(dastakAccent)
                    .accessibilityLabel("Restoring account")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var authenticationView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.06),
                    Color(red: 0.13, green: 0.08, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 92, height: 92)
                        .overlay {
                            Text(String(applicationName.prefix(1)))
                                .font(.system(size: 36, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                        }

                    Text(applicationName)
                        .font(.system(size: 32, weight: .light, design: .serif))
                        .foregroundStyle(.white)

                    Text(routeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.74))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }

                Group {
                    switch coordinator.route {
                    case .signedOut:
                        signedOutView
                    case .needsProfile:
                        profileView
                    case .pendingApproval:
                        resolvedRestrictedView(
                            route: .pendingApproval,
                            title: "Approval pending",
                            message: "This account is waiting for approval to use this app."
                        )
                    case .suspended:
                        resolvedRestrictedView(
                            route: .suspended,
                            title: "Account suspended",
                            message: "This account cannot use this app right now."
                        )
                    case .accessDenied:
                        resolvedRestrictedView(
                            route: .accessDenied,
                            title: "Access denied",
                            message: "This account does not have access to this app."
                        )
                    case .active:
                        EmptyView()
                    }
                }
                .padding(20)
                .frame(maxWidth: 430)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 28, y: 18)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.81))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }

    private var dastakAuthenticationView: some View {
        ZStack {
            dastakCanvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    DastakAuthWordmark(size: 40)
                    Text(dastakRoleLabel)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(dastakAccent)
                    Text(routeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(dastakSecondaryText)
                }
                .padding(.top, 28)

                Spacer(minLength: 72)

                Group {
                    switch coordinator.route {
                    case .signedOut:
                        dastakSignedOutView
                    case .needsProfile:
                        dastakProfileView
                    case .pendingApproval:
                        resolvedRestrictedView(
                            route: .pendingApproval,
                            title: "Approval pending",
                            message: "This account is waiting for approval to use this app."
                        )
                    case .suspended:
                        resolvedRestrictedView(
                            route: .suspended,
                            title: "Account suspended",
                            message: "This account cannot use this app right now."
                        )
                    case .accessDenied:
                        resolvedRestrictedView(
                            route: .accessDenied,
                            title: "Access denied",
                            message: "This account does not have access to this app."
                        )
                    case .active:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(dastakError)
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: 430, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .preferredColorScheme(.dark)
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
            .frame(height: 50)

            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    GoogleLogoMark()
                    Text("Continue with Google")
                }
            }
            .buttonStyle(BrandGoogleButtonStyle())
        }
    }

    private var dastakSignedOutView: some View {
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
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    GoogleLogoMark()
                    Text("Continue with Google")
                }
            }
            .buttonStyle(DastakGoogleButtonStyle())
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
                !profileInputIsValid || coordinator.isProfileSubmissionInFlight
            )
        }
    }

    private var dastakProfileView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tell us about you")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Your name and phone number are required for deliveries.")
                    .font(.subheadline)
                    .foregroundStyle(dastakSecondaryText)
            }
            .padding(.bottom, 4)
            #if os(iOS)
            TextField("Full name", text: $displayName)
                .textContentType(.name)
                .textFieldStyle(DastakTextFieldStyle())
            #else
            TextField("Full name", text: $displayName)
                .textFieldStyle(DastakTextFieldStyle())
            #endif
            dastakPhoneNumberField
            Text("Include the country code. Your number is used only for delivery contact.")
                .font(.caption)
                .foregroundStyle(dastakSecondaryText)
            Button(coordinator.isProfileSubmissionInFlight ? "Completing profile" : "Continue") {
                Task { await completeProfile() }
            }
            .buttonStyle(DastakPrimaryButtonStyle())
            .disabled(
                !profileInputIsValid || coordinator.isProfileSubmissionInFlight
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

    @ViewBuilder
    private var dastakPhoneNumberField: some View {
        #if os(iOS)
        TextField("Phone number", text: $phoneNumber)
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
            .textFieldStyle(DastakTextFieldStyle())
        #else
        TextField("Phone number", text: $phoneNumber)
            .textFieldStyle(DastakTextFieldStyle())
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

    private var routeSubtitle: String {
        switch coordinator.route {
        case .signedOut: return "Sign in to continue."
        case .needsProfile: return "Complete your account details."
        case .pendingApproval: return "Your account is awaiting approval."
        case .suspended: return "This account is currently suspended."
        case .accessDenied: return "This account cannot use this app."
        case .active: return "Account active."
        }
    }

    @ViewBuilder
    private func resolvedRestrictedView(
        route: AccountRoute,
        title: String,
        message: String
    ) -> some View {
        if let restrictedContent {
            VStack(spacing: 16) {
                restrictedContent(route)
                Button("Sign out") {
                    Task { await signOut() }
                }
                .buttonStyle(.bordered)
            }
        } else {
            restrictedView(title: title, message: message)
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

        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let fullName = credential.fullName {
            displayName = [fullName.givenName, fullName.familyName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
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

    private var dastakCanvas: Color {
        Color(red: 15 / 255, green: 15 / 255, blue: 16 / 255)
    }

    private var dastakSurface: Color {
        Color(red: 24 / 255, green: 23 / 255, blue: 22 / 255)
    }

    private var dastakAccent: Color {
        Color(red: 176 / 255, green: 141 / 255, blue: 87 / 255)
    }

    private var dastakSecondaryText: Color {
        Color(red: 184 / 255, green: 177 / 255, blue: 168 / 255)
    }

    private var dastakError: Color {
        Color(red: 166 / 255, green: 90 / 255, blue: 69 / 255)
    }

    private var dastakRoleLabel: String {
        switch requiredAccess {
        case .dastakCustomer: "Customer"
        case .dastakMerchant: "Merchant"
        case .dastakAdmin: "Admin"
        case .profileOnly: applicationName
        }
    }

    private var profileInputIsValid: Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(name.count)
            && phone.range(of: #"^\+[1-9][0-9]{7,14}$"#, options: .regularExpression) != nil
    }
}

private struct DastakAuthWordmark: View {
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.18) {
            Text("Dastak")
                .font(.system(size: size, weight: .light, design: .default))
            Text("دستک")
                .font(.system(size: size * 0.78, weight: .regular))
                .environment(\.layoutDirection, .rightToLeft)
        }
        .foregroundStyle(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dastak")
    }
}

private struct DastakTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 15)
            .frame(minHeight: 52)
            .foregroundStyle(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
            .background(Color(red: 24 / 255, green: 23 / 255, blue: 22 / 255))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DastakPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .font(.headline)
            .foregroundStyle(Color(red: 33 / 255, green: 19 / 255, blue: 14 / 255))
            .background(Color(red: 176 / 255, green: 141 / 255, blue: 87 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct DastakGoogleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .font(.headline)
            .foregroundStyle(Color(red: 33 / 255, green: 19 / 255, blue: 14 / 255))
            .background(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private struct GoogleLogoMark: View {
    var body: some View {
        #if canImport(UIKit)
        if let url = Bundle.module.url(forResource: "GoogleG", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        } else {
            fallbackMark
        }
        #else
        fallbackMark
        #endif
    }

    private var fallbackMark: some View {
        Image("GoogleG", bundle: .module)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

private struct BrandGoogleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .font(.headline)
            .foregroundStyle(.primary)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private struct ShellUnavailableView: View {
    let applicationName: String

    var body: some View {
        VStack(spacing: 12) {
            Text(applicationName)
                .font(.title2.bold())
            Text("Authentication unavailable")
            Text("Backend configuration is missing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
