import AuthenticationServices
import CryptoKit
import Foundation
import MarketplaceDesignSystem
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

public struct MarketplaceAccessRefreshAction: @unchecked Sendable {
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

private struct MarketplaceAccessRefreshEnvironmentKey: EnvironmentKey {
    static let defaultValue = MarketplaceAccessRefreshAction(action: {})
}

public extension EnvironmentValues {
    var marketplaceSignOut: MarketplaceSignOutAction {
        get { self[MarketplaceSignOutEnvironmentKey.self] }
        set { self[MarketplaceSignOutEnvironmentKey.self] = newValue }
    }

    var marketplaceAccessRefresh: MarketplaceAccessRefreshAction {
        get { self[MarketplaceAccessRefreshEnvironmentKey.self] }
        set { self[MarketplaceAccessRefreshEnvironmentKey.self] = newValue }
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
        let accessTokenBroker = MarketplaceAccessTokenBroker {
            try await operations.currentAccessToken()
        }
        let functionClient = SupabaseFunctionClient(
            configuration: configuration,
            accessTokenProvider: {
                try await accessTokenBroker.accessToken()
            }
        )
        services = MarketplaceAuthenticatedServices(
            functions: functionClient,
            orderEvents: SupabaseOrderEventClient(
                configuration: configuration,
                accessTokenProvider: {
                    try await accessTokenBroker.accessToken()
                }
            ),
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
            },
            appAccessProvider: { application in
                try await operations.resolveAppAccess(for: application)
            },
            oauthIdentityLinker: { provider in
                try await operations.linkIdentity(
                    provider: provider,
                    redirectTo: try OAuthCallbackConfiguration(bundle: bundle).callbackURL()
                )
            },
            oauthReauthenticator: { provider in
                try await operations.reauthenticate(
                    provider: provider,
                    redirectTo: try OAuthCallbackConfiguration(bundle: bundle).callbackURL()
                )
            }
        )
    }
}

public struct MarketplaceAuthenticationShell: View {
    private let applicationName: String
    private let product: MarketplaceProduct
    private let requiredAccess: MarketplaceApplicationAccess
    private let showsPersistentSignOut: Bool
    private let legalLinks: MarketplaceLegalLinks
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
        legalLinks = MarketplaceLegalLinks(bundle: bundle)
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
                    legalLinks: legalLinks,
                    showsPersistentSignOut: showsPersistentSignOut,
                    activeContent: sessionRegistered(
                        activeContent(services),
                        services: services
                    ),
                    restrictedContent: restrictedContent.map { content in
                        { route in
                            sessionRegistered(
                                content(route, services),
                                services: services
                            )
                        }
                    }
                )
            } else {
                ShellUnavailableView(applicationName: applicationName)
            }
        }
    }

    private func sessionRegistered(
        _ content: AnyView,
        services: MarketplaceAuthenticatedServices
    ) -> AnyView {
        guard product == .dastak else { return content }
        return AnyView(
            content.modifier(
                DastakSessionRegistrationModifier(
                    client: SupabaseAccountSessionClient(functions: services.functions),
                    applicationName: applicationName
                )
            )
        )
    }
}

private struct DastakSessionRegistrationModifier: ViewModifier {
    let client: any AccountSessionClient
    let applicationName: String

    @State private var hasRegistered = false

    func body(content: Content) -> some View {
        content.task {
            guard !hasRegistered else { return }
            hasRegistered = true
            _ = try? await client.snapshot(
                device: currentDevice,
                idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!
            )
        }
    }

    private var currentDevice: AccountSessionDevice {
        #if canImport(UIKit)
        let name = UIDevice.current.name
        let model = UIDevice.current.model
        return AccountSessionDevice(
            deviceName: name.isEmpty ? model : name,
            platform: "ios",
            appName: applicationName,
            userAgent: "Dastak iOS"
        )
        #else
        return AccountSessionDevice(
            deviceName: Host.current().localizedName ?? "Apple device",
            platform: "ios",
            appName: applicationName,
            userAgent: "Dastak Apple app"
        )
        #endif
    }
}

