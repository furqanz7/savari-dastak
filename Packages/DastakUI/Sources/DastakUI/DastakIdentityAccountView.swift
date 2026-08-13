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
    private let roleName: String
    private let accessLabel: String
    private let allowsAccountDeletion: Bool
    @StateObject private var model: DastakIdentityAccountModel
    @Environment(\.marketplaceSignOut) private var signOut
    @State private var showsProfileEditor = false
    @State private var showsDeleteConfirmation = false

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
                DastakProfileEditor(customer: model.customer) { name, phone in
                    try await model.update(displayName: name, phoneNumber: phone)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Delete your Dastak account?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your access and signs you out. Records that must be retained are detached from your identity.")
            }
        }
        .marketplacePage()
        .task { await model.load() }
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
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
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
                Button(action: DastakNotificationPreferences.openSystemSettings) {
                    row(title: "Language", value: "Follows iPhone", symbol: "globe")
                }
                .buttonStyle(.plain)
                Divider()
                NavigationLink {
                    DastakPrivacyAndDataView()
                } label: {
                    row(title: "Privacy and data", value: nil, symbol: "hand.raised")
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private func row(title: String, value: String?, symbol: String) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 24)
            Text(title).font(.headline).foregroundStyle(.primary)
            Spacer()
            if let value { Text(value).font(.subheadline).foregroundStyle(.secondary) }
            if value == nil {
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
        .contentShape(Rectangle())
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Button { Task { await signOut() } } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
            }
            if allowsAccountDeletion {
                Divider()
                Button(role: .destructive) { showsDeleteConfirmation = true } label: {
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
