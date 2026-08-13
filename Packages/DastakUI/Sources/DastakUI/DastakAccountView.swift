import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakAccountView: View {
    let customer: MarketplaceCheckoutCustomer?
    let location: DastakDeliveryLocation?
    let discoveryRadiusKilometres: Int
    let refreshFailure: DastakCustomerRefreshFailure?
    let chooseLocation: () -> Void
    let retryAccount: () -> Void
    let updateProfile: (String, String) async throws -> Void
    let deleteAccount: () async throws -> Void

    @Environment(\.marketplaceSignOut) private var signOut
    @State private var showingProfileEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                profileSection
                if let refreshFailure {
                    DastakRefreshNotice(failure: refreshFailure, action: retryAccount)
                }
                deliverySection
                supportSection
                accountActions
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.top, MarketplaceSpacing.medium)
            .padding(.bottom, MarketplaceSpacing.xxLarge)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Account")
        .sheet(isPresented: $showingProfileEditor) {
            DastakProfileEditor(customer: customer, updateProfile: updateProfile)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete your Dastak account?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await performAccountDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs you out and permanently removes your account. Completed order records are retained without your identity where legally required.")
        }
        .alert("Dastak", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Personal details")
                .font(MarketplaceTypography.sectionTitle)

            Button { showingProfileEditor = true } label: {
                HStack(spacing: MarketplaceSpacing.compact) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(customer?.displayName ?? "Your account")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(customer?.phoneNumber ?? "Phone number unavailable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let email = customer?.email, !email.isEmpty {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(MarketplaceSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .marketplaceFlatSurface()
        }
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Delivery")
                .font(MarketplaceTypography.sectionTitle)

            Button(action: chooseLocation) {
                VStack(spacing: MarketplaceSpacing.medium) {
                    HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location?.displayName ?? "Add delivery address")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(location?.displayAddress ?? "Add a house, flat or landmark")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        Spacer(minLength: MarketplaceSpacing.small)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Divider()
                    HStack {
                        Label("Delivery range", systemImage: "scope")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(discoveryRadiusKilometres) km")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
                .padding(MarketplaceSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .marketplaceFlatSurface()
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Support")
                .font(MarketplaceTypography.sectionTitle)
            Link(destination: URL(string: "tel:112")!) {
                Label("Emergency assistance", systemImage: "sos")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MarketplaceSpacing.medium)
            }
            .foregroundStyle(MarketplaceColors.destructive.color)
            .marketplaceFlatSurface()
        }
    }

    private var accountActions: some View {
        VStack(spacing: 0) {
            Button {
                Task { await signOut() }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
            }
            Divider()
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label(isDeleting ? "Deleting account..." : "Delete account", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
            }
            .disabled(isDeleting)
        }
        .font(.headline)
        .padding(.horizontal, MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    @MainActor
    private func performAccountDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await deleteAccount()
        } catch {
            errorMessage = "Your account could not be deleted. Please try again."
        }
    }
}

private struct DastakProfileEditor: View {
    let customer: MarketplaceCheckoutCustomer?
    let updateProfile: (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var phoneNumber: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        customer: MarketplaceCheckoutCustomer?,
        updateProfile: @escaping (String, String) async throws -> Void
    ) {
        self.customer = customer
        self.updateProfile = updateProfile
        _displayName = State(initialValue: customer?.displayName ?? "")
        _phoneNumber = State(initialValue: customer?.phoneNumber ?? "+91")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal details") {
                    TextField("Full name", text: $displayName)
                        .textContentType(.name)
#if os(iOS)
                    TextField("Phone number with country code", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
#else
                    TextField("Phone number with country code", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
#endif
                }
                Section {
                    Text("Your phone number is shared only when needed for an active delivery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(MarketplaceColors.destructive.color) }
                }
            }
            .navigationTitle("Edit profile")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private var isValid: Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(name.count)
            && phone.range(of: #"^\+[1-9][0-9]{7,14}$"#, options: .regularExpression) != nil
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
