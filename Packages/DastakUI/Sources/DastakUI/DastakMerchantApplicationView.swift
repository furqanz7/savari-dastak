import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class DastakMerchantApplicationModel: ObservableObject {
    static let maximumBusinessNameLength = 120
    static let maximumBusinessAddressLength = 300
    static let maximumLegalNameLength = 160

    @Published var merchantType: MerchantType?
    @Published var legalName = ""
    @Published var businessName = ""
    @Published var businessAddress = ""
    @Published private(set) var selectedLocation: DastakDeliveryLocation?
    @Published private(set) var evidenceName: String?
    @Published private(set) var onboardingState: MerchantOnboardingState = .notApplied
    @Published private(set) var applicationID: UUID?
    @Published private(set) var reviewReason: String?
    @Published private(set) var isSubmitting = false
    @Published private(set) var isLoading = true
    @Published private(set) var loadErrorMessage: String?
    @Published var submissionErrorMessage: String?

    private let services: MarketplaceAuthenticatedServices
    private let applicationClient: any MerchantApplicationClient
    private var evidenceData: Data?
    private var evidenceContentType: String?
    private var submissionKey: IdempotencyKey?
    private var uploadedEvidence: (fingerprint: String, path: String)?

    init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        applicationClient = SupabaseMerchantApplicationClient(functions: services.functions)
    }

    var normalizedBusinessName: String {
        businessName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLegalName: String {
        legalName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBusinessAddress: String {
        businessAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        merchantType != nil
            && !normalizedLegalName.isEmpty
            && normalizedLegalName.count <= Self.maximumLegalNameLength
            && !normalizedBusinessName.isEmpty
            && normalizedBusinessName.count <= Self.maximumBusinessNameLength
            && !normalizedBusinessAddress.isEmpty
            && normalizedBusinessAddress.count <= Self.maximumBusinessAddressLength
            && selectedLocation != nil
            && evidenceData != nil
            && loadErrorMessage == nil
            && !isSubmitting
            && !isLoading
    }

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        submissionErrorMessage = nil
        defer { isLoading = false }

        do {
            let key = IdempotencyKey(rawValue: UUID().uuidString)!
            let snapshot = try await applicationClient.selfSnapshot(idempotencyKey: key)
            onboardingState = snapshot.onboardingState
            applicationID = snapshot.applicationID
            reviewReason = snapshot.reviewReason
            merchantType = snapshot.merchantType
            if let snapshotLegalName = snapshot.legalName, !snapshotLegalName.isEmpty {
                legalName = snapshotLegalName
            }
            if let snapshotName = snapshot.businessName, !snapshotName.isEmpty {
                businessName = snapshotName
            }
            if let snapshotAddress = snapshot.businessAddress, !snapshotAddress.isEmpty {
                businessAddress = snapshotAddress
            }
            if let latitude = snapshot.latitude,
               let longitude = snapshot.longitude,
               let address = snapshot.businessAddress {
                selectedLocation = DastakDeliveryLocation(
                    address: address,
                    point: GeoPoint(latitude: latitude, longitude: longitude)
                )
            }
        } catch {
            loadErrorMessage = "We could not check your merchant application. Check your connection and try again."
        }
    }

    func updateBusinessName(_ value: String) {
        businessName = String(value.prefix(Self.maximumBusinessNameLength))
        submissionKey = nil
        submissionErrorMessage = nil
    }

    func updateLegalName(_ value: String) {
        legalName = String(value.prefix(Self.maximumLegalNameLength))
        submissionKey = nil
        submissionErrorMessage = nil
    }

    func selectMerchantType(_ value: MerchantType) {
        merchantType = value
        submissionKey = nil
        submissionErrorMessage = nil
    }

    func updateBusinessAddress(_ value: String) {
        businessAddress = String(value.prefix(Self.maximumBusinessAddressLength))
        submissionKey = nil
        submissionErrorMessage = nil
    }

    func selectLocation(_ location: DastakDeliveryLocation) {
        selectedLocation = location
        if normalizedBusinessAddress.isEmpty {
            businessAddress = String(location.address.prefix(Self.maximumBusinessAddressLength))
        }
        submissionKey = nil
        submissionErrorMessage = nil
    }

    func selectEvidence(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let values = try url.resourceValues(forKeys: [.contentTypeKey])
            guard data.count > 0,
                  data.count <= 10 * 1_024 * 1_024,
                  let contentType = values.contentType?.preferredMIMEType,
                  Self.evidenceExtension(contentType) != nil
            else {
                throw DastakMerchantApplicationError.invalidEvidence
            }
            evidenceData = data
            evidenceContentType = contentType
            evidenceName = url.lastPathComponent
            uploadedEvidence = nil
            submissionKey = nil
            submissionErrorMessage = nil
        } catch {
            clearEvidence()
            submissionErrorMessage = "Choose a PDF, JPG, or PNG document up to 10 MB."
        }
    }

    func clearEvidence() {
        evidenceData = nil
        evidenceContentType = nil
        evidenceName = nil
        uploadedEvidence = nil
        submissionKey = nil
    }

    @discardableResult
    func submit() async -> Bool {
        guard canSubmit,
              let merchantType,
              let selectedLocation,
              let evidenceData,
              let evidenceContentType,
              let fileExtension = Self.evidenceExtension(evidenceContentType)
        else { return false }
        isSubmitting = true
        submissionErrorMessage = nil
        defer { isSubmitting = false }

        do {
            let fingerprint = "\(evidenceData.count):\(evidenceData.hashValue):\(evidenceContentType)"
            let evidencePath: String
            if let uploadedEvidence, uploadedEvidence.fingerprint == fingerprint {
                evidencePath = uploadedEvidence.path
            } else {
                let accountID = try await services.accountID()
                evidencePath = [
                    "merchant",
                    accountID.uuidString.lowercased(),
                    "\(UUID().uuidString.lowercased()).\(fileExtension)"
                ].joined(separator: "/")
                try await services.uploadObject(
                    bucket: "dastak-evidence",
                    path: evidencePath,
                    data: evidenceData,
                    contentType: evidenceContentType
                )
                uploadedEvidence = (fingerprint, evidencePath)
            }

            let key = submissionKey ?? IdempotencyKey(rawValue: UUID().uuidString)!
            submissionKey = key
            let result = try await applicationClient.submit(
                merchantType: merchantType,
                legalName: normalizedLegalName,
                businessName: normalizedBusinessName,
                businessAddress: normalizedBusinessAddress,
                latitude: selectedLocation.point.latitude,
                longitude: selectedLocation.point.longitude,
                evidenceObjectPath: evidencePath,
                idempotencyKey: key
            )
            applicationID = result.applicationID
            submissionKey = nil
            onboardingState = .pending
            reviewReason = nil
            return true
        } catch let error as FunctionClientError {
            if case let .api(_, _, message) = error {
                submissionErrorMessage = message
            } else {
                submissionErrorMessage = "The merchant application could not be submitted. Try again."
            }
        } catch {
            submissionErrorMessage = "The merchant application could not be submitted. Try again."
        }
        return false
    }

    private static func evidenceExtension(_ contentType: String) -> String? {
        switch contentType.lowercased() {
        case "application/pdf": "pdf"
        case "image/jpeg": "jpg"
        case "image/png": "png"
        default: nil
        }
    }
}

