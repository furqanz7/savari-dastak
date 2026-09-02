import DastakDomain
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

private enum DastakPartnerEvidenceKind {
    case identity
    case vehicle
}

@MainActor
private final class DastakDeliveryPartnerApplicationModel: ObservableObject {
    private struct EvidencePayload {
        let data: Data
        let contentType: String
        let name: String

        var fingerprint: String {
            "\(data.count):\(data.hashValue):\(contentType)"
        }
    }

    private struct UploadedEvidence {
        let fingerprint: String
        let path: String
    }

    @Published var deliveryMethod: MarketplaceInfrastructure.DeliveryMethod = .motorbike {
        didSet { if oldValue != deliveryMethod { submissionKey = nil } }
    }
    @Published var vehicleRegistrationNumber = "" {
        didSet { if oldValue != vehicleRegistrationNumber { submissionKey = nil } }
    }
    @Published var vehicleMakeModel = "" {
        didSet { if oldValue != vehicleMakeModel { submissionKey = nil } }
    }
    @Published private(set) var identityEvidenceName: String?
    @Published private(set) var vehicleEvidenceName: String?
    @Published private(set) var isSubmitting = false
    @Published private(set) var isLoading = true
    @Published private(set) var reviewReason: String?
    @Published var errorMessage: String?

    private let services: MarketplaceAuthenticatedServices
    private let client: any DeliveryPartnerClient
    private var identityEvidence: EvidencePayload?
    private var vehicleEvidence: EvidencePayload?
    private var uploadedIdentityEvidence: UploadedEvidence?
    private var uploadedVehicleEvidence: UploadedEvidence?
    private var submissionKey: IdempotencyKey?

    init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        client = SupabaseDeliveryPartnerClient(functions: services.functions)
    }

    var canSubmit: Bool {
        guard identityEvidence != nil, !isSubmitting, !isLoading else { return false }
        guard deliveryMethod.requiresVehicleVerification else { return true }
        return vehicleEvidence != nil
            && Self.isValidRegistration(normalizedRegistration)
            && (2...80).contains(normalizedMakeModel.count)
    }

    func load() async {
        do {
            let snapshot = try await client.selfSnapshot(
                idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!
            )
            if snapshot.onboardingState == .rejected {
                deliveryMethod = snapshot.deliveryMethod == .bike ? .motorbike : snapshot.deliveryMethod ?? .motorbike
                vehicleRegistrationNumber = snapshot.vehicleRegistrationNumber ?? ""
                vehicleMakeModel = snapshot.vehicleMakeModel ?? ""
                reviewReason = snapshot.reviewReason
            }
            errorMessage = nil
        } catch {
            errorMessage = "Your application could not be loaded. You can still enter the details again."
        }
        isLoading = false
    }

    func selectEvidence(url: URL, kind: DastakPartnerEvidenceKind) {
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

            let payload = EvidencePayload(
                data: data,
                contentType: contentType,
                name: url.lastPathComponent
            )
            switch kind {
            case .identity:
                identityEvidence = payload
                identityEvidenceName = payload.name
                uploadedIdentityEvidence = nil
            case .vehicle:
                vehicleEvidence = payload
                vehicleEvidenceName = payload.name
                uploadedVehicleEvidence = nil
            }
            submissionKey = nil
            errorMessage = nil
        } catch {
            switch kind {
            case .identity:
                identityEvidence = nil
                identityEvidenceName = nil
            case .vehicle:
                vehicleEvidence = nil
                vehicleEvidenceName = nil
            }
            errorMessage = "Choose a clear PDF, JPG, or PNG document up to 10 MB."
        }
    }

    func submit() async -> Bool {
        guard canSubmit, let identityEvidence else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let accountID = try await services.accountID()
            let identity = try await upload(
                identityEvidence,
                role: "identity",
                accountID: accountID,
                cached: uploadedIdentityEvidence
            )
            uploadedIdentityEvidence = identity.uploaded

            var vehiclePath: String?
            if deliveryMethod.requiresVehicleVerification, let vehicleEvidence {
                let vehicle = try await upload(
                    vehicleEvidence,
                    role: "vehicle",
                    accountID: accountID,
                    cached: uploadedVehicleEvidence
                )
                uploadedVehicleEvidence = vehicle.uploaded
                vehiclePath = vehicle.path
            }

            let key = submissionKey ?? IdempotencyKey(rawValue: UUID().uuidString)!
            submissionKey = key
            _ = try await client.submit(
                deliveryMethod: deliveryMethod,
                identityEvidenceObjectPath: identity.path,
                vehicleRegistrationNumber: deliveryMethod.requiresVehicleVerification
                    ? normalizedRegistration : nil,
                vehicleMakeModel: deliveryMethod.requiresVehicleVerification
                    ? normalizedMakeModel : nil,
                vehicleEvidenceObjectPath: vehiclePath,
                idempotencyKey: key
            )
            submissionKey = nil
            reviewReason = nil
            return true
        } catch let error as FunctionClientError {
            if case let .api(_, _, message) = error { errorMessage = message }
            else { errorMessage = "The application could not be submitted." }
        } catch {
            errorMessage = "The application could not be submitted."
        }
        return false
    }

    private var normalizedRegistration: String {
        vehicleRegistrationNumber
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .uppercased()
    }

    private var normalizedMakeModel: String {
        vehicleMakeModel
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func upload(
        _ evidence: EvidencePayload,
        role: String,
        accountID: UUID,
        cached: UploadedEvidence?
    ) async throws -> (path: String, uploaded: UploadedEvidence) {
        if let cached, cached.fingerprint == evidence.fingerprint {
            return (cached.path, cached)
        }
        guard let fileExtension = Self.fileExtension(evidence.contentType) else {
            throw DastakDeliveryPartnerApplicationError.invalidEvidence
        }
        let path = [
            "dastak-partner",
            accountID.uuidString.lowercased(),
            "\(role)-\(UUID().uuidString.lowercased()).\(fileExtension)"
        ].joined(separator: "/")
        try await services.uploadObject(
            bucket: "dastak-evidence",
            path: path,
            data: evidence.data,
            contentType: evidence.contentType
        )
        return (path, UploadedEvidence(fingerprint: evidence.fingerprint, path: path))
    }

    private static func isValidRegistration(_ value: String) -> Bool {
        (4...20).contains(value.count) && value.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == " " || $0 == "-"
        }
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
    private enum Field: Hashable {
        case registration
        case makeModel
    }

    private let access: DeliveryPartnerAccess
    private let onRefresh: () async -> Void
    @StateObject private var model: DastakDeliveryPartnerApplicationModel
    @State private var importingEvidence: DastakPartnerEvidenceKind?
    @FocusState private var focusedField: Field?

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
                    case .notApplied where model.isLoading, .rejected where model.isLoading:
                        ProgressView("Loading application")
                            .frame(maxWidth: .infinity)
                            .padding(.top, MarketplaceSpacing.xxLarge)
                    case .notApplied, .rejected:
                        applicationForm
                    case .pending:
                        status(
                            symbol: "clock.badge.checkmark",
                            title: "Application under review",
                            message: "You can keep using Dastak as a customer. Delivery Partner mode unlocks after approval."
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
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, MarketplaceSpacing.large)
                .padding(.top, MarketplaceSpacing.medium)
                .padding(.bottom, showsApplicationForm ? 112 : MarketplaceSpacing.large)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await onRefresh() }
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .safeAreaInset(edge: .bottom) {
                if showsApplicationForm && !model.isLoading { submitBar }
            }
            .navigationTitle("Apply to deliver")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
