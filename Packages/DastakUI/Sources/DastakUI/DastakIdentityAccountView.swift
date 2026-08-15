import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

@MainActor
private final class DastakIdentityAccountModel: ObservableObject {
    @Published private(set) var customer: MarketplaceCheckoutCustomer?
    @Published private(set) var deliveryPartner: DeliveryPartnerSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var isDeleting = false
    @Published var errorMessage: String?

    private let services: MarketplaceAuthenticatedServices
    private let profileClient: any AccountProfileClient
    private let deliveryPartnerClient: any DeliveryPartnerClient
    private let loadsDeliveryPartner: Bool

    init(services: MarketplaceAuthenticatedServices, roleName: String) {
        self.services = services
        profileClient = SupabaseAccountProfileClient(functions: services.functions)
        deliveryPartnerClient = SupabaseDeliveryPartnerClient(functions: services.functions)
        loadsDeliveryPartner = roleName == "Delivery Partner"
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await profileClient.snapshot(idempotencyKey: key())
            let identity = try? await services.checkoutCustomer()
            customer = MarketplaceCheckoutCustomer(
                displayName: profile.displayName,
                email: identity?.email,
                phoneNumber: profile.phoneNumber
            )
            if loadsDeliveryPartner {
                deliveryPartner = try await deliveryPartnerClient.selfSnapshot(
                    idempotencyKey: key()
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = "Your account details could not be loaded."
        }
    }

    func update(displayName: String, phoneNumber: String) async throws {
        let profile = try await profileClient.update(
            displayName: displayName,
            phoneNumber: phoneNumber,
            idempotencyKey: key()
        )
        customer = MarketplaceCheckoutCustomer(
            displayName: profile.displayName,
            email: customer?.email,
            phoneNumber: profile.phoneNumber
        )
        errorMessage = nil
    }

    func deleteAccount() async throws {
        isDeleting = true
        defer { isDeleting = false }
        try await profileClient.deleteAccount(idempotencyKey: key())
    }

    private func key() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }
}

public struct DastakIdentityAccountView: View {
    private enum AccountAlert: Identifiable {
        case signOut
        case deleteAccount

        var id: String {
            switch self {
            case .signOut: "sign-out"
            case .deleteAccount: "delete-account"
            }
        }
    }

    private let roleName: String
    private let accessLabel: String
    private let allowsAccountDeletion: Bool
    private let openWorkspace: () -> Void
    @StateObject private var model: DastakIdentityAccountModel
    @Environment(\.marketplaceSignOut) private var signOut
    @State private var showsProfileEditor = false
    @State private var accountAlert: AccountAlert?
    @State private var notificationStatus: DastakNotificationPermissionState = .notRequested

    public init(
        roleName: String,
        accessLabel: String = "Active",
        allowsAccountDeletion: Bool = true,
        openWorkspace: @escaping () -> Void = {},
        services: MarketplaceAuthenticatedServices
    ) {
        self.roleName = roleName
        self.accessLabel = accessLabel
        self.allowsAccountDeletion = allowsAccountDeletion
        self.openWorkspace = openWorkspace
        _model = StateObject(
            wrappedValue: DastakIdentityAccountModel(
                services: services,
                roleName: roleName
            )
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.xLarge) {
                    accountHeading
                    identity
                    if let errorMessage = model.errorMessage {
                        accountError(errorMessage)
                    }
                    if roleName == "Delivery Partner" {
                        partnerCredentials
                    }
                    settings
                    if roleName == "Delivery Partner" {
                        partnerSupport
                    }
                    actions
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.top, MarketplaceSpacing.small)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
            }
            .refreshable { await model.load() }
            .navigationTitle("Account")
            .dastakInlineNavigationTitle()
            .sheet(isPresented: $showsProfileEditor) {
                DastakProfileEditor(
                    customer: model.customer,
                    subtitle: profileSubtitle,
                    contactMessage: contactPrivacyMessage
                ) { name, phone in
                    try await model.update(displayName: name, phoneNumber: phone)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert(item: $accountAlert, content: makeAccountAlert)
        }
        .marketplacePage()
        .task {
            await model.load()
            notificationStatus = await DastakNotificationPreferences.status()
        }
    }