private enum DastakMerchantApplicationError: Error {
    case invalidEvidence
}

enum DastakMerchantAccessPresentation: Equatable {
    case loading
    case application
    case pending
    case approved
    case suspended
    case loadFailure
    case unavailable

    static func resolve(
        route: AccountRoute,
        onboardingState: MerchantOnboardingState,
        isLoading: Bool,
        hasLoadError: Bool
    ) -> Self {
        if route == .suspended { return .suspended }
        if isLoading { return .loading }
        if route == .pendingApproval { return .pending }
        if hasLoadError { return .loadFailure }
        switch onboardingState {
        case .notApplied, .rejected: return route == .accessDenied ? .application : .unavailable
        case .pending: return .pending
        case .approved: return .approved
        }
    }
}

public struct DastakMerchantAccessView: View {
    private enum Field: Hashable {
        case legalName
        case businessName
        case businessAddress
    }

    private let route: AccountRoute
    @StateObject private var model: DastakMerchantApplicationModel
    @StateObject private var locationManager = DastakLocationManager()
    @Environment(\.marketplaceSignOut) private var signOut
    @Environment(\.marketplaceAccessRefresh) private var refreshAccess
    @State private var showsImporter = false
    @State private var showsLocationPicker = false
    @State private var showsSignOutConfirmation = false
    @FocusState private var focusedField: Field?

