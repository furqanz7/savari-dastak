import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class DastakMerchantApplicationModel: ObservableObject {
    @Published var businessName = ""
    @Published var businessAddress = ""
    @Published private(set) var evidenceName: String?
    @Published private(set) var isSubmitting = false
    @Published private(set) var isSubmitted = false
    @Published private(set) var isLoading = true
    @Published private(set) var isRejected = false
    @Published private(set) var reviewReason: String?
    @Published var errorMessage: String?

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

    var canSubmit: Bool {
        !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !businessAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && evidenceData != nil
            && !isSubmitting
            && !isLoading
    }

    func load() async {
        do {
            let key = IdempotencyKey(rawValue: UUID().uuidString)!
            let snapshot = try await applicationClient.selfSnapshot(idempotencyKey: key)
            if snapshot.onboardingState == .rejected {
                businessName = snapshot.businessName ?? ""
                businessAddress = snapshot.businessAddress ?? ""
                reviewReason = snapshot.reviewReason
                isRejected = true
            }
            errorMessage = nil
        } catch {
            errorMessage = "Your merchant application could not be loaded. You can still enter the details again."
        }
        isLoading = false
    }

    func selectEvidence(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
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
            errorMessage = nil
        } catch {
            evidenceData = nil
            evidenceContentType = nil
            evidenceName = nil
            errorMessage = "Choose a PDF, JPG, or PNG document up to 10 MB."
        }
    }

    func submit() async {
        guard canSubmit,
              let evidenceData,
              let evidenceContentType,
              let fileExtension = Self.evidenceExtension(evidenceContentType)
        else { return }
        isSubmitting = true
        errorMessage = nil
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
            _ = try await applicationClient.submit(
                businessName: businessName,
                businessAddress: businessAddress,
                evidenceObjectPath: evidencePath,
                idempotencyKey: key
            )
            submissionKey = nil
            isSubmitted = true
            isRejected = false
            reviewReason = nil
        } catch let error as FunctionClientError {
            if case let .api(_, _, message) = error {
                errorMessage = message
            } else {
                errorMessage = "The merchant application could not be submitted."
            }
        } catch {
            errorMessage = "The merchant application could not be submitted."
        }
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

public struct DastakMerchantAccessView: View {
    private enum Field: Hashable {
        case businessName
        case businessAddress
    }

    private let route: AccountRoute
    @StateObject private var model: DastakMerchantApplicationModel
    @State private var showsImporter = false
    @FocusState private var focusedField: Field?

    public init(route: AccountRoute, services: MarketplaceAuthenticatedServices) {
        self.route = route
        _model = StateObject(
            wrappedValue: DastakMerchantApplicationModel(services: services)
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch route {
                    case .accessDenied where model.isLoading:
                        ProgressView("Loading application")
                    case .accessDenied where !model.isSubmitted:
                        applicationForm
                    case .pendingApproval, .accessDenied:
                        status(
                            symbol: "clock.badge.checkmark",
                            title: "Application under review",
                            message: "Dastak will unlock your merchant workspace after approval."
                        )
                    case .suspended:
                        status(
                            symbol: "exclamationmark.shield",
                            title: "Merchant access suspended",
                            message: "Your store cannot use the merchant app right now."
                        )
                    default:
                        status(
                            symbol: "lock",
                            title: "Merchant access unavailable",
                            message: "Sign in again or contact Dastak support."
                        )
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(MarketplaceSpacing.large)
                .frame(maxWidth: .infinity)
            }
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .navigationTitle("Merchant")
            .toolbar {
#if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
#endif
            }
        }
        .marketplacePage()
        .task {
            if route == .accessDenied { await model.load() }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.pdf, .jpeg, .png],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                model.selectEvidence(url: url)
            } else if case .failure = result {
                model.errorMessage = "The selected document could not be opened."
            }
        }
    }

    private var applicationForm: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Image(systemName: "storefront.fill")
                    .font(.title2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(model.isRejected ? "APPLICATION UPDATE" : "MERCHANT REGISTRATION")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(model.isRejected ? "Update your application" : "Bring your store to Dastak")
                    .font(MarketplaceTypography.hero)
                Text(model.isRejected
                    ? "Review the feedback, update your details, and submit a new document."
                    : "Tell us where you trade and provide one document for owner review.")
                    .font(MarketplaceTypography.supporting)
                    .foregroundStyle(.secondary)
            }

            DastakApplicationProgress()

            if let reviewReason = model.reviewReason {
                HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                    Image(systemName: "exclamationmark.bubble")
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Update requested").font(.headline)
                        Text(reviewReason).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(MarketplaceSpacing.medium)
                .marketplaceFlatSurface()
            }

            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Label("Store details", systemImage: "storefront")
                    .font(MarketplaceTypography.sectionTitle)

                Text("Business name")
                    .font(.subheadline.bold())
                TextField("Your store name", text: $model.businessName)
                    .textContentType(.organizationName)
                    .focused($focusedField, equals: .businessName)
                    .padding(.horizontal, MarketplaceSpacing.compact)
                    .frame(minHeight: 54)
                    .marketplaceFlatSurface()

                Text("Business address")
                    .font(.subheadline.bold())
                TextField(
                    "Shop number, street, area and city",
                    text: $model.businessAddress,
                    axis: .vertical
                )
                .lineLimit(3...5)
                .textContentType(.fullStreetAddress)
                .focused($focusedField, equals: .businessAddress)
                .padding(MarketplaceSpacing.compact)
                .frame(minHeight: 96, alignment: .topLeading)
                .marketplaceFlatSurface()
            }
            .padding(.top, MarketplaceSpacing.medium)
            .overlay(alignment: .top) { Divider() }

            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Label("Verification document", systemImage: "checkmark.shield")
                    .font(MarketplaceTypography.sectionTitle)
                Text("Business registration or the owner's identity proof.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    focusedField = nil
                    showsImporter = true
                } label: {
                    HStack(spacing: MarketplaceSpacing.compact) {
                        Image(systemName: model.evidenceName == nil ? "doc.badge.plus" : "doc.badge.checkmark")
                            .font(.title3)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.evidenceName ?? "Choose a document")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("PDF, JPG or PNG, up to 10 MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(MarketplaceSpacing.compact)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .marketplaceFlatSurface()
            }
            .padding(.top, MarketplaceSpacing.medium)
            .overlay(alignment: .top) { Divider() }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(MarketplaceColors.destructive.color)
            }

            Button(model.isSubmitting ? "Submitting" : model.isRejected ? "Resubmit for review" : "Submit for review") {
                Task { await model.submit() }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(!model.canSubmit)

            Label(
                "Your document is private and used only to review this application.",
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func status(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: MarketplaceSpacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MarketplaceSpacing.large)
    }
}
