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
    let becomeDeliveryPartner: () -> Void
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
                partnerOpportunity
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
            Text("Saved place")
                .font(MarketplaceTypography.sectionTitle)

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
            .marketplaceFlatSurface()
            .accessibilityHint(location == nil ? "Add a saved delivery address" : "Edit your saved delivery address")
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Support")
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
            Text("Earn with Dastak")
                .font(MarketplaceTypography.sectionTitle)

            Button(action: becomeDeliveryPartner) {
                HStack(spacing: MarketplaceSpacing.compact) {
                    accountIcon("figure.delivery")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Become a Delivery Partner")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Apply once, then choose when you want to earn.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: MarketplaceSpacing.small)
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                .padding(MarketplaceSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    private var accountActions: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Account security")
                .font(MarketplaceTypography.sectionTitle)
            VStack(spacing: 0) {
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
                    Text("Your browse area is stored separately from your saved delivery address. The delivery address is used only for pricing and fulfilling an order. Current location is requested only when you choose to use it.")
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
            "It is shared only when an active delivery requires contact."
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
