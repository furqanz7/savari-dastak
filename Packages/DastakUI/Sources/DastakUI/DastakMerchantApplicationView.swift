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
    private let route: AccountRoute
    @StateObject private var model: DastakMerchantApplicationModel
    @State private var showsImporter = false

    public init(route: AccountRoute, services: MarketplaceAuthenticatedServices) {
        self.route = route
        _model = StateObject(
            wrappedValue: DastakMerchantApplicationModel(services: services)
        )
    }

    public var body: some View {
        Group {
            switch route {
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
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            Image(systemName: "storefront")
                .font(.title2)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)

            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Text("Merchant registration")
                    .font(.caption.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text("Apply to sell")
                    .font(MarketplaceTypography.sectionTitle)
                Text("Add your business details and one proof document.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("Business name", text: $model.businessName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.organizationName)

            TextField(
                "Business address",
                text: $model.businessAddress,
                axis: .vertical
            )
            .lineLimit(3...5)
            .textFieldStyle(.roundedBorder)
            .textContentType(.fullStreetAddress)

            Button {
                showsImporter = true
            } label: {
                Label(
                    model.evidenceName ?? "Choose business document",
                    systemImage: "doc.badge.plus"
                )
            }
            .buttonStyle(MarketplaceSecondaryButtonStyle())

            Text("PDF, JPG, or PNG, up to 10 MB.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(MarketplaceColors.destructive.color)
            }

            Button(model.isSubmitting ? "Submitting" : "Submit for review") {
                Task { await model.submit() }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(!model.canSubmit)
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
