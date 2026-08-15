import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

@MainActor
private final class DastakIdentityAccountModel: ObservableObject {
    @Published private(set) var customer: MarketplaceCheckoutCustomer?
    @Published private(set) var isLoading = true
    @Published private(set) var isDeleting = false
    @Published var errorMessage: String?

    private let services: MarketplaceAuthenticatedServices
    private let profileClient: any AccountProfileClient

    init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        profileClient = SupabaseAccountProfileClient(functions: services.functions)
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
    @StateObject private var model: DastakIdentityAccountModel
    @Environment(\.marketplaceSignOut) private var signOut
    @State private var showsProfileEditor = false
    @State private var accountAlert: AccountAlert?
    @State private var notificationStatus: DastakNotificationPermissionState = .notRequested

    public init(
        roleName: String,
        accessLabel: String = "Active",
        allowsAccountDeletion: Bool = true,
        services: MarketplaceAuthenticatedServices
    ) {
        self.roleName = roleName
        self.accessLabel = accessLabel
        self.allowsAccountDeletion = allowsAccountDeletion
        _model = StateObject(wrappedValue: DastakIdentityAccountModel(services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    identity
                    settings
                    actions
                    if let errorMessage = model.errorMessage {
                        Button("Try again") { Task { await model.load() } }
                            .buttonStyle(MarketplaceSecondaryButtonStyle())
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(MarketplaceColors.destructive.color)
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(MarketplaceSpacing.medium)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
            }
            .navigationTitle("Account")
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

    private var identity: some View {
        Button { showsProfileEditor = true } label: {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.customer?.displayName ?? (model.isLoading ? "Loading account" : roleName))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(roleName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let phone = model.customer?.phoneNumber {
                        Text(phone).font(.caption).foregroundStyle(.secondary)
                    }
                    if let email = model.customer?.email, !email.isEmpty {
                        Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(accessLabel)
                        .font(.caption.bold())
                        .foregroundStyle(MarketplaceColors.success.color)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(MarketplaceSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marketplaceFlatSurface()
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Settings").font(MarketplaceTypography.sectionTitle)
            VStack(spacing: 0) {
                row(title: "Access", value: accessLabel, symbol: "checkmark.shield")
                Divider()
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

    private func row(
        title: String,
        value: String?,
        symbol: String,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 24)
            Text(title).font(.headline).foregroundStyle(.primary)
            Spacer()
            if let value { Text(value).font(.subheadline).foregroundStyle(.secondary) }
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
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
                }
                if allowsAccountDeletion {
                    Divider()
                    Button(role: .destructive) { accountAlert = .deleteAccount } label: {
                        Label(model.isDeleting ? "Deleting account..." : "Delete account", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
                    }
                    .disabled(model.isDeleting)
                }
            }
            .font(.headline)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
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