#endif
            }
        }
        .marketplacePage()
        .task {
            if access == .notApplied || access == .rejected { await model.load() }
        }
        .task(id: access) {
            guard access == .pending || access == .suspended || access == .unavailable else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await onRefresh()
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importingEvidence != nil },
                set: { if !$0 { importingEvidence = nil } }
            ),
            allowedContentTypes: [.pdf, .jpeg, .png],
            allowsMultipleSelection: false
        ) { result in
            let kind = importingEvidence
            importingEvidence = nil
            guard let kind else { return }
            if case let .success(urls) = result, let url = urls.first {
                model.selectEvidence(url: url, kind: kind)
            } else if case .failure = result {
                model.errorMessage = "The selected document could not be opened."
            }
        }
        .onTapGesture { dismissKeyboard() }
    }

    private var showsApplicationForm: Bool {
        access == .notApplied || access == .rejected
    }

    private var applicationForm: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.xLarge) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Text(access == .rejected ? "APPLICATION UPDATE" : "DELIVERY PARTNER")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(access == .rejected ? "Update your application" : "Deliver with Dastak")
                    .font(MarketplaceTypography.hero)
                Text(access == .rejected
                    ? "Review the requested changes, then send your application again."
                    : "Choose how you deliver. We verify your identity and, for motor vehicles, the vehicle you use.")
                    .font(MarketplaceTypography.supporting)
                    .foregroundStyle(.secondary)
            }

            if let reviewReason = model.reviewReason {
                HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Update requested").font(.headline)
                        Text(reviewReason).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(MarketplaceSpacing.medium)
                .marketplaceFlatSurface()
            }

            applicationSection(
                number: "1",
                title: "How will you deliver?",
                description: "Choose the method you will actively use."
            ) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: MarketplaceSpacing.small)],
                    spacing: MarketplaceSpacing.small
                ) {
                    ForEach(Self.deliveryMethods, id: \.method) { option in
                        methodButton(option.method, title: option.title, symbol: option.symbol)
                    }
                }
            }

            applicationSection(
                number: "2",
                title: "Verify your identity",
                description: "Upload one clear government-issued identity document."
            ) {
                evidenceButton(
                    title: model.identityEvidenceName ?? "Choose identity proof",
                    detail: model.identityEvidenceName == nil
                        ? "Aadhaar, driving licence, voter ID or passport"
                        : "Ready to upload",
                    selected: model.identityEvidenceName != nil
                ) { importingEvidence = .identity }
            }

            if model.deliveryMethod.requiresVehicleVerification {
                applicationSection(
                    number: "3",
                    title: "Verify your vehicle",
                    description: "Motorbike, Scooter, Auto, and Car partners must verify the vehicle used for deliveries."
                ) {
                    VStack(spacing: MarketplaceSpacing.compact) {
                        TextField("Registration number", text: $model.vehicleRegistrationNumber)
                            .focused($focusedField, equals: .registration)
#if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
#endif
                            .padding(.horizontal, MarketplaceSpacing.medium)
                            .frame(minHeight: 54)
                            .marketplaceFlatSurface()

                        TextField("Vehicle make and model", text: $model.vehicleMakeModel)
                            .focused($focusedField, equals: .makeModel)
                            .padding(.horizontal, MarketplaceSpacing.medium)
                            .frame(minHeight: 54)
                            .marketplaceFlatSurface()

                        evidenceButton(
                            title: model.vehicleEvidenceName ?? "Choose registration certificate",
                            detail: model.vehicleEvidenceName == nil
                                ? "Upload the vehicle RC as PDF, JPG, or PNG"
                                : "Vehicle proof ready to upload",
                            selected: model.vehicleEvidenceName != nil
                        ) { importingEvidence = .vehicle }
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(MarketplaceColors.destructive.color)
            }

            Label(
                model.deliveryMethod.requiresVehicleVerification
                    ? "Your identity and vehicle documents stay private and are used only for verification."
                    : "Your identity document stays private and is used only for verification.",
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func applicationSection<Content: View>(
        number: String,
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Text(number)
                    .font(.caption.bold())
                    .foregroundStyle(MarketplaceColors.dastakIconBackground.color)
                    .frame(width: 28, height: 28)
                    .background(MarketplaceColors.dastakAccent.color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(MarketplaceTypography.sectionTitle)
                    Text(description).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(.top, MarketplaceSpacing.medium)
        .overlay(alignment: .top) { Divider() }
    }

    private func methodButton(
        _ method: MarketplaceInfrastructure.DeliveryMethod,
        title: String,
        symbol: String
    ) -> some View {
        let selected = model.deliveryMethod == method
        return Button {
            model.deliveryMethod = method
            dismissKeyboard()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(height: 24)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(method.requiresVehicleVerification ? "Vehicle check" : "Identity only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(.horizontal, 6)
            .foregroundStyle(selected ? MarketplaceColors.dastakAccent.color : .primary)
            .background(selected
                ? MarketplaceColors.dastakAccent.color.opacity(0.12)
                : MarketplaceColors.dastakSurface.color)
            .clipShape(RoundedRectangle(cornerRadius: MarketplaceMetrics.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MarketplaceMetrics.controlCornerRadius, style: .continuous)
                    .stroke(selected ? MarketplaceColors.dastakAccent.color : MarketplaceColors.dividerDark.color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(method.requiresVehicleVerification ? "vehicle verification required" : "identity verification only")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func evidenceButton(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: selected ? "checkmark.document.fill" : "doc.badge.plus")
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 40, height: 40)
                    .background(MarketplaceColors.dastakAccent.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(selected ? MarketplaceColors.dastakAccent.color : Color.secondary)
            }
            .padding(MarketplaceSpacing.compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marketplaceFlatSurface()
    }

    private var submitBar: some View {
        VStack(spacing: 7) {
            Button(
                model.isSubmitting
                    ? "Submitting..."
                    : access == .rejected ? "Resubmit for review" : "Submit for review"
            ) {
                dismissKeyboard()
                Task {
                    if await model.submit() { await onRefresh() }
                }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(!model.canSubmit)

            Text(model.deliveryMethod.requiresVehicleVerification
                ? "Identity and vehicle verification are required."
                : "Identity verification is required.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MarketplaceSpacing.large)
        .padding(.top, MarketplaceSpacing.compact)
        .padding(.bottom, MarketplaceSpacing.small)
        .background(.ultraThinMaterial)
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
            Text("Pull down to check now. This screen also checks automatically.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MarketplaceSpacing.xxLarge)
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

    private static let deliveryMethods: [(
        method: MarketplaceInfrastructure.DeliveryMethod,
        title: String,
        symbol: String
    )] = [
        (.walking, "Walk", "figure.walk"),
        (.bicycle, "Bicycle", "bicycle"),
        (.motorbike, "Motorbike", "fuelpump.fill"),
        (.scooter, "Scooter", "bicycle"),
        (.auto, "Auto", "car.side.fill"),
        (.car, "Car", "car.fill")
    ]
}