    public init(route: AccountRoute, services: MarketplaceAuthenticatedServices) {
        self.route = route
        _model = StateObject(
            wrappedValue: DastakMerchantApplicationModel(services: services)
        )
    }

    public var body: some View {
        ZStack {
            DastakMatteBackground(style: .dark).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(MarketplaceColors.dividerDark.color)

                ScrollView {
                    content
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 26)
                        .padding(.bottom, presentation == .application ? 112 : 36)
                        .frame(maxWidth: .infinity)
                }
                .refreshable { await refreshApplicationAndAccess() }
#if os(iOS)
                .scrollDismissesKeyboard(.interactively)
#endif
            }
        }
        .foregroundStyle(MarketplaceColors.dastakText.color)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presentation == .application { submissionBar }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .task { await model.load() }
        .task(id: presentation) {
            guard presentation == .pending || presentation == .approved else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await refreshApplicationAndAccess()
            }
        }
        .sheet(isPresented: $showsLocationPicker) {
            DastakLocationPicker(
                title: "Store location",
                currentLocation: model.selectedLocation ?? locationManager.location,
                useLocation: model.selectLocation,
                requestCurrentLocation: locationManager.requestLocation
            )
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.pdf, .jpeg, .png],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { model.selectEvidence(url: url) }
            case let .failure(error):
                guard (error as NSError).code != NSUserCancelledError else { return }
                model.submissionErrorMessage = "The selected document could not be opened."
            }
        }
        .confirmationDialog(
            "Use a different account?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) { Task { await signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to return to this merchant application.")
        }
    }

    private var presentation: DastakMerchantAccessPresentation {
        .resolve(
            route: route,
            onboardingState: model.onboardingState,
            isLoading: model.isLoading,
            hasLoadError: model.loadErrorMessage != nil
        )
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                DastakWordmark(size: 29)
                Text("MERCHANT")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }

            Spacer(minLength: 16)

            Button {
                focusedField = nil
                showsSignOutConfirmation = true
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
            .accessibilityLabel("Use a different account")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: 604)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .loading:
            loadingView
        case .application:
            applicationForm
        case .pending:
            statusView(
                symbol: "clock.badge.checkmark",
                eyebrow: "APPLICATION RECEIVED",
                title: "Your store is under review",
                message: "We'll unlock the merchant workspace as soon as the application is approved.",
                progressStep: 3
            )
        case .approved:
            statusView(
                symbol: "checkmark.seal.fill",
                eyebrow: "APPROVED",
                title: "Your merchant access is ready",
                message: "Your workspace will open automatically. Pull down if you want to check immediately.",
                progressStep: 3
            )
        case .suspended:
            statusView(
                symbol: "exclamationmark.shield",
                eyebrow: "ACCESS PAUSED",
                title: "Merchant access is suspended",
                message: "Your store workspace is unavailable while this account is being reviewed.",
                progressStep: nil
            )
        case .loadFailure:
            statusView(
                symbol: "wifi.exclamationmark",
                eyebrow: "CONNECTION ISSUE",
                title: "We couldn't check your application",
                message: model.loadErrorMessage ?? "Pull down to try again when your connection is stable.",
                progressStep: nil
            )
        case .unavailable:
            statusView(
                symbol: "lock.shield",
                eyebrow: "ACCESS UNAVAILABLE",
                title: "This account cannot open Merchant",
                message: "Pull down to check access or use the account linked to your store.",
                progressStep: nil
            )
        }
    }

    private var loadingView: some View {
        VStack(spacing: 18) {
            ProgressView().tint(MarketplaceColors.dastakAccent.color)
            Text("Checking your merchant application")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .combine)
    }

    private var applicationForm: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.onboardingState == .rejected ? "APPLICATION UPDATE" : "MERCHANT REGISTRATION")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(model.onboardingState == .rejected ? "Update your store application" : "Bring your store to Dastak")
                    .font(MarketplaceTypography.instrumentSerif(fixedSize: 43))
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.onboardingState == .rejected
                    ? "Make the requested changes and send the application back for review."
                    : "Add the store customers know, then verify that you own or operate it.")
                    .font(.subheadline)
                    .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DastakApplicationProgress(currentStep: 2)

            if let reviewReason = model.reviewReason, !reviewReason.isEmpty {
                applicationNotice(
                    symbol: "text.bubble.fill",
                    title: "Changes requested",
                    message: reviewReason,
                    color: MarketplaceColors.dastakAccent.color
                )
            }

            formSection(
                symbol: "square.grid.2x2",
                title: "Business type",
                message: "This selects the catalogue and order tools your branch receives after approval."
            ) {
                HStack(spacing: 10) {
                    merchantTypeButton(
                        .restaurantCafe,
                        symbol: "fork.knife",
                        title: "Restaurant or cafe",
                        detail: "Menus and food options"
                    )
                    merchantTypeButton(
                        .retail,
                        symbol: "basket",
                        title: "Retail store",
                        detail: "Canonical retail SKUs"
                    )
                }
            }

            formSection(
                symbol: "storefront",
                title: "Business and branch",
                message: "Tell Admin who operates it and what customers should see."
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    fieldLabel("Legal business name", count: model.legalName.count, maximum: DastakMerchantApplicationModel.maximumLegalNameLength)
                    TextField("Name on your registration document", text: Binding(
                        get: { model.legalName },
                        set: { model.updateLegalName($0) }
                    ))
                    .textContentType(.organizationName)
#if os(iOS)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .businessName }
#endif
                    .focused($focusedField, equals: .legalName)
                    .merchantTextField()
                }

                VStack(alignment: .leading, spacing: 9) {
                    fieldLabel("Customer-facing name", count: model.businessName.count, maximum: DastakMerchantApplicationModel.maximumBusinessNameLength)
                    TextField("Store name", text: Binding(
                        get: { model.businessName },
                        set: { model.updateBusinessName($0) }
                    ))
                    .textContentType(.organizationName)
#if os(iOS)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .businessAddress }
#endif
                    .focused($focusedField, equals: .businessName)
                    .merchantTextField()
                }

                VStack(alignment: .leading, spacing: 9) {
                    fieldLabel("Business address", count: model.businessAddress.count, maximum: DastakMerchantApplicationModel.maximumBusinessAddressLength)
                    TextField(
                        "Shop number, street, area and city",
                        text: Binding(
                            get: { model.businessAddress },
                            set: { model.updateBusinessAddress($0) }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                    .textContentType(.fullStreetAddress)
                    .focused($focusedField, equals: .businessAddress)
                    .merchantTextField(minimumHeight: 104, alignment: .topLeading)
                }
            }

            formSection(
                symbol: "mappin.and.ellipse",
                title: "Exact store location",
                message: "Required to connect this branch to the correct Dastak service area."
            ) {
                Button {
                    focusedField = nil
                    showsLocationPicker = true
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: model.selectedLocation == nil ? "mappin.circle" : "checkmark.circle.fill")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .frame(width: 42, height: 42)
                            .background(MarketplaceColors.dastakAccentSoft.color)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.selectedLocation == nil ? "Choose store location" : "Store pin selected")
                                .font(.subheadline.weight(.semibold))
                            Text(model.selectedLocation?.address ?? "Search an address or use the current location")
                                .font(.caption)
                                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .merchantSurface()
            }

            formSection(
                symbol: "checkmark.shield",
                title: "Store verification",
                message: "Upload one government identity or business registration document."
            ) {
                Button {
                    focusedField = nil
                    showsImporter = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: model.evidenceName == nil ? "doc.badge.plus" : "doc.badge.checkmark.fill")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .frame(width: 42, height: 42)
                            .background(MarketplaceColors.dastakAccentSoft.color)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.evidenceName ?? "Choose a document")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MarketplaceColors.dastakText.color)
                                .lineLimit(1)
                            Text(model.evidenceName == nil ? "PDF, JPG or PNG, up to 10 MB" : "Tap to replace")
                                .font(.caption)
                                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .merchantSurface()

                if model.evidenceName != nil {
                    Button(role: .destructive) { model.clearEvidence() } label: {
                        Label("Remove document", systemImage: "trash")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MarketplaceColors.destructive.color)
                    .frame(minHeight: 44)
                }

                Label(
                    "Your document stays private and is used only for merchant verification.",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let message = model.submissionErrorMessage {
                applicationNotice(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Application not sent",
                    message: message,
                    color: MarketplaceColors.destructive.color
                )
            }
        }
    }

    private var submissionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(MarketplaceColors.dividerDark.color)
            Button {
                focusedField = nil
                Task {
                    if await model.submit() { await refreshAccess() }
                }
            } label: {
                HStack(spacing: 10) {
                    if model.isSubmitting { ProgressView().tint(MarketplaceColors.dastakIconBackground.color) }
                    Text(model.isSubmitting
                        ? "Submitting application"
                        : model.onboardingState == .rejected ? "Resubmit for review" : "Submit for review")
                }
            }
            .buttonStyle(DastakMerchantPrimaryButtonStyle())
            .disabled(!model.canSubmit)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: 604)
            .frame(maxWidth: .infinity)
        }
        .background(.ultraThinMaterial)
    }

    private func statusView(
        symbol: String,
        eyebrow: String,
        title: String,
        message: String,
        progressStep: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 54, height: 54)
                .background(MarketplaceColors.dastakAccentSoft.color)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(title)
                    .font(MarketplaceTypography.instrumentSerif(fixedSize: 43))
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let progressStep { DastakApplicationProgress(currentStep: progressStep) }

            if let businessName = nonEmpty(model.businessName) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("STORE").font(.caption2.weight(.semibold)).tracking(1)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text(businessName).font(.headline)
                    if let businessAddress = nonEmpty(model.businessAddress) {
                        Text(businessAddress)
                            .font(.subheadline)
                            .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .merchantSurface()
            }

            Label("Pull down to check now. Dastak also checks automatically.", systemImage: "arrow.down")
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
    }

    private func refreshApplicationAndAccess() async {
        await model.load()
        await refreshAccess()
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func merchantTypeButton(
        _ type: MerchantType,
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        let selected = model.merchantType == type
        return Button {
            model.selectMerchantType(type)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .medium))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                }
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakText.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(selected ? MarketplaceColors.dastakAccentSoft.color : MarketplaceColors.dastakSurface.color)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? MarketplaceColors.dastakAccent.color : MarketplaceColors.dividerDark.color, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func fieldLabel(_ title: String, count: Int, maximum: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(count)/\(maximum)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
        }
    }

    private func formSection<Content: View>(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 34, height: 34)
                    .background(MarketplaceColors.dastakAccentSoft.color)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(.top, 24)
        .overlay(alignment: .top) {
            Rectangle().fill(MarketplaceColors.dividerDark.color).frame(height: 1)
        }
    }

    private func applicationNotice(
        symbol: String,
        title: String,
        message: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct DastakMerchantPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(MarketplaceColors.dastakIconBackground.color)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(MarketplaceColors.dastakAccent.color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private extension View {
    func merchantSurface() -> some View {
        background(MarketplaceColors.dastakSurface.color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MarketplaceColors.dividerDark.color, lineWidth: 1)
            }
    }

    func merchantTextField(
        minimumHeight: CGFloat = 56,
        alignment: Alignment = .center
    ) -> some View {
        padding(.horizontal, 15)
            .padding(.vertical, minimumHeight > 60 ? 14 : 0)
            .frame(minHeight: minimumHeight, alignment: alignment)
            .merchantSurface()
    }
}