    private var accountHeading: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text(roleName == "Delivery Partner" ? "DELIVERY PARTNER" : roleName.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Your account")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 38))
            Text(accountIntroduction)
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var identity: some View {
        Button { showsProfileEditor = true } label: {
            HStack(spacing: MarketplaceSpacing.medium) {
                Text(profileInitials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 58, height: 58)
                    .background(MarketplaceColors.dastakAccentSoft.color, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.customer?.displayName ?? (model.isLoading ? "Loading account" : roleName))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let phone = model.customer?.phoneNumber {
                        Text(phone).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let email = model.customer?.email, !email.isEmpty {
                        Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
        .disabled(model.isLoading)
        .marketplaceFlatSurface()
        .accessibilityHint("Edit your name and contact number")
    }

    @ViewBuilder
    private var partnerCredentials: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Work profile").font(MarketplaceTypography.sectionTitle)

            VStack(spacing: 0) {
                credentialHeader
                if let partner = model.deliveryPartner {
                    Divider().padding(.leading, 60)
                    credentialRow(
                        title: "Delivery method",
                        value: partner.deliveryMethod.map(deliveryMethodName) ?? "Not available",
                        symbol: partner.deliveryMethod.map(deliveryMethodSymbol) ?? "location"
                    )
                    if let registration = partner.vehicleRegistrationNumber {
                        Divider().padding(.leading, 60)
                        credentialRow(
                            title: "Vehicle",
                            value: partner.vehicleMakeModel ?? registration,
                            detail: partner.vehicleMakeModel == nil ? nil : registration,
                            symbol: "car.side"
                        )
                    }
                    Divider().padding(.leading, 60)
                    credentialRow(
                        title: "Verification",
                        value: verificationLabel(partner),
                        symbol: "checkmark.seal"
                    )
                    Divider().padding(.leading, 60)
                    credentialRow(
                        title: "Availability",
                        value: availabilityLabel(partner),
                        symbol: partner.availability?.status == .online ? "location.fill" : "location.slash"
                    )
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()

            Text("Identity, delivery method and vehicle changes require Dastak review to protect customers, merchants and partners.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    private var credentialHeader: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: partnerStatusSymbol)
                .font(.headline)
                .foregroundStyle(partnerStatusColor)
                .frame(width: 40, height: 40)
                .background(partnerStatusColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(partnerStatusTitle)
                    .font(.headline)
                Text(partnerStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(partnerAccessLabel.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(partnerStatusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(partnerStatusColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .frame(minHeight: 66)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Preferences").font(MarketplaceTypography.sectionTitle)
            VStack(spacing: 0) {
                if roleName != "Delivery Partner" {
                    row(
                        title: "Access",
                        value: accessLabel,
                        symbol: "checkmark.shield"
                    )
                    Divider()
                }
                Button { Task { await manageNotifications() } } label: {
                    row(
                        title: "Notifications",
                        value: notificationStatus.title,
                        symbol: "bell",
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
                Divider()
                NavigationLink {
                    DastakPrivacyAndDataView(roleName: roleName)
                } label: {
                    row(
                        title: "Privacy and data",
                        value: nil,
                        symbol: "hand.raised",
                        showsDisclosure: true
                    )
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private var partnerSupport: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Support and safety").font(MarketplaceTypography.sectionTitle)
            VStack(spacing: 0) {
                Button(action: openWorkspace) {
                    row(
                        title: "Delivery workspace",
                        value: "Open your current assignment",
                        symbol: "shippingbox",
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 56)
                Link(destination: URL(string: "tel:112")!) {
                    row(
                        title: "Emergency assistance",
                        value: "Call India emergency services",
                        symbol: "sos",
                        showsDisclosure: true,
                        isDestructive: true
                    )
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private func row(
        title: String,
        value: String?,
        symbol: String,
        showsDisclosure: Bool = false,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    isDestructive
                        ? MarketplaceColors.destructive.color
                        : MarketplaceColors.dastakAccent.color
                )
                .frame(width: 36, height: 36)
                .background(
                    (isDestructive
                        ? MarketplaceColors.destructive.color
                        : MarketplaceColors.dastakAccent.color
                    ).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
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
                Text(value).font(.subheadline).foregroundStyle(.secondary)
            }
            if showsDisclosure {
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
        .contentShape(Rectangle())
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Account controls").font(MarketplaceTypography.sectionTitle)
            VStack(spacing: 0) {
                Button { accountAlert = .signOut } label: {
                    row(
                        title: "Sign out",
                        value: "End this session on this device",
                        symbol: "rectangle.portrait.and.arrow.right",
                        showsDisclosure: true
                    )
                }
                if allowsAccountDeletion {
                    Divider().padding(.leading, 56)
                    Button(role: .destructive) { accountAlert = .deleteAccount } label: {
                        row(
                            title: model.isDeleting ? "Deleting account..." : "Delete account",
                            value: "Permanently remove your Dastak account",
                            symbol: "trash",
                            showsDisclosure: true,
                            isDestructive: true
                        )
                    }
                    .disabled(model.isDeleting)
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private func credentialRow(
        title: String,
        value: String,
        detail: String? = nil,
        symbol: String
    ) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 40)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: MarketplaceSpacing.compact)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 54)
    }

    private func accountError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MarketplaceColors.destructive.color)
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Button("Try again") { Task { await model.load() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            Spacer()
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
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

    private var profileSubtitle: String {
        roleName == "Merchant"
            ? "Keep your store contact accurate."
            : roleName == "Delivery Partner"
                ? "Keep your delivery contact accurate."
                : "Keep this account's contact accurate."
    }

    private var contactPrivacyMessage: String {
        roleName == "Merchant"
            ? "Used only when an active order requires store contact. It is not used to sign in."
            : roleName == "Delivery Partner"
                ? "Shared only during an assigned delivery when contact is required. It is not used to sign in."
                : "Used only when an active task requires contact. It is not used to sign in."
    }

    private var accountIntroduction: String {
        roleName == "Delivery Partner"
            ? "Manage the identity, verified work details and permissions used while you deliver."
            : "Manage your identity, permissions and account access."
    }

    private var profileInitials: String {
        let words = (model.customer?.displayName ?? roleName)
            .split(separator: " ")
            .prefix(2)
        let initials = words.compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? "D" : initials.uppercased()
    }

    private var partnerStatusTitle: String {
        guard let state = model.deliveryPartner?.onboardingState else {
            return model.isLoading ? "Checking partner access" : "Partner access unavailable"
        }
        return switch state {
        case .approved: "Verified partner"
        case .pending: "Review in progress"
        case .rejected: "Review required"
        case .notApplied: "Application required"
        }
    }

    private var partnerStatusMessage: String {
        guard let state = model.deliveryPartner?.onboardingState else {
            return model.isLoading ? "Loading your approved work details" : "Pull to refresh or try again"
        }
        return switch state {
        case .approved: "Your identity and work method are approved"
        case .pending: "Dastak is reviewing your application"
        case .rejected: model.deliveryPartner?.reviewReason ?? "Update your application for another review"
        case .notApplied: "Complete the partner application to deliver"
        }
    }

    private var partnerStatusSymbol: String {
        switch model.deliveryPartner?.onboardingState {
        case .approved: "checkmark.seal.fill"
        case .pending: "clock.fill"
        case .rejected: "exclamationmark.shield.fill"
        case .notApplied: "doc.badge.plus"
        case nil: "wifi.exclamationmark"
        }
    }

    private var partnerStatusColor: Color {
        switch model.deliveryPartner?.onboardingState {
        case .approved: MarketplaceColors.success.color
        case .pending, .notApplied: MarketplaceColors.warning.color
        case .rejected, nil: MarketplaceColors.destructive.color
        }
    }

    private var partnerAccessLabel: String {
        switch model.deliveryPartner?.onboardingState {
        case .approved: accessLabel
        case .pending: "Pending"
        case .rejected: "Review"
        case .notApplied: "Apply"
        case nil: model.isLoading ? "Checking" : "Unavailable"
        }
    }

    private func deliveryMethodName(_ method: DeliveryMethod) -> String {
        switch method {
        case .walking: "Walking"
        case .bicycle: "Bicycle"
        case .bike: "Motorbike"
        case .auto: "Auto"
        case .car: "Car"
        }
    }

    private func deliveryMethodSymbol(_ method: DeliveryMethod) -> String {
        switch method {
        case .walking: "figure.walk"
        case .bicycle: "bicycle"
        case .bike: "motorcycle"
        case .auto: "car.side"
        case .car: "car"
        }
    }

    private func verificationLabel(_ partner: DeliveryPartnerSnapshot) -> String {
        guard partner.onboardingState == .approved else { return "Not verified" }
        return partner.deliveryMethod?.requiresVehicleVerification == true
            ? "Identity and vehicle verified"
            : "Identity verified"
    }

    private func availabilityLabel(_ partner: DeliveryPartnerSnapshot) -> String {
        partner.availability?.status == .online ? "Online" : "Offline"
    }

    private func makeAccountAlert(_ alert: AccountAlert) -> Alert {
        switch alert {
        case .signOut:
            Alert(
                title: Text("Sign out of Dastak?"),
                message: Text("You'll need to sign in again to access this account."),
                primaryButton: .cancel(Text("Cancel")),
                secondaryButton: .destructive(Text("Sign out")) {
                    Task { await signOut() }
                }
            )
        case .deleteAccount:
            Alert(
                title: Text("Delete your Dastak account?"),
                message: Text("This permanently removes your access and signs you out. Records that must be retained are detached from your identity."),
                primaryButton: .cancel(Text("Cancel")),
                secondaryButton: .destructive(Text("Delete account")) {
                    Task { await deleteAccount() }
                }
            )
        }
    }

    @MainActor
    private func deleteAccount() async {
        do {
            try await model.deleteAccount()
            await signOut()
        } catch {
            model.errorMessage = "Your account could not be deleted. Please try again."
        }
    }
}
