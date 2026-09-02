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
    private let persona: MarketplaceDastakPersona?

    init(services: MarketplaceAuthenticatedServices, roleName: String) {
        self.services = services
        profileClient = SupabaseAccountProfileClient(functions: services.functions)
        deliveryPartnerClient = SupabaseDeliveryPartnerClient(functions: services.functions)
        loadsDeliveryPartner = roleName == "Delivery Partner"
        persona = switch roleName {
        case "Merchant": .merchant
        case "Delivery Partner": .delivery
        default: nil
        }
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
        guard let persona else { throw DastakIdentityAccountError.deletionUnavailable }
        try await profileClient.deleteAccount(persona: persona, idempotencyKey: key())
    }

    private func key() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }
}

private enum DastakIdentityAccountError: Error {
    case deletionUnavailable
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
    private let accountSessionClient: any AccountSessionClient
    private let sessionApplicationName: String
    @StateObject private var model: DastakIdentityAccountModel
    @Environment(\.marketplaceSignOut) private var signOut
    @Environment(\.scenePhase) private var scenePhase
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
        accountSessionClient = SupabaseAccountSessionClient(functions: services.functions)
        sessionApplicationName = switch roleName {
        case "Delivery Partner": "Dastak"
        case "Merchant": "Dastak Merchant"
        case "Owner": "Dastak Admin"
        default: "Dastak \(roleName)"
        }
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
                LazyVStack(alignment: .leading, spacing: 26) {
                    rootTitle
                    accountHeading
                    identity
                    if let errorMessage = model.errorMessage {
                        accountError(errorMessage)
                    }
                    if roleName == "Delivery Partner" {
                        partnerCredentials
                    }
                    if roleName == "Merchant" {
                        merchantWorkspace
                    }
                    settings
                    if roleName == "Delivery Partner" {
                        partnerSupport
                    }
                    actions
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.top, MarketplaceSpacing.compact)
                .padding(.bottom, 132)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.load() }
            .dastakNavigationBarHidden()
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { notificationStatus = await DastakNotificationPreferences.status() }
        }
    }

    private var rootTitle: some View {
        Text("Account")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private var accountHeading: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text(roleName == "Delivery Partner" ? "DELIVERY PARTNER" : roleName.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text(roleName == "Merchant" ? "Your store identity" : "Your account")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 36))
            Text(accountIntroduction)
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var identity: some View {
        Button { showsProfileEditor = true } label: {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                HStack(spacing: MarketplaceSpacing.medium) {
                    Text(profileInitials)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .frame(width: 58, height: 58)
                        .background(
                            MarketplaceColors.dastakAccentSoft.color,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.customer?.displayName ?? (model.isLoading ? "Loading account" : roleName))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(roleName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .frame(width: 40, height: 40)
                        .background(MarketplaceColors.dastakAccentSoft.color, in: Circle())
                }

                if model.isLoading {
                    HStack(spacing: MarketplaceSpacing.small) {
                        ProgressView().tint(MarketplaceColors.dastakAccent.color)
                        Text("Loading contact details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Divider()
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                        contactLine(
                            symbol: "phone",
                            value: model.customer?.phoneNumber,
                            fallback: "Add a contact number"
                        )
                        contactLine(
                            symbol: "envelope",
                            value: model.customer?.email,
                            fallback: "Sign-in email unavailable"
                        )
                    }
                }
            }
            .padding(MarketplaceSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isLoading)
        .marketplaceFlatSurface()
        .accessibilityHint("Edit your name and contact number")
    }

    private func contactLine(symbol: String, value: String?, fallback: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 18)
            Text(nonEmpty(value) ?? fallback)
                .font(.subheadline)
                .foregroundStyle(
                    nonEmpty(value) == nil
                        ? Color.secondary.opacity(0.62)
                        : Color.secondary
                )
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
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
                    if partner.deliveryMethod?.requiresVehicleVerification == true {
                        Divider().padding(.leading, 60)
                        credentialRow(
                            title: "Vehicle",
                            value: partner.vehicleMakeModel
                                ?? partner.vehicleRegistrationNumber
                                ?? "Details missing",
                            detail: partner.vehicleMakeModel != nil
                                ? partner.vehicleRegistrationNumber
                                : nil,
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
                    NavigationLink {
                        DastakRoleAccessView(roleName: roleName, accessLabel: accessLabel)
                    } label: {
                        row(
                            title: "Access and approval",
                            value: accessLabel,
                            symbol: "checkmark.shield",
                            showsDisclosure: true
                        )
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                NavigationLink {
                    DastakNotificationSettingsView(
                        roleName: roleName,
                        status: $notificationStatus
                    )
                } label: {
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
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private var merchantWorkspace: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Store workspace").font(MarketplaceTypography.sectionTitle)
            Button(action: openWorkspace) {
                row(
                    title: "Manage your store",
                    value: "Catalogue, availability and store details",
                    symbol: "storefront",
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)
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
                NavigationLink {
                    DastakAccountSessionsView(
                        client: accountSessionClient,
                        applicationName: sessionApplicationName
                    )
                } label: {
                    row(
                        title: "Devices and sessions",
                        value: "Review signed-in devices",
                        symbol: "laptopcomputer.and.iphone",
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 56)
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
                            title: model.isDeleting ? "Deleting \(roleName)..." : "Delete \(roleName)",
                            value: "Remove only this \(roleName.lowercased()) profile and access",
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
                Label("Pull down to try again", systemImage: "arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            Spacer()
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
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
            ? "Manage the identity, work details and permissions used while you deliver."
            : "Manage your identity, permissions and account access."
    }

    private var profileInitials: String {
        let words = (model.customer?.displayName ?? roleName)
            .split(separator: " ")
            .prefix(2)
        let initials = words.compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? "D" : initials.uppercased()
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    private var partnerStatusTitle: String {
        if partnerNeedsVehicleReview { return "Vehicle review required" }
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
        if partnerNeedsVehicleReview {
            return "Vehicle details are missing from this legacy approval"
        }
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
        if partnerNeedsVehicleReview { return "exclamationmark.triangle.fill" }
        return switch model.deliveryPartner?.onboardingState {
        case .approved: "checkmark.seal.fill"
        case .pending: "clock.fill"
        case .rejected: "exclamationmark.shield.fill"
        case .notApplied: "doc.badge.plus"
        case nil: "wifi.exclamationmark"
        }
    }

    private var partnerStatusColor: Color {
        if partnerNeedsVehicleReview { return MarketplaceColors.warning.color }
        return switch model.deliveryPartner?.onboardingState {
        case .approved: MarketplaceColors.success.color
        case .pending, .notApplied: MarketplaceColors.warning.color
        case .rejected, nil: MarketplaceColors.destructive.color
        }
    }

    private var partnerAccessLabel: String {
        if partnerNeedsVehicleReview { return "Action needed" }
        return switch model.deliveryPartner?.onboardingState {
        case .approved: accessLabel
        case .pending: "Pending"
        case .rejected: "Review"
        case .notApplied: "Apply"
        case nil: model.isLoading ? "Checking" : "Unavailable"
        }
    }

    private func deliveryMethodName(_ method: DeliveryMethod) -> String {
        switch method {
        case .retired: "Retired delivery method"
        case .bike, .motorbike: "Motorbike"
        case .scooter: "Scooter"
        case .auto: "Auto"
        case .goodsVehicle: "Tempo / goods vehicle"
        }
    }

    private func deliveryMethodSymbol(_ method: DeliveryMethod) -> String {
        switch method {
        case .retired: "nosign"
        case .bike, .motorbike: "motorcycle"
        case .scooter: "scooter"
        case .auto: "car.side"
        case .goodsVehicle: "truck.box.fill"
        }
    }

    private func verificationLabel(_ partner: DeliveryPartnerSnapshot) -> String {
        guard partner.onboardingState == .approved else { return "Not verified" }
        guard partner.deliveryMethod?.requiresVehicleVerification == true else {
            return "Identity verified"
        }
        return hasCompleteVehicleVerification(partner)
            ? "Identity and vehicle verified"
            : "Vehicle verification required"
    }

    private var partnerNeedsVehicleReview: Bool {
        guard let partner = model.deliveryPartner,
              partner.onboardingState == .approved,
              partner.deliveryMethod?.requiresVehicleVerification == true
        else { return false }
        return !hasCompleteVehicleVerification(partner)
    }

    private func hasCompleteVehicleVerification(_ partner: DeliveryPartnerSnapshot) -> Bool {
        [
            partner.vehicleRegistrationNumber,
            partner.vehicleMakeModel,
            partner.vehicleEvidenceObjectPath
        ].allSatisfy { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
                    Task { await endCurrentSessionAndSignOut() }
                }
            )
        case .deleteAccount:
            Alert(
                title: Text("Delete \(roleName)?"),
                message: Text("Only this \(roleName.lowercased()) profile is removed. Your other Dastak profiles stay available, and this profile can be recovered later."),
                primaryButton: .cancel(Text("Cancel")),
                secondaryButton: .destructive(Text("Delete \(roleName)")) {
                    Task { await deleteAccount() }
                }
            )
        }
    }

    @MainActor
    private func endCurrentSessionAndSignOut() async {
        try? await accountSessionClient.endCurrent(
            idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!
        )
        await signOut()
    }

    @MainActor
    private func deleteAccount() async {
        do {
            try await model.deleteAccount()
            await signOut()
        } catch let error as FunctionClientError {
            if case let .api(_, code, message) = error,
               code == "persona_deletion_blocked" || code == "reauthentication_required" {
                model.errorMessage = message
            } else {
                model.errorMessage = "Your \(roleName) profile could not be deleted. Other profiles are unchanged."
            }
        } catch {
            model.errorMessage = "Your \(roleName) profile could not be deleted. Other profiles are unchanged."
        }
    }
}

private struct DastakRoleAccessView: View {
    let roleName: String
    let accessLabel: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                    Text(roleName.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text("Workspace access")
                        .font(MarketplaceTypography.instrumentSerif(fixedSize: 36))
                    Text("Your permissions are approved by Dastak and cannot be changed from profile details.")
                        .font(MarketplaceTypography.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: MarketplaceSpacing.medium) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(MarketplaceColors.success.color)
                        .frame(width: 48, height: 48)
                        .background(MarketplaceColors.success.color.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Access \(accessLabel.lowercased())")
                            .font(.headline)
                        Text(accessMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(accessLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(MarketplaceColors.success.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(MarketplaceColors.success.color.opacity(0.12), in: Capsule())
                }
                .padding(MarketplaceSpacing.medium)
                .marketplaceFlatSurface()

                VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                    Text("Included workspace").font(MarketplaceTypography.sectionTitle)
                    VStack(spacing: 0) {
                        ForEach(Array(capabilities.enumerated()), id: \.offset) { index, capability in
                            accessRow(capability)
                            if index < capabilities.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .marketplaceFlatSurface()
                }

                Label(
                    "If your access is incorrect, contact Dastak support. Signing out or editing your profile does not change approval.",
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
        .navigationTitle("Access")
        .dastakInlineNavigationTitle()
        .dastakNavigationBarVisible()
    }

    private var capabilities: [(symbol: String, title: String, detail: String)] {
        switch roleName {
        case "Merchant":
            [
                ("list.bullet.clipboard", "Orders", "Receive and manage orders for your approved store."),
                ("square.grid.2x2", "Catalogue", "Maintain products, prices and availability."),
                ("storefront", "Store", "Manage trading status and store details.")
            ]
        case "Admin":
            [
                ("checkmark.shield", "Reviews", "Review marketplace access and submitted evidence."),
                ("chart.bar", "Operations", "Monitor marketplace activity and exceptions."),
                ("gearshape", "Controls", "Manage approved operational settings.")
            ]
        default:
            [
                ("shippingbox", "Deliveries", "Access deliveries assigned to this approved account."),
                ("indianrupeesign", "Earnings", "Review completed delivery earnings."),
                ("person.text.rectangle", "Work profile", "View approved identity and work details.")
            ]
        }
    }

    private var accessMessage: String {
        roleName == "Merchant"
            ? "This account can operate its approved store."
            : "This account can use its approved Dastak workspace."
    }

    private func accessRow(_ capability: (symbol: String, title: String, detail: String)) -> some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: capability.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 36, height: 36)
                .background(
                    MarketplaceColors.dastakAccent.color.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(capability.title).font(.headline)
                Text(capability.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MarketplaceSpacing.compact)
    }
}

private struct DastakNotificationSettingsView: View {
    let roleName: String
    @Binding var status: DastakNotificationPermissionState
    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                    Text("NOTIFICATIONS")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text("Stay ready")
                        .font(MarketplaceTypography.instrumentSerif(fixedSize: 36))
                    Text(introduction)
                        .font(MarketplaceTypography.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: MarketplaceSpacing.medium) {
                    Image(systemName: statusSymbol)
                        .font(.title3)
                        .foregroundStyle(statusColor)
                        .frame(width: 48, height: 48)
                        .background(statusColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle).font(.headline)
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(MarketplaceSpacing.medium)
                .marketplaceFlatSurface()

                VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                    Text("You may receive").font(MarketplaceTypography.sectionTitle)
                    VStack(spacing: 0) {
                        notificationRow("New orders and urgent changes", symbol: "bell.badge")
                        Divider().padding(.leading, 52)
                        notificationRow("Cancellations and pickup updates", symbol: "arrow.triangle.2.circlepath")
                        Divider().padding(.leading, 52)
                        notificationRow("Account and approval updates", symbol: "checkmark.shield")
                    }
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .marketplaceFlatSurface()
                }

                Button(action: managePermission) {
                    HStack {
                        if isRequesting { ProgressView().tint(.black) }
                        Text(primaryActionTitle)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.black)
                .background(MarketplaceColors.dastakAccent.color)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .disabled(isRequesting || status == .unavailable)
                .opacity(status == .unavailable ? 0.5 : 1)

                Label(
                    "Order status remains available inside Dastak even when system notifications are off.",
                    systemImage: "info.circle"
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
        .navigationTitle("Notifications")
        .dastakInlineNavigationTitle()
        .dastakNavigationBarVisible()
        .task { status = await DastakNotificationPreferences.status() }
    }

    private var introduction: String {
        roleName == "Merchant"
            ? "Receive time-sensitive store and order updates without keeping Dastak open."
            : "Receive time-sensitive work and account updates without keeping Dastak open."
    }

    private var statusTitle: String {
        switch status {
        case .notRequested: "Notifications are not set up"
        case .enabled: "Notifications are on"
        case .disabled: "Notifications are off"
        case .unavailable: "Notifications are unavailable"
        }
    }

    private var statusDetail: String {
        switch status {
        case .notRequested: "Allow alerts so important updates reach you promptly."
        case .enabled: "Dastak can send alerts, sounds and badge updates."
        case .disabled: "Turn notifications on in iPhone Settings to receive alerts."
        case .unavailable: "This device does not currently provide notification settings."
        }
    }

    private var statusSymbol: String {
        switch status {
        case .enabled: "bell.badge.fill"
        case .disabled: "bell.slash.fill"
        case .notRequested: "bell.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .enabled: MarketplaceColors.success.color
        case .notRequested: MarketplaceColors.dastakAccent.color
        case .disabled, .unavailable: MarketplaceColors.warning.color
        }
    }

    private var primaryActionTitle: String {
        switch status {
        case .notRequested: "Enable notifications"
        case .enabled, .disabled: "Open iPhone Settings"
        case .unavailable: "Unavailable on this device"
        }
    }

    private func notificationRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 36)
            Text(title).font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
        .frame(minHeight: 54)
    }

    private func managePermission() {
        switch status {
        case .notRequested:
            isRequesting = true
            Task {
                status = await DastakNotificationPreferences.request()
                isRequesting = false
            }
        case .enabled, .disabled:
            DastakNotificationPreferences.openSystemSettings()
        case .unavailable:
            break
        }
    }
}
