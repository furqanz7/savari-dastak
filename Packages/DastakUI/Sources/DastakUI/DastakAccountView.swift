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
        case deleteAccount
        case error(String)

        var id: String {
            switch self {
            case .signOut: "sign-out"
            case .deleteAccount: "delete-account"
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

    @Environment(\.marketplaceSignOut) private var signOut
    @State private var showingProfileEditor = false
    @State private var accountAlert: AccountAlert?
    @State private var isDeleting = false
    @State private var notificationStatus: DastakNotificationPermissionState = .notRequested
    private let legalLinks = MarketplaceLegalLinks(bundle: .main)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                profileSection
                if let refreshFailure {
                    DastakRefreshNotice(failure: refreshFailure, action: retryAccount)
                }
                deliverySection
                preferencesSection
                identitySection
                supportSection
                partnerOpportunity
                accountActions
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.top, MarketplaceSpacing.medium)
            .padding(.bottom, MarketplaceSpacing.xxLarge)
        }
        .scrollIndicators(.hidden)
        .marketplacePage()
        .navigationTitle("Account")
        .sheet(isPresented: $showingProfileEditor) {
            DastakProfileEditor(customer: customer, updateProfile: updateProfile)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $accountAlert, content: makeAccountAlert)
        .task {
            notificationStatus = await DastakNotificationPreferences.status()
            refreshIdentities()
        }
    }

    private var profileSection: some View {
        Button { showingProfileEditor = true } label: {
            HStack(spacing: MarketplaceSpacing.medium) {
                ZStack {
                    Circle()
                        .fill(MarketplaceColors.dastakAccentSoft.color)
                    Text(profileInitials)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(customer?.displayName ?? "Your account")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(customer?.phoneNumber ?? customer?.email ?? "Complete your details")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let email = customer?.email,
                       !email.isEmpty,
                       customer?.phoneNumber != nil {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 38, height: 38)
                    .background(MarketplaceColors.dastakAccentSoft.color, in: Circle())
            }
            .padding(MarketplaceSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marketplaceFlatSurface()
        .accessibilityHint("Edit your name and contact number")
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                Text("Saved addresses")
                    .font(MarketplaceTypography.sectionTitle)
                Spacer()
                Text("\(savedAddressCount)/10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: chooseLocation) {
                HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
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
                        .padding(.top, 8)
                }
                .padding(MarketplaceSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeliveryPartnerAccessLoading)
            .marketplaceFlatSurface()
            .accessibilityHint(location == nil ? "Add a saved delivery address" : "Manage your saved delivery addresses")
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Help and legal")
                .font(MarketplaceTypography.sectionTitle)
            VStack(spacing: 0) {
                Button(action: openOrders) {
                    accountRow(
                        title: "Help with an order",
                        value: "Get support for a current or past order",
                        symbol: "questionmark.bubble"
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 56)
                if let supportURL = legalLinks.support {
                    Link(destination: supportURL) {
                        accountRow(
                            title: "Contact Dastak support",
                            value: "Account, access or delivery help",
                            symbol: "message"
                        )
                    }
                    Divider().padding(.leading, 56)
                }
                if let privacyURL = legalLinks.privacyPolicy {
                    Link(destination: privacyURL) {
                        accountRow(
                            title: "Privacy Policy",
                            value: "How Dastak uses and protects your information",
                            symbol: "hand.raised"
                        )
                    }
                    Divider().padding(.leading, 56)
                }
                if let termsURL = legalLinks.terms {
                    Link(destination: termsURL) {
                        accountRow(
                            title: "Terms of Service",
                            value: "Ordering, payment, delivery and account terms",
                            symbol: "doc.text"
                        )
                    }
                    Divider().padding(.leading, 56)
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
            .marketplaceFlatSurface()
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Preferences")
                .font(MarketplaceTypography.sectionTitle)

            VStack(spacing: 0) {
                Button { Task { await manageNotifications() } } label: {
                    accountRow(
                        title: "Notifications",
                        value: notificationStatus.title,
                        symbol: "bell"
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 56)
                accountRow(
                    title: "Browse range",
                    value: "\(discoveryRadiusKilometres) km",
                    symbol: "scope",
                    showsDisclosure: false
                )
                Divider().padding(.leading, 56)
                NavigationLink {
                    DastakPrivacyAndDataView()
                } label: {
                    accountRow(title: "Privacy and data", value: nil, symbol: "hand.raised")
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Sign-in security")
                .font(MarketplaceTypography.sectionTitle)

            VStack(spacing: 0) {
                ForEach(MarketplaceOAuthProvider.allCases, id: \.self) { provider in
                    HStack(spacing: MarketplaceSpacing.compact) {
                        accountIcon(provider == .apple ? "apple.logo" : "g.circle.fill")
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
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Button("Add") { linkIdentity(provider) }
                                .buttonStyle(.bordered)
                                .disabled(isLinkingIdentity)
                        }
                    }
                    .frame(minHeight: 68)

                    if provider != .google {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()

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
            } else {
                Text("Dastak never merges accounts because an email or phone number matches. Link only while signed in to the account you want to keep.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        HStack(spacing: MarketplaceSpacing.compact) {
            accountIcon(symbol, isDestructive: isDestructive)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isDestructive ? MarketplaceColors.destructive.color : Color.primary)
                if let value, value.count > 12 {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let value, value.count <= 12 {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private func accountIcon(_ symbol: String, isDestructive: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isDestructive ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color)
            .frame(width: 36, height: 36)
            .background(
                (isDestructive ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
    }

    private var partnerOpportunity: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(partnerPresentation.sectionTitle)
                    .font(MarketplaceTypography.sectionTitle)
                Spacer()
                if let status = partnerPresentation.status {
                    Text(status)
                        .font(.caption2.bold())
                        .foregroundStyle(partnerPresentation.isAttention ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            (partnerPresentation.isAttention ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
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
                            .fixedSize(horizontal: false, vertical: true)
                        Text(partnerPresentation.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: MarketplaceSpacing.small)
                    if isDeliveryPartnerAccessLoading {
                        ProgressView()
                            .tint(MarketplaceColors.dastakAccent.color)
                    } else {
                        Image(systemName: deliveryPartnerAccess == .notApplied ? "arrow.up.right" : "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    }
                }
                .padding(MarketplaceSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .marketplaceFlatSurface()
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
            Text("Account security")
                .font(MarketplaceTypography.sectionTitle)
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
                Divider().padding(.leading, 56)
                Button { accountAlert = .signOut } label: {
                    accountRow(
                        title: "Sign out",
                        value: "End this session on this device",
                        symbol: "rectangle.portrait.and.arrow.right"
                    )
                }
                Divider().padding(.leading, 56)
                Button(role: .destructive) { accountAlert = .deleteAccount } label: {
                    accountRow(
                        title: isDeleting ? "Deleting account..." : "Delete account",
                        value: "Permanently remove your Dastak account",
                        symbol: "trash",
                        isDestructive: true
                    )
                }
                .disabled(isDeleting)
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private var profileInitials: String {
        let parts = (customer?.displayName ?? "Dastak")
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
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
        case .deleteAccount:
            Alert(
                title: Text("Delete your Dastak account?"),
                message: Text(deletionWarning),
                primaryButton: .cancel(Text("Cancel")),
                secondaryButton: .destructive(Text("Delete account")) {
                    Task { await performAccountDeletion() }
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
    private func performAccountDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await deleteAccount()
        } catch {
            accountAlert = .error("Your account could not be deleted. Please try again.")
        }
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
                        .font(MarketplaceTypography.instrumentSerif(fixedSize: 36))
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
            .marketplaceFlatSurface()
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
                        Text("Personal details")
                            .font(.largeTitle.bold())
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
                            .marketplaceFlatSurface()
                    }

                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        Text("Phone number")
                            .font(.subheadline.weight(.semibold))
                        DastakPhoneNumberField(phoneNumber: $phoneNumber)
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
                        .disabled(!isValid || isSaving)
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
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(name.count)
            && DastakPhoneNumberValidator.isValidE164(phone)
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
