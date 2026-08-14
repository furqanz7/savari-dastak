import MarketplaceDesignSystem
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
    let discoveryRadiusKilometres: Int
    let refreshFailure: DastakCustomerRefreshFailure?
    let chooseLocation: () -> Void
    let openOrders: () -> Void
    let retryAccount: () -> Void
    let updateProfile: (String, String) async throws -> Void
    let deleteAccount: () async throws -> Void

    @Environment(\.marketplaceSignOut) private var signOut
    @State private var showingProfileEditor = false
    @State private var accountAlert: AccountAlert?
    @State private var isDeleting = false
    @State private var notificationStatus: DastakNotificationPermissionState = .notRequested

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                profileSection
                if let refreshFailure {
                    DastakRefreshNotice(failure: refreshFailure, action: retryAccount)
                }
                deliverySection
                preferencesSection
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $accountAlert, content: makeAccountAlert)
        .task {
            notificationStatus = await DastakNotificationPreferences.status()
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
            Button(action: openOrders) {
                Label("Help with an order", systemImage: "questionmark.bubble")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
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
                Divider()
                Button(action: DastakNotificationPreferences.openSystemSettings) {
                    accountRow(title: "Language", value: "Follows iPhone", symbol: "globe")
                }
                .buttonStyle(.plain)
                Divider()
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

    private func accountRow(title: String, value: String?, symbol: String) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 24)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
        .contentShape(Rectangle())
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
        VStack(spacing: 0) {
            Button { accountAlert = .signOut } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
            }
            Divider()
            Button(role: .destructive) { accountAlert = .deleteAccount } label: {
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

    private func makeAccountAlert(_ alert: AccountAlert) -> Alert {
        switch alert {
        case .signOut:
            Alert(
                title: Text("Sign out of Dastak?"),
                message: Text("You'll need to sign in again to access your account and orders."),
                primaryButton: .cancel(Text("Cancel")),
                secondaryButton: .destructive(Text("Sign out")) {
                    Task { await signOut() }
                }
            )
        case .deleteAccount:
            Alert(
                title: Text("Delete your Dastak account?"),
                message: Text("This permanently deletes your account and signs you out. Completed order records may be retained without your identity where legally required."),
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
        List {
            Section("Contact") {
                Text("Your phone number is unverified at launch and is not used to sign in, recover your account, or prove payment.")
                Text(contactMessage)
            }
            if roleName == nil {
                Section("Location") {
                    Text("Your saved delivery address is used for discovery, pricing and fulfilment. Current location is requested only when you choose to use it.")
                }
            } else {
                Section("Role access") {
                    Text("Dastak uses owner-approved access to decide which workspace this account can open. Profile details cannot grant or change that access.")
                }
            }
            Section("Control") {
                Text(controlMessage)
            }
        }
        .navigationTitle("Privacy and data")
    }

    private var contactMessage: String {
        switch roleName {
        case "Merchant":
            "It is shared only when an active order requires store contact."
        case "Delivery Partner":
            "It is shared only during an assigned delivery when customer, merchant, or partner contact is required."
        default:
            "It is shared only when an active delivery requires customer and partner contact."
        }
    }

    private var controlMessage: String {
        roleName == nil
            ? "You can edit your profile and delivery address, change permissions in iPhone Settings, sign out, or permanently delete your account from Account."
            : "You can edit your profile, change permissions in iPhone Settings, sign out, or permanently delete your account from Account."
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
            && phone.range(of: #"^\+[1-9][0-9]{7,14}$"#, options: .regularExpression) != nil
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
