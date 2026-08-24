import DastakDomain
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DastakAccountView: View {
    private enum AccountAlert: Identifiable {
        case signOut
        case error(String)

        var id: String {
            switch self {
            case .signOut: "sign-out"
            case .error: "error"
            }
        }
    }

    let customer: MarketplaceCheckoutCustomer?
    let location: DastakDeliveryLocation?
    let savedAddressCount: Int
    let accountSessionClient: any AccountSessionClient
    let linkedIdentities: [MarketplaceLinkedIdentity]
    let isLinkingIdentity: Bool
    let identityMessage: String?
    let identityMessageIsSuccess: Bool
    let hasActiveOrders: Bool
    let discoveryRadiusKilometres: Int
    let refreshFailure: DastakCustomerRefreshFailure?
    let deliveryPartnerAccess: DeliveryPartnerAccess
    let isDeliveryPartnerAccessLoading: Bool
    let chooseLocation: () -> Void
    let openOrders: () -> Void
    let becomeDeliveryPartner: () -> Void
    let retryAccount: () -> Void
    let refreshIdentities: () -> Void
    let linkIdentity: (MarketplaceOAuthProvider) -> Void
    let updateProfile: (String, String) async throws -> Void
    let deleteAccount: () async throws -> Void
    let reauthenticate: (MarketplaceOAuthProvider) async throws -> Void
    let exportAccount: () async throws -> MarketplaceAccountExport

    @Environment(\.marketplaceSignOut) private var signOut
    @State private var showingProfileEditor = false
    @State private var showingDeleteAccount = false
    @State private var accountExport: DastakAccountExportFile?
    @State private var accountAlert: AccountAlert?
    @State private var isExporting = false
    @State private var notificationStatus: DastakNotificationPermissionState = .notRequested
    private let legalLinks = MarketplaceLegalLinks(bundle: .main)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                profileSection
                if let refreshFailure {
                    DastakRefreshNotice(failure: refreshFailure, action: retryAccount)
                }
                deliverySection
                preferencesSection
                identitySection
                accountActions
                supportSection
                partnerOpportunity
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.top, MarketplaceSpacing.medium)
            .padding(.bottom, MarketplaceSpacing.xxLarge * 2)
        }
        .scrollIndicators(.hidden)
        .marketplacePage()
        .navigationTitle("Account")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showingProfileEditor) {
            DastakProfileEditor(customer: customer, updateProfile: updateProfile)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDeleteAccount) {
            DastakDeleteAccountSheet(
                warning: deletionWarning,
                linkedIdentities: linkedIdentities,
                deleteAccount: deleteAccount,
                reauthenticate: reauthenticate
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $accountExport) { file in
            DastakAccountExportSheet(file: file)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $accountAlert, content: makeAccountAlert)
        .task {
            notificationStatus = await DastakNotificationPreferences.status()
            refreshIdentities()
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ACCOUNT")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text("Your Dastak")
                    .font(MarketplaceTypography.instrumentSerif(size: 44, relativeTo: .largeTitle))
                Text("Your details, saved places and account controls—kept together and protected.")
                    .font(MarketplaceTypography.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { showingProfileEditor = true } label: {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                    HStack(spacing: MarketplaceSpacing.medium) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.09))
                            Circle()
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                            Text(profileInitials)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(MarketplaceColors.dastakAccentDark.color)
                        }
                        .frame(width: 68, height: 68)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(customer?.displayName ?? "Your account")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(MarketplaceColors.textPrimaryDark.color)
                                .lineLimit(1)
                            Text(customer?.phoneNumber ?? "Add a contact number")
                                .font(.subheadline)
                                .foregroundStyle(MarketplaceColors.textSecondaryDark.color)
                                .lineLimit(1)
                            if let email = customer?.email, !email.isEmpty {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(MarketplaceColors.textSecondaryDark.color)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        ViewThatFits(in: .horizontal) {
                            Label("Edit", systemImage: "pencil")
                                .padding(.horizontal, 11)
                            Image(systemName: "pencil")
                                .frame(width: 36)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.textPrimaryDark.color)
                        .frame(minHeight: 36)
                        .background(.white.opacity(0.09), in: Capsule())
                    }

                    Rectangle()
                        .fill(.white.opacity(0.11))
                        .frame(height: 1)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: MarketplaceSpacing.compact) {
                            profileSecurityBadge
                            profilePlacesBadge
                        }
                        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                            profileSecurityBadge
                            profilePlacesBadge
                        }
                    }
                }
                .padding(20)
                .contentShape(Rectangle())
                .background {
                    DastakMatteBackground(style: .dark)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(MarketplaceColors.dastakAccentDark.color.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edit your name and contact number")
        }
    }

    private func profileBadge(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MarketplaceColors.textSecondaryDark.color)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }

    private var profileSecurityBadge: some View {
        profileBadge(
            linkedIdentities.isEmpty ? "Secure sign-in" : linkedProviderSummary,
            symbol: "checkmark.shield.fill"
        )
    }

    private var profilePlacesBadge: some View {
        profileBadge(
            savedAddressCount == 1 ? "1 saved place" : "\(savedAddressCount) saved places",
            symbol: "mappin.and.ellipse"
        )
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            accountSectionHeader(
                "Saved places",
                detail: "Your default doorstep for checkout",
                trailing: "\(savedAddressCount)/10"
            )

            Button(action: chooseLocation) {
                HStack(alignment: .center, spacing: MarketplaceSpacing.medium) {
                    accountIcon("location.fill")
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: MarketplaceSpacing.small) {
                            Text(location?.displayName ?? "Add delivery address")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if location != nil {
                                Text("DEFAULT")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        MarketplaceColors.dastakAccent.color.opacity(0.10),
                                        in: Capsule()
                                    )
                            }
                        }
                        Text(location?.displayAddress ?? "Save a precise pin and doorstep details for checkout.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                    Spacer(minLength: MarketplaceSpacing.small)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dastakAccountSurface()
            .accessibilityHint(location == nil ? "Add a saved delivery address" : "Manage your saved delivery addresses")
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            accountSectionHeader("Help and safety", detail: "Support, policies and emergency help")
            VStack(spacing: 0) {
                Button(action: openOrders) {
                    accountRow(
                        title: "Help with an order",
                        value: "Get support for a current or past order",
                        symbol: "questionmark.bubble"
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                if let supportURL = legalLinks.support {
                    Link(destination: supportURL) {
                        accountRow(
                            title: "Contact Dastak support",
                            value: "Account, access or delivery help",
                            symbol: "message"
                        )
                    }
                    Divider().padding(.leading, 64)
                }
                if let privacyURL = legalLinks.privacyPolicy {
                    Link(destination: privacyURL) {
                        accountRow(
                            title: "Privacy Policy",
                            value: "How Dastak uses and protects your information",
                            symbol: "hand.raised"
                        )
                    }
                    Divider().padding(.leading, 64)
                }
                if let termsURL = legalLinks.terms {
                    Link(destination: termsURL) {
                        accountRow(
                            title: "Terms of Service",
                            value: "Ordering, payment, delivery and account terms",
                            symbol: "doc.text"
                        )
                    }
                    Divider().padding(.leading, 64)
                }
                Link(destination: URL(string: "tel:112")!) {
                    accountRow(
                        title: "Emergency assistance",
                        value: "Call India emergency services",
                        symbol: "sos",
                        isDestructive: true
                    )
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .dastakAccountSurface()
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            accountSectionHeader("Preferences", detail: "How Dastak works on this device")

            VStack(spacing: 0) {
                Button { Task { await manageNotifications() } } label: {
                    accountRow(
                        title: "Notifications",
                        value: notificationStatus.title,
                        symbol: "bell"
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                accountRow(
                    title: "Browse range",
                    value: "\(discoveryRadiusKilometres) km",
                    symbol: "scope",
                    showsDisclosure: false
                )
                Divider().padding(.leading, 64)
                NavigationLink {
                    DastakPrivacyAndDataView()
                } label: {
                    accountRow(title: "Privacy and data", value: nil, symbol: "hand.raised")
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .dastakAccountSurface()
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            accountSectionHeader("Sign-in security", detail: "Apple and Google identities you control")

            VStack(spacing: 0) {
                ForEach(MarketplaceOAuthProvider.allCases, id: \.self) { provider in
                    HStack(spacing: MarketplaceSpacing.compact) {
                        MarketplaceIdentityProviderMark(provider)
                            .frame(width: 40, height: 40)
                            .background(
                                MarketplaceColors.dastakAccentSoft.color,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider == .apple ? "Apple" : "Google")
                                .font(.headline)
                            Text(isLinked(provider) ? "Linked to this Dastak account" : "Not linked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isLinked(provider) {
                            Label("Linked", systemImage: "checkmark.shield.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MarketplaceColors.success.color)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Button("Add") { linkIdentity(provider) }
                                .buttonStyle(.bordered)
                                .disabled(isLinkingIdentity)
                        }
                    }
                    .frame(minHeight: 76)

                    if provider != .google {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .dastakAccountSurface()

            if let identityMessage {
                Label(
                    identityMessage,
                    systemImage: identityMessageIsSuccess ? "checkmark.shield.fill" : "exclamationmark.shield"
                )
                    .font(.footnote)
                    .foregroundStyle(
                        identityMessageIsSuccess
                            ? MarketplaceColors.dastakAccent.color
                            : MarketplaceColors.destructive.color
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(MarketplaceSpacing.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (identityMessageIsSuccess ? MarketplaceColors.success.color : MarketplaceColors.destructive.color)
                            .opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            } else {
                Label(
                    "Dastak never merges accounts because an email or phone number matches. Link only while signed in to the account you want to keep.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
            }
        }
    }

    private func isLinked(_ provider: MarketplaceOAuthProvider) -> Bool {
        linkedIdentities.contains { $0.provider == provider }
    }

    private func accountRow(
        title: String,
        value: String?,
        symbol: String,
        showsDisclosure: Bool = true,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: MarketplaceSpacing.medium) {
            accountIcon(symbol, isDestructive: isDestructive)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isDestructive ? MarketplaceColors.destructive.color : Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let value, value.count > 12 {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            if let value, value.count <= 12 {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 74)
        .padding(.vertical, MarketplaceSpacing.small)
        .contentShape(Rectangle())
    }

    private func accountIcon(_ symbol: String, isDestructive: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isDestructive ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color)
            .frame(width: 42, height: 42)
            .background(
                (isDestructive ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }

    private func accountSectionHeader(
        _ title: String,
        detail: String,
        trailing: String? = nil
    ) -> some View {
        HStack(alignment: .bottom, spacing: MarketplaceSpacing.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.08), in: Capsule())
            }
        }
    }

    private var partnerOpportunity: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(partnerPresentation.sectionTitle)
                        .font(.title3.weight(.semibold))
                    Text("One account, a separate partner workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let status = partnerPresentation.status {
                    Text(status)
                        .font(.caption2.bold())
                        .foregroundStyle(partnerPresentation.isAttention ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            (partnerPresentation.isAttention ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color).opacity(0.12),
                            in: Capsule()
                        )
                }
            }

            Button(action: becomeDeliveryPartner) {
                HStack(spacing: MarketplaceSpacing.compact) {
                    accountIcon("shippingbox.fill")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(partnerPresentation.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(partnerPresentation.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    if isDeliveryPartnerAccessLoading {
                        ProgressView()
                            .tint(MarketplaceColors.dastakAccent.color)
                    } else {
                        Image(systemName: deliveryPartnerAccess == .notApplied ? "arrow.up.right" : "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    }
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dastakAccountSurface(accented: true)
            .accessibilityLabel(partnerPresentation.title)
            .accessibilityHint(partnerPresentation.detail)
        }
    }

    private var partnerPresentation: PartnerPresentation {
        if isDeliveryPartnerAccessLoading {
            return PartnerPresentation(
                sectionTitle: "Delivery Partner",
                title: "Checking your partner access",
                detail: "This will only take a moment."
            )
        }
        switch deliveryPartnerAccess {
        case .approved:
            return PartnerPresentation(
                sectionTitle: "Delivery Partner",
                title: "Switch to Delivery Partner mode",
                detail: "Open your delivery workspace and continue earning.",
                status: "APPROVED"
            )
        case .pending:
            return PartnerPresentation(
                sectionTitle: "Delivery Partner",
                title: "View your application",
                detail: "Your application is under review. We will notify you when it is approved.",
                status: "IN REVIEW"
            )
        case .rejected:
            return PartnerPresentation(
                sectionTitle: "Delivery Partner",
                title: "Update your application",
                detail: "Review the feedback, update your details and submit again.",
                status: "ACTION NEEDED",
                isAttention: true
            )
        case .suspended:
            return PartnerPresentation(
                sectionTitle: "Delivery Partner",
                title: "Delivery Partner access paused",
                detail: "Open your partner workspace to review your account status and next steps.",
                status: "PAUSED",
                isAttention: true
            )
        case .notApplied:
            return PartnerPresentation(
                sectionTitle: "Earn with Dastak",
                title: "Become a Delivery Partner",
                detail: "Apply once, then choose when you want to earn."
            )
        case .unavailable:
            return PartnerPresentation(
                sectionTitle: "Delivery Partner",
                title: "Open Delivery Partner",
                detail: "Check your application or access your delivery workspace."
            )
        }
    }

    private struct PartnerPresentation {
        let sectionTitle: String
        let title: String
        let detail: String
        var status: String?
        var isAttention = false
    }

    @MainActor
    private func manageNotifications() async {
        switch notificationStatus {
        case .notRequested:
            notificationStatus = await DastakNotificationPreferences.request()
        case .enabled, .disabled, .unavailable:
            DastakNotificationPreferences.openSystemSettings()
        }
    }

    private var accountActions: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            accountSectionHeader("Account and data", detail: "Sessions, export and account access")
            VStack(spacing: 0) {
                NavigationLink {
                    DastakAccountSessionsView(
                        client: accountSessionClient,
                        applicationName: "Dastak"
                    )
                } label: {
                    accountRow(
                        title: "Devices and sessions",
                        value: "Review signed-in devices",
                        symbol: "laptopcomputer.and.iphone"
                    )
                }
                Divider().padding(.leading, 64)
                Button { Task { await prepareAccountExport() } } label: {
                    accountRow(
                        title: isExporting ? "Preparing your data..." : "Download your data",
                        value: "Profile, places, sessions, orders and issues",
                        symbol: "arrow.down.doc"
                    )
                }
                .disabled(isExporting)
                Divider().padding(.leading, 64)
                Button { accountAlert = .signOut } label: {
                    accountRow(
                        title: "Sign out",
                        value: "End this session on this device",
                        symbol: "rectangle.portrait.and.arrow.right"
                    )
                }
                Divider().padding(.leading, 64)
                Button(role: .destructive) { showingDeleteAccount = true } label: {
                    accountRow(
                        title: "Delete account",
                        value: "Permanently remove your Dastak account",
                        symbol: "trash",
                        isDestructive: true
                    )
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .dastakAccountSurface()
        }
    }

    private var profileInitials: String {
        let parts = (customer?.displayName ?? "Dastak")
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var linkedProviderSummary: String {
        linkedIdentities
            .map { $0.provider == .apple ? "Apple" : "Google" }
            .joined(separator: " + ")
    }

    private func makeAccountAlert(_ alert: AccountAlert) -> Alert {
        switch alert {
        case .signOut:
            Alert(
                title: Text("Sign out of Dastak?"),
                message: Text("You'll need to sign in again to access your account and orders."),
                primaryButton: .cancel(Text("Cancel")),
                secondaryButton: .destructive(Text("Sign out")) {
                    Task { await endCurrentSessionAndSignOut() }
                }
            )
        case let .error(message):
            Alert(
                title: Text("Dastak"),
                message: Text(message),
                dismissButton: .cancel(Text("OK"))
            )
        }
    }

    private var deletionWarning: String {
        let history = "Completed order and financial records may be retained without your identity where legally required."
        guard hasActiveOrders else {
            return "This permanently deletes your account and signs you out. \(history)"
        }
        return "You have an active order. It will continue, but deleting now removes your access to tracking and in-app support. This permanently signs you out. \(history)"
    }

    @MainActor
    private func endCurrentSessionAndSignOut() async {
        try? await accountSessionClient.endCurrent(
            idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!
        )
        await signOut()
    }

    @MainActor
    private func prepareAccountExport() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let exported = try await exportAccount()
            let safeFilename = exported.filename
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeFilename.isEmpty ? "dastak-account.json" : safeFilename)
            try exported.data.write(to: url, options: [.atomic])
            accountExport = DastakAccountExportFile(url: url)
        } catch {
            accountAlert = .error("Your Dastak data could not be prepared. Please try again.")
        }
    }
}

struct DastakAccountSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let accented: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        content
            .background {
                shape
                    .fill(MarketplaceColors.surface(for: colorScheme))
                    .overlay {
                        if accented {
                            LinearGradient(
                                colors: [
                                    MarketplaceColors.accent(for: colorScheme).opacity(0.10),
                                    .clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(shape)
                        }
                    }
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    accented
                        ? MarketplaceColors.accent(for: colorScheme).opacity(0.34)
                        : MarketplaceColors.divider(for: colorScheme).opacity(0.82),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.055), radius: 16, y: 7)
    }
}

extension View {
    func dastakAccountSurface(accented: Bool = false) -> some View {
        modifier(DastakAccountSurface(accented: accented))
    }
}

private struct DastakAccountExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DastakAccountExportSheet: View {
    let file: DastakAccountExportFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.success.color)
                    .frame(width: 54, height: 54)
                    .background(
                        MarketplaceColors.success.color.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                Text("Your data is ready")
                    .font(MarketplaceTypography.instrumentSerif(size: 38, relativeTo: .largeTitle))
                Text("Save or share this private JSON file using a destination you trust.")
                    .font(MarketplaceTypography.supporting)
                    .foregroundStyle(.secondary)
                ShareLink(item: file.url) {
                    Label("Save or share data", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(MarketplaceColors.dastakAccent.color)
                Spacer(minLength: 0)
            }
            .padding(MarketplaceSpacing.large)
            .marketplacePage()
            .navigationTitle("Data export")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear { try? FileManager.default.removeItem(at: file.url) }
    }
}

private struct DastakDeleteAccountSheet: View {
    let warning: String
    let linkedIdentities: [MarketplaceLinkedIdentity]
    let deleteAccount: () async throws -> Void
    let reauthenticate: (MarketplaceOAuthProvider) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var isBusy = false
    @State private var requiresReauthentication = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        Text("PERMANENT ACTION")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(MarketplaceColors.destructive.color)
                        Text("Delete your account?")
                            .font(MarketplaceTypography.instrumentSerif(size: 40, relativeTo: .largeTitle))
                        Text(warning)
                            .font(MarketplaceTypography.supporting)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if requiresReauthentication {
                        verificationSection
                    } else {
                        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                            Text("Type DELETE to confirm")
                                .font(.subheadline.weight(.semibold))
                            TextField("DELETE", text: $confirmation)
#if os(iOS)
                                .textInputAutocapitalization(.characters)
#endif
                                .autocorrectionDisabled()
                                .padding(.horizontal, MarketplaceSpacing.compact)
                                .frame(minHeight: 56)
                                .dastakAccountSurface()
                                .accessibilityLabel("Type DELETE to confirm account deletion")
                        }

                        Button(role: .destructive) {
                            Task { await requestDeletion() }
                        } label: {
                            ZStack {
                                Label(
                                    isBusy ? "Deleting account…" : "Permanently delete account",
                                    systemImage: "trash.fill"
                                )
                                if isBusy {
                                    HStack {
                                        Spacer()
                                        ProgressView().tint(.white)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DastakDestructiveActionButtonStyle())
                        .disabled(!confirmed || isBusy)
                        .accessibilityHint("Permanently deletes this account after identity verification.")

                        Label("This cannot be undone.", systemImage: "exclamationmark.shield.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MarketplaceColors.destructive.color)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(MarketplaceColors.destructive.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(MarketplaceSpacing.large)
            }
            .scrollIndicators(.hidden)
            .marketplacePage()
            .navigationTitle("Delete account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep account") { dismiss() }.disabled(isBusy)
                }
            }
        }
    }

    private var confirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Verify it’s you")
                .font(.title3.weight(.semibold))
            Text("Sign in again with a method already linked to this Dastak account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(linkedIdentities, id: \.provider) { identity in
                Button {
                    Task { await verifyAndDelete(identity.provider) }
                } label: {
                    HStack(spacing: MarketplaceSpacing.compact) {
                        MarketplaceIdentityProviderMark(identity.provider)
                            .frame(width: 24, height: 24)
                        Text("Continue with \(identity.provider == .apple ? "Apple" : "Google")")
                        Spacer()
                        if isBusy { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .dastakAccountSurface()
    }

    @MainActor
    private func requestDeletion() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await deleteAccount()
        } catch let error as FunctionClientError {
            if case let .api(_, code, message) = error, code == "reauthentication_required" {
                requiresReauthentication = true
                errorMessage = message
            } else {
                errorMessage = "Your account could not be deleted. Your account is unchanged."
            }
        } catch {
            errorMessage = "Your account could not be deleted. Your account is unchanged."
        }
    }

    @MainActor
    private func verifyAndDelete(_ provider: MarketplaceOAuthProvider) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await reauthenticate(provider)
            try await deleteAccount()
        } catch MarketplaceAuthenticatedServicesError.identityMismatch {
            errorMessage = "A different Dastak account signed in. Deletion was cancelled."
        } catch let error as FunctionClientError {
            if case let .api(_, _, message) = error { errorMessage = message }
            else { errorMessage = "Identity verification could not be completed." }
        } catch {
            errorMessage = "Identity verification could not be completed. Your account is unchanged."
        }
    }
}

private struct DastakDestructiveActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                MarketplaceColors.destructive.color,
                                MarketplaceColors.destructive.color.opacity(0.88),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(
                color: MarketplaceColors.destructive.color.opacity(isEnabled ? 0.22 : 0),
                radius: 18,
                y: 8
            )
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct DastakPrivacyAndDataView: View {
    let roleName: String?

    init(roleName: String? = nil) {
        self.roleName = roleName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                    Text((roleName ?? "Customer").uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text("Your data")
                        .font(MarketplaceTypography.instrumentSerif(size: 40, relativeTo: .largeTitle))
                    Text("Clear controls and only the information Dastak needs to operate your account.")
                        .font(MarketplaceTypography.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                privacySection(title: "Contact", items: contactItems)

                if roleName == nil {
                    privacySection(title: "Location", items: locationItems)
                } else {
                    privacySection(title: "Permissions and access", items: accessItems)
                }

                privacySection(title: "Records and control", items: controlItems)

                Label(
                    "Dastak never uses your profile phone number to sign in, recover your account or prove payment.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(MarketplaceSpacing.medium)
            .padding(.bottom, MarketplaceSpacing.xxLarge)
        }
        .scrollIndicators(.hidden)
        .marketplacePage()
        .navigationTitle("Privacy and data")
        .dastakInlineNavigationTitle()
        .dastakNavigationBarVisible()
    }

    private typealias PrivacyItem = (symbol: String, title: String, detail: String)

    private var contactItems: [PrivacyItem] {
        [
            (
                "phone",
                "Contact number",
                contactMessage
            ),
            (
                "person.text.rectangle",
                "Profile identity",
                "Your name and sign-in email identify this account across approved Dastak services."
            )
        ]
    }

    private var locationItems: [PrivacyItem] {
        [
            (
                "location",
                "Browse area",
                "Stored separately from delivery addresses and used to find nearby stores."
            ),
            (
                "house",
                "Delivery addresses",
                "Used for pricing and fulfilling an order. Current location is requested only when you choose it."
            )
        ]
    }

    private var accessItems: [PrivacyItem] {
        [
            (
                "checkmark.shield",
                "Approved workspace",
                "Server-approved access decides which workspace this account can open. Profile edits cannot grant access."
            ),
            (
                "doc.text.magnifyingglass",
                "Review evidence",
                verificationMessage
            )
        ]
    }

    private var controlItems: [PrivacyItem] {
        [
            (
                "clock.arrow.circlepath",
                "Operational records",
                "Order and financial records may be retained where required for settlement, fraud prevention or law."
            ),
            (
                "slider.horizontal.3",
                "Your controls",
                controlMessage
            )
        ]
    }

    private func privacySection(title: String, items: [PrivacyItem]) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text(title).font(MarketplaceTypography.sectionTitle)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                        Image(systemName: item.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .frame(width: 36, height: 36)
                            .background(
                                MarketplaceColors.dastakAccent.color.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.headline)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, MarketplaceSpacing.compact)

                    if index < items.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .dastakAccountSurface()
        }
    }

    private var contactMessage: String {
        switch roleName {
        case "Merchant":
            "Shared only when an active order requires contact with your store."
        case "Delivery Partner":
            "Shared only during an assigned delivery when customer, merchant or partner contact is required."
        default:
            "Shared only when an active delivery requires contact."
        }
    }

    private var verificationMessage: String {
        switch roleName {
        case "Merchant":
            "Store and identity evidence is restricted to authorised reviewers and used to approve merchant access."
        case "Delivery Partner":
            "Identity and vehicle evidence is restricted to authorised reviewers and used to approve delivery access."
        default:
            "Evidence is restricted to authorised reviewers and used only for account approval."
        }
    }

    private var controlMessage: String {
        roleName == nil
            ? "Edit your profile and addresses, manage device permissions, sign out or request permanent account deletion from Account."
            : "Edit your profile, manage device permissions, sign out or request permanent account deletion from Account."
    }
}

struct DastakProfileEditor: View {
    private enum Field: Hashable {
        case name
    }

    let customer: MarketplaceCheckoutCustomer?
    let subtitle: String
    let contactMessage: String
    let updateProfile: (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var phoneNumber: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didAttemptSave = false
    @FocusState private var focusedField: Field?

    init(
        customer: MarketplaceCheckoutCustomer?,
        subtitle: String = "Keep your delivery contact accurate.",
        contactMessage: String = "Used only when an active delivery requires contact. It is not used to sign in.",
        updateProfile: @escaping (String, String) async throws -> Void
    ) {
        self.customer = customer
        self.subtitle = subtitle
        self.contactMessage = contactMessage
        self.updateProfile = updateProfile
        _displayName = State(initialValue: customer?.displayName ?? "")
        _phoneNumber = State(initialValue: customer?.phoneNumber ?? "+91")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        Image(systemName: "person.text.rectangle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .frame(width: 48, height: 48)
                            .background(
                                MarketplaceColors.dastakAccent.color.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )
                        Text("Personal details")
                            .font(MarketplaceTypography.instrumentSerif(size: 40, relativeTo: .largeTitle))
                        Text(subtitle)
                            .font(MarketplaceTypography.supporting)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        Text("Full name")
                            .font(.subheadline.weight(.semibold))
                        TextField("Enter your full name", text: $displayName)
                            .textContentType(.name)
#if os(iOS)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
#endif
                            .focused($focusedField, equals: .name)
                            .padding(.horizontal, MarketplaceSpacing.compact)
                            .frame(minHeight: 56)
                            .dastakAccountSurface()
                            .accessibilityHint(nameValidationMessage ?? "Required, up to 80 characters")
                        if didAttemptSave, let nameValidationMessage {
                            Label(nameValidationMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(MarketplaceColors.destructive.color)
                        }
                    }

                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        Text("Phone number")
                            .font(.subheadline.weight(.semibold))
                        DastakPhoneNumberField(phoneNumber: $phoneNumber)
                            .accessibilityHint(phoneValidationMessage ?? "Include the country code")
                        if didAttemptSave, let phoneValidationMessage {
                            Label(phoneValidationMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(MarketplaceColors.destructive.color)
                        }
                        Label(
                            contactMessage,
                            systemImage: "lock.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(MarketplaceColors.destructive.color)
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.top, MarketplaceSpacing.large)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
            }
            .scrollIndicators(.hidden)
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .marketplacePage()
            .navigationTitle("Edit profile")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        dismissKeyboard()
                        Task { await save() }
                    }
                        .disabled(isSaving)
                }
#if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
#endif
            }
        }
        .onTapGesture { dismissKeyboard() }
    }

    private var isValid: Bool {
        nameValidationMessage == nil && phoneValidationMessage == nil
    }

    private var nameValidationMessage: String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter your full name." }
        if name.count > 80 { return "Use 80 characters or fewer." }
        return nil
    }

    private var phoneValidationMessage: String? {
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return DastakPhoneNumberValidator.isValidE164(phone)
            ? nil
            : "Enter a valid phone number with country code."
    }

    @MainActor
    private func dismissKeyboard() {
        focusedField = nil
#if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
#endif
    }

    @MainActor
    private func save() async {
        didAttemptSave = true
        guard isValid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await updateProfile(displayName, phoneNumber)
            dismiss()
        } catch let error as FunctionClientError {
            if case let .api(_, _, message) = error { errorMessage = message }
            else { errorMessage = "Your profile could not be updated." }
        } catch {
            errorMessage = "Your profile could not be updated."
        }
    }
}
