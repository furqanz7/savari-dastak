import DastakDomain
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class DastakDeliveryPartnerApplicationModel: ObservableObject {
    @Published var deliveryMethod: MarketplaceInfrastructure.DeliveryMethod = .bike
    @Published private(set) var evidenceName: String?
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let services: MarketplaceAuthenticatedServices
    private let client: any DeliveryPartnerClient
    private var evidenceData: Data?
    private var evidenceContentType: String?
    private var uploadedEvidence: (fingerprint: String, path: String)?
    private var submissionKey: IdempotencyKey?

    init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        client = SupabaseDeliveryPartnerClient(functions: services.functions)
    }

    var canSubmit: Bool {
        evidenceData != nil && !isSubmitting
    }

    func selectEvidence(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let values = try url.resourceValues(forKeys: [.contentTypeKey])
            guard data.count > 0,
                  data.count <= 10 * 1_024 * 1_024,
                  let contentType = values.contentType?.preferredMIMEType,
                  Self.fileExtension(contentType) != nil
            else { throw DastakDeliveryPartnerApplicationError.invalidEvidence }
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

    func submit() async -> Bool {
        guard canSubmit,
              let evidenceData,
              let evidenceContentType,
              let fileExtension = Self.fileExtension(evidenceContentType)
        else { return false }
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
                    "dastak-partner",
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
            _ = try await client.submit(
                deliveryMethod: deliveryMethod,
                identityEvidenceObjectPath: evidencePath,
                idempotencyKey: key
            )
            submissionKey = nil
            return true
        } catch let error as FunctionClientError {
            if case let .api(_, _, message) = error { errorMessage = message }
            else { errorMessage = "The application could not be submitted." }
        } catch {
            errorMessage = "The application could not be submitted."
        }
        return false
    }

    private static func fileExtension(_ contentType: String) -> String? {
        switch contentType.lowercased() {
        case "application/pdf": "pdf"
        case "image/jpeg": "jpg"
        case "image/png": "png"
        default: nil
        }
    }
}

private enum DastakDeliveryPartnerApplicationError: Error {
    case invalidEvidence
}

public struct DastakDeliveryPartnerAccessView: View {
    private let access: DeliveryPartnerAccess
    private let onRefresh: () async -> Void
    @StateObject private var model: DastakDeliveryPartnerApplicationModel
    @State private var showsImporter = false

    public init(
        access: DeliveryPartnerAccess,
        services: MarketplaceAuthenticatedServices,
        onRefresh: @escaping () async -> Void
    ) {
        self.access = access
        self.onRefresh = onRefresh
        _model = StateObject(wrappedValue: DastakDeliveryPartnerApplicationModel(services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch access {
                    case .notApplied, .rejected:
                        applicationForm
                    case .pending:
                        status(
                            symbol: "clock.badge.checkmark",
                            title: "Application under review",
                            message: "You can keep using Dastak as a customer. We will unlock Delivery Partner mode after approval."
                        )
                    case .suspended:
                        status(
                            symbol: "exclamationmark.shield",
                            title: "Delivery access suspended",
                            message: "You cannot receive delivery work right now. Contact Dastak support if you need a review."
                        )
                    case .unavailable:
                        status(
                            symbol: "wifi.exclamationmark",
                            title: "Status unavailable",
                            message: "Dastak could not check your Delivery Partner access."
                        )
                    case .approved:
                        ProgressView("Opening Delivery Partner")
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                .padding(MarketplaceSpacing.large)
                .frame(maxWidth: .infinity)
            }
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .navigationTitle("Delivery Partner")
        }
        .marketplacePage()
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
                Image(systemName: "figure.delivery")
                    .font(.title2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(access == .rejected ? "APPLICATION UPDATE" : "DELIVERY PARTNER")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(access == .rejected ? "Apply again" : "Deliver with Dastak")
                    .font(MarketplaceTypography.hero)
                Text(access == .rejected
                    ? "Your previous application was not approved. Update the details and submit it again."
                    : "Choose how you deliver and provide one identity document for owner review.")
                    .font(MarketplaceTypography.supporting)
                    .foregroundStyle(.secondary)
            }

            DastakApplicationProgress()

            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Label("Delivery method", systemImage: "location.north.line")
                    .font(MarketplaceTypography.sectionTitle)
                Text("Choose the method you will actively use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Delivery method", selection: $model.deliveryMethod) {
                    Text("Walking").tag(MarketplaceInfrastructure.DeliveryMethod.walking)
                    Text("Bicycle").tag(MarketplaceInfrastructure.DeliveryMethod.bicycle)
                    Text("Bike").tag(MarketplaceInfrastructure.DeliveryMethod.bike)
                    Text("Auto").tag(MarketplaceInfrastructure.DeliveryMethod.auto)
                    Text("Car").tag(MarketplaceInfrastructure.DeliveryMethod.car)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: MarketplaceMetrics.minimumTouchTarget, alignment: .leading)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .marketplaceFlatSurface()
            }
            .padding(.top, MarketplaceSpacing.medium)
            .overlay(alignment: .top) { Divider() }

            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Label("Identity proof", systemImage: "checkmark.shield")
                    .font(MarketplaceTypography.sectionTitle)
                Text("Upload one clear document that belongs to you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button { showsImporter = true } label: {
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

            Button(model.isSubmitting ? "Submitting..." : "Submit for review") {
                Task {
                    if await model.submit() { await onRefresh() }
                }
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
                .font(.system(size: 36))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text(title).font(MarketplaceTypography.hero).multilineTextAlignment(.center)
            Text(message)
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Check status") { Task { await onRefresh() } }
                .buttonStyle(MarketplaceSecondaryButtonStyle())
        }
        .padding(.top, MarketplaceSpacing.xxLarge)
    }
}