private struct DefaultMarketplaceActiveView: View {
    var body: some View {
        Text("Account active")
    }
}

private struct AuthenticationRouteView: View {
    private enum SignInProvider: String {
        case apple = "Apple"
        case google = "Google"
    }

    let applicationName: String
    let product: MarketplaceProduct
    let requiredAccess: MarketplaceApplicationAccess
    @ObservedObject var coordinator: AuthenticationCoordinator
    let legalLinks: MarketplaceLegalLinks
    let showsPersistentSignOut: Bool
    let activeContent: AnyView
    let restrictedContent: ((AccountRoute) -> AnyView)?

    @State private var displayName = ""
    @State private var phoneNumber = ""
    @State private var appleNonce: String?
    @State private var errorMessage: String?
    @State private var identityRecoveryComplete = false
    @State private var restored = false
    @State private var showsSignOutConfirmation = false
    @State private var signingInProvider: SignInProvider?

    var body: some View {
        Group {
            if coordinator.isRestoring {
                restoreView
            } else if coordinator.restorationFailed {
                restorationFailureView
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
        .task(id: coordinator.route) {
            guard requiredAccess == .dastakAdmin, coordinator.route == .accessDenied else {
                return
            }
            await signOut()
        }
        .confirmationDialog(
            "Sign out of Dastak?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to continue with a different account.")
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

    private var restorationFailureView: some View {
        ZStack {
            (product == .dastak ? dastakCanvas : Color(red: 0.06, green: 0.06, blue: 0.06))
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(product == .dastak ? dastakAccent : .white)
                Text("Unable to check your account")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Check your connection and try again. Your saved sign-in has not been removed.")
                    .font(.subheadline)
                    .foregroundStyle(product == .dastak ? dastakSecondaryText : Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
                Button("Try again") {
                    errorMessage = nil
                    Task { await coordinator.restore() }
                }
                .frame(maxWidth: 360)
                .frame(minHeight: 54)
                .font(.headline)
                .foregroundStyle(product == .dastak ? Color(red: 33 / 255, green: 19 / 255, blue: 14 / 255) : .black)
                .background(product == .dastak ? dastakAccent : .white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .buttonStyle(.plain)
                Button("Sign out") { showsSignOutConfirmation = true }
                    .foregroundStyle(.secondary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(product == .dastak ? dastakError : .red)
                }
            }
            .padding(28)
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
            Group {
                if requiredAccess == .dastakCustomer {
                    DastakMatteBackground(style: .dark)
                } else {
                    dastakCanvas
                }
            }
                .ignoresSafeArea()
                .onTapGesture { dismissKeyboard() }

            if coordinator.route == .needsProfile {
                dastakProfileAuthenticationView
            } else if restrictedContent != nil,
                      coordinator.route == .pendingApproval
                        || coordinator.route == .suspended
                        || coordinator.route == .accessDenied {
                dastakRouteContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                dastakStandardAuthenticationView
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var dastakProfileAuthenticationView: some View {
        if requiredAccess == .dastakCustomer {
            dastakCustomerProfileAuthenticationView
        } else {
            dastakOperatorProfileAuthenticationView
        }
    }

    private var dastakCustomerProfileAuthenticationView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 820
            VStack(alignment: .leading, spacing: 0) {
                dastakCustomerBrandHeader(compact: compact)
                dastakCustomerProfileHero(compact: compact)
                    .padding(.top, compact ? 16 : 32)
                dastakCustomerProfileForm(compact: compact)
                    .padding(.top, compact ? 14 : 24)
                dastakErrorView
                    .padding(.top, compact ? 6 : 10)
            }
            .frame(maxWidth: 430, alignment: .leading)
            .padding(.horizontal, compact ? 20 : 24)
            .padding(.top, compact ? 8 : 16)
            .padding(.bottom, compact ? 8 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
#if os(iOS)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
#endif
    }

    private var dastakOperatorProfileAuthenticationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dastakAuthenticationHeader(showsSubtitle: false)
                dastakProfileView
                    .padding(.top, 46)
                dastakErrorView
            }
            .frame(maxWidth: 430, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 32)
        }
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
#endif
    }

    @ViewBuilder
    private var dastakStandardAuthenticationView: some View {
        if requiredAccess == .dastakCustomer, coordinator.route == .signedOut {
            dastakCustomerSignInView
        } else {
            dastakOperatorAuthenticationView
        }
    }

    private var dastakCustomerSignInView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 900
            VStack(alignment: .leading, spacing: 0) {
                    dastakCustomerBrandHeader(compact: compact)

                    VStack(alignment: .leading, spacing: compact ? 8 : 14) {
                        Text("WELCOME TO DASTAK")
                            .font(.caption2.weight(.bold))
                            .tracking(1.7)
                            .foregroundStyle(dastakAccent)

                        Text("Everything you need,\nthoughtfully delivered.")
                            .font(MarketplaceTypography.instrumentSerif(size: compact ? 36 : 44))
                            .foregroundStyle(.white)
                            .lineSpacing(-2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Food and everyday essentials in one basket. We secure every item before you pay.")
                            .font(.system(size: compact ? 14 : 16, weight: .regular))
                            .foregroundStyle(dastakSecondaryText)
                            .lineSpacing(compact ? 1 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, compact ? 18 : 40)

                    if !compact {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 18) {
                                dastakCustomerPromises
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                dastakCustomerPromises
                            }
                        }
                        .padding(.top, 20)
                    }

                    Spacer(minLength: compact ? 10 : 30)

                    VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Continue securely")
                                .font(.headline)
                                .foregroundStyle(.white)
                            if !compact {
                                Text("Use Apple or Google to create or return to your Dastak account.")
                                    .font(.footnote)
                                    .foregroundStyle(dastakSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        dastakSignedOutView
                        signInProgressView
                        dastakErrorView

                        Divider()
                            .overlay(Color.white.opacity(0.10))

                        Label(
                            compact
                                ? "Phone is added later for delivery—not sign-in."
                                : "Your phone number is added later for delivery contact—not for sign-in.",
                            systemImage: "lock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(dastakSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(compact ? 14 : 18)
                    .background(dastakSurface.opacity(0.94))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.black.opacity(0.28), radius: 28, y: 18)

                    dastakLegalLinks
                    Spacer(minLength: compact ? 4 : 12)
                }
                .frame(maxWidth: 430, alignment: .topLeading)
                .padding(.horizontal, compact ? 20 : 24)
                .padding(.top, compact ? 8 : 16)
                .padding(.bottom, compact ? 6 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
    }

    private var dastakOperatorAuthenticationView: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    dastakAuthenticationHeader(showsSubtitle: true)
                    Spacer(minLength: 52)
                    dastakRouteContent
                        .frame(maxWidth: .infinity)
                    signInProgressView
                    dastakErrorView
                    if coordinator.route == .signedOut {
                        dastakLegalLinks
                    }
                    Spacer(minLength: 28)
                }
                .frame(
                    maxWidth: 430,
                    minHeight: proxy.size.height,
                    alignment: .topLeading
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 36)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func dastakCustomerBrandHeader(compact: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 16) {
            DastakAuthWordmark(size: compact ? 32 : 38)
            Spacer(minLength: 10)
            Text("Customer")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.25)
                .foregroundStyle(dastakAccent)
                .padding(.horizontal, 11)
                .frame(minHeight: 30)
                .background(dastakAccent.opacity(0.10))
                .overlay {
                    Capsule()
                        .stroke(dastakAccent.opacity(0.28), lineWidth: 1)
                }
                .clipShape(Capsule())
        }
        .padding(.top, compact ? 4 : 12)
    }

    private func dastakCustomerProfileHero(compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 16) {
            HStack(spacing: 8) {
                Capsule().fill(dastakAccent).frame(height: 3)
                Capsule().fill(dastakAccent).frame(height: 3)
            }
            .accessibilityHidden(true)

            Text("ACCOUNT SETUP · 2 OF 2")
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(dastakAccent)

            Text("Make Dastak yours.")
                .font(MarketplaceTypography.instrumentSerif(size: compact ? 34 : 42))
                .foregroundStyle(.white)

            Text("Tell us what to call you and where an active delivery can reach you.")
                .font(.system(size: compact ? 14 : 16))
                .foregroundStyle(dastakSecondaryText)
                .lineSpacing(compact ? 1 : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var dastakCustomerPromises: some View {
        DastakOnboardingPromise(
            symbol: "checkmark.seal.fill",
            title: "Exact items",
            detail: "Secured first"
        )
        DastakOnboardingPromise(
            symbol: "lock.shield.fill",
            title: "Private by design",
            detail: "One protected checkout"
        )
    }

    private func dastakAuthenticationHeader(showsSubtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DastakAuthWordmark(size: 40)
            Text(dastakRoleLabel)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(dastakAccent)
            if showsSubtitle {
                Text(routeSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(dastakSecondaryText)
            }
        }
        .padding(.top, 28)
    }

    @ViewBuilder
    private var dastakRouteContent: some View {
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

    @ViewBuilder
    private var dastakErrorView: some View {
        if let errorMessage {
            if requiredAccess == .dastakCustomer {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(dastakError)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(dastakError.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityElement(children: .combine)
            } else {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(dastakError)
                    .padding(.top, 20)
            }
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
                guard signingInProvider == nil else { return }
                do {
                    signingInProvider = .apple
                    let nonce = try AppleSignInNonce.make()
                    appleNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = AppleSignInNonce.sha256(nonce)
                } catch {
                    signingInProvider = nil
                    errorMessage = "Apple sign-in is unavailable."
                }
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(signingInProvider != nil)

            Button {
                Task { await signInWithGoogle() }
            } label: {
                DastakGoogleSignInLabel(title: "Continue with Google")
            }
            .buttonStyle(DastakGoogleButtonStyle())
            .disabled(signingInProvider != nil)
        }
    }

    @ViewBuilder
    private var signInProgressView: some View {
        if let signingInProvider {
            HStack(spacing: 8) {
                ProgressView().tint(dastakAccent)
                Text("Opening \(signingInProvider.rawValue) securely…")
                    .font(.footnote)
                    .foregroundStyle(dastakSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var dastakLegalLinks: some View {
        if requiredAccess == .dastakCustomer {
            VStack(spacing: 8) {
                Text("By continuing, you agree to Dastak’s Terms and acknowledge the Privacy Policy.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 18) {
                    if let terms = legalLinks.terms {
                        Link("Terms", destination: terms)
                    }
                    if let privacy = legalLinks.privacyPolicy {
                        Link("Privacy", destination: privacy)
                    }
                    if let support = legalLinks.support {
                        Link("Get help", destination: support)
                    }
                }
                .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(dastakSecondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
        } else {
            let links = [
                ("Privacy", legalLinks.privacyPolicy),
                ("Terms", legalLinks.terms),
                ("Support", legalLinks.support),
            ]
            HStack(spacing: 18) {
                ForEach(links.compactMap { title, url in url.map { (title, $0) } }, id: \.0) { title, url in
                    Link(title, destination: url)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(dastakSecondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
        }
    }

    private var profileView: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)
            phoneNumberField
            Text("Required profile contact. No SMS verification is used, and it is not used for payments.")
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

    @ViewBuilder
    private var dastakProfileView: some View {
        if requiredAccess == .dastakCustomer {
            dastakCustomerProfileForm
        } else {
            dastakOperatorProfileForm
        }
    }

    private var dastakCustomerProfileForm: some View {
        dastakCustomerProfileForm(compact: false)
    }

    private func dastakCustomerProfileForm(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            Label("Signed in securely with Apple or Google", systemImage: "checkmark.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(dastakAccent)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Full name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
#if os(iOS)
                TextField("Enter your full name", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onChange(of: displayName) { value in
                        if value.count > 80 { displayName = String(value.prefix(80)) }
                    }
                    .textFieldStyle(DastakTextFieldStyle())
#else
                TextField("Enter your full name", text: $displayName)
                    .textFieldStyle(DastakTextFieldStyle())
#endif
                Text("As you want it shown on your Dastak account.")
                    .font(.caption)
                    .foregroundStyle(dastakSecondaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Delivery phone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                DastakPhoneNumberField(phoneNumber: $phoneNumber)

                if dastakPhoneHasUserInput, !DastakPhoneNumberValidator.isValidE164(phoneNumber) {
                    Label("Enter a complete phone number.", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(dastakError)
                } else {
                    Label(dastakPhonePrivacyText, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(dastakSecondaryText)
                }
            }

            Button {
                dismissKeyboard()
                Task {
                    if identityRecoveryComplete { await signOut() }
                    else { await completeProfile() }
                }
            } label: {
                HStack(spacing: 9) {
                    if coordinator.isProfileSubmissionInFlight {
                        ProgressView()
                            .tint(Color(red: 33 / 255, green: 19 / 255, blue: 14 / 255))
                            .accessibilityHidden(true)
                    }
                    Text(coordinator.isProfileSubmissionInFlight
                        ? "Saving your details…"
                        : identityRecoveryComplete
                            ? "Continue to sign in"
                            : "Save and continue")
                    if !coordinator.isProfileSubmissionInFlight {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
            }
            .buttonStyle(DastakPrimaryButtonStyle())
            .disabled(!profileInputIsValid || coordinator.isProfileSubmissionInFlight)

            Button("Use a different account") {
                dismissKeyboard()
                showsSignOutConfirmation = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(dastakSecondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.plain)
        }
        .padding(compact ? 14 : 18)
        .background(dastakSurface.opacity(0.94))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 24, y: 16)
    }

    private var dastakOperatorProfileForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Your details")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text(dastakProfilePurpose)
                    .font(.subheadline)
                    .foregroundStyle(dastakSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Full name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
#if os(iOS)
                TextField("Enter your full name", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
                    .textFieldStyle(DastakTextFieldStyle())
#else
                TextField("Enter your full name", text: $displayName)
                    .textFieldStyle(DastakTextFieldStyle())
#endif
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Phone number")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                DastakPhoneNumberField(phoneNumber: $phoneNumber)
                Label(dastakPhonePrivacyText, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(dastakSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(coordinator.isProfileSubmissionInFlight
                ? "Completing profile"
                : identityRecoveryComplete
                    ? "Continue to sign in"
                    : "Continue") {
                dismissKeyboard()
                Task {
                    if identityRecoveryComplete { await signOut() }
                    else { await completeProfile() }
                }
            }
            .buttonStyle(DastakPrimaryButtonStyle())
            .disabled(
                !profileInputIsValid || coordinator.isProfileSubmissionInFlight
            )

            Button("Use a different account") {
                dismissKeyboard()
                showsSignOutConfirmation = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(dastakSecondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.plain)
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
            if product == .dastak {
                restrictedContent(route)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(
                        \.marketplaceSignOut,
                        MarketplaceSignOutAction { await signOut() }
                    )
                    .environment(
                        \.marketplaceAccessRefresh,
                        MarketplaceAccessRefreshAction { await coordinator.restore() }
                    )
            } else {
                VStack(spacing: 16) {
                    restrictedContent(route)
                    Button("Check status") {
                        Task { await coordinator.restore() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Sign out") {
                        showsSignOutConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            VStack(spacing: 12) {
                Text(title).font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Check status") {
                    Task { await coordinator.restore() }
                }
                .buttonStyle(.borderedProminent)
                Button("Sign out") {
                    showsSignOutConfirmation = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func handleAppleCompletion(
        _ result: Result<ASAuthorization, any Error>
    ) {
        if case let .failure(error) = result {
            appleNonce = nil
            signingInProvider = nil
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                errorMessage = nil
            } else {
                errorMessage = "Apple sign-in could not be completed."
            }
            return
        }

        guard
            case let .success(authorization) = result,
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let identityToken = String(data: tokenData, encoding: .utf8),
            let nonce = appleNonce
        else {
            appleNonce = nil
            signingInProvider = nil
            errorMessage = "Apple sign-in could not be completed."
            return
        }
        appleNonce = nil

        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let fullName = credential.fullName {
            displayName = [fullName.givenName, fullName.familyName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        Task {
            defer { signingInProvider = nil }
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
        guard signingInProvider == nil else { return }
        signingInProvider = .google
        defer { signingInProvider = nil }
        do {
            errorMessage = nil
            let suggestion = try await coordinator.signInWithGoogle()
            if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let suggestion {
                displayName = suggestion
            }
        } catch let error as AuthenticationClientError {
            errorMessage = error.googleSignInMessage
        } catch {
            errorMessage = AuthenticationClientError.oauthSignInFailed.googleSignInMessage
        }
    }

    @MainActor
    private func completeProfile() async {
        errorMessage = nil
        do {
            try await coordinator.completeProfile(
                displayName: displayName,
                phoneNumber: phoneNumber
            )
        } catch {
            if coordinator.profileSubmissionError?.requiresIdentityReauthentication == true {
                identityRecoveryComplete = true
                errorMessage = "Your Dastak account is recovered. Continue to sign in with your updated email."
            } else {
                errorMessage = coordinator.profileSubmissionError?.profileSubmissionMessage
                    ?? "Profile completion failed."
            }
        }
    }

    @MainActor
    private func signOut() async {
        do {
            errorMessage = nil
            identityRecoveryComplete = false
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
        case .dastakDelivery: "Delivery Partner"
        case .dastakAdmin: "Admin"
        case .profileOnly: applicationName
        }
    }

    private var dastakProfilePurpose: String {
        switch requiredAccess {
        case .dastakCustomer:
            "Add the contact details used for your deliveries."
        case .dastakMerchant:
            "Add the contact details used for your store and orders."
        case .dastakDelivery:
            "Add the contact details used for delivery work."
        case .dastakAdmin:
            "Add the contact details for this owner account."
        case .profileOnly:
            "Add the contact details used for your account."
        }
    }

    private var dastakPhonePrivacyText: String {
        switch requiredAccess {
        case .dastakCustomer:
            "Required for your Dastak profile and shared only when an active delivery needs contact. No SMS verification is used."
        case .dastakMerchant:
            "Required for your Dastak profile and shared only when an active order needs contact. No SMS verification is used."
        case .dastakDelivery:
            "Required for your Dastak profile and shared only for active delivery work. No SMS verification is used."
        case .dastakAdmin, .profileOnly:
            "Required for your Dastak profile and used only for account contact. No SMS verification is used."
        }
    }

    private var dastakPhoneHasUserInput: Bool {
        !DastakPhoneNumberParts.parse(phoneNumber).nationalNumber.isEmpty
    }

    @MainActor
    private func dismissKeyboard() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
#endif
    }

    private var profileInputIsValid: Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(name.count)
            && DastakPhoneNumberValidator.isValidE164(phone)
    }
}

private struct DastakOnboardingPromise: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 176 / 255, green: 141 / 255, blue: 87 / 255))
                .frame(width: 24, height: 24)
                .background(Color(red: 176 / 255, green: 141 / 255, blue: 87 / 255).opacity(0.11))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 184 / 255, green: 177 / 255, blue: 168 / 255))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct DastakAuthWordmark: View {
    let size: CGFloat

    var body: some View {
        DastakWordmark(size: size)
        .foregroundStyle(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
    }
}

private struct DastakTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 15)
            .frame(minHeight: 52)
            .foregroundStyle(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
            .tint(Color(red: 176 / 255, green: 141 / 255, blue: 87 / 255))
            .background(Color(red: 24 / 255, green: 23 / 255, blue: 22 / 255))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DastakPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .font(.headline)
            .foregroundStyle(Color(red: 33 / 255, green: 19 / 255, blue: 14 / 255))
            .background(Color(red: 176 / 255, green: 141 / 255, blue: 87 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(!isEnabled ? 0.42 : configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct DastakGoogleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .font(.headline)
            .foregroundStyle(Color(red: 33 / 255, green: 19 / 255, blue: 14 / 255))
            .background(Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private struct DastakGoogleSignInLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            GoogleLogoMark()
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
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
