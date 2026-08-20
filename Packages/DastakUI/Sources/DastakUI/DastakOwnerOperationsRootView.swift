import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

@MainActor
private final class DastakOwnerOperationsModel: ObservableObject {
    @Published private(set) var snapshot: OwnerOrderOperationsSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyIdentity: String?
    @Published var errorMessage: String?
    @Published var notice: String?

    private let operationsClient: any OwnerOrderOperationsClient
    private let merchantClient: any MerchantOrderClient
    private let checkoutClient: any DastakCheckoutClient
    private var actionKeys: [String: IdempotencyKey] = [:]

    init(services: MarketplaceAuthenticatedServices) {
        operationsClient = SupabaseOwnerOrderOperationsClient(functions: services.functions)
        merchantClient = SupabaseMerchantOrderClient(functions: services.functions)
        checkoutClient = SupabaseDastakCheckoutClient(functions: services.functions)
    }

    var isBusy: Bool { busyIdentity != nil }

    func bootstrap() async {
        await refresh()
        isLoading = false
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await operationsClient.snapshot(limit: 100, idempotencyKey: key())
            errorMessage = nil
        } catch {
            errorMessage = message(for: error, fallback: "Marketplace operations could not be refreshed.")
        }
    }

    func resolveSupport(_ exception: OwnerOrderException, resolution: String) async -> Bool {
        guard let caseID = UUID(uuidString: exception.exceptionID.replacingOccurrences(of: "support:", with: "")) else {
            errorMessage = "This support case reference is invalid."
            return false
        }
        return await perform(identity: "support:\(caseID):\(resolution)", success: "Support case resolved.") { key in
            _ = try await self.operationsClient.resolveSupport(
                caseID: caseID,
                resolution: resolution,
                idempotencyKey: key
            )
        }
    }

    func resetHandoff(_ exception: OwnerOrderException, reason: String) async -> Bool {
        guard let purpose = exception.purpose else {
            errorMessage = "This handoff exception has no code purpose."
            return false
        }
        let identity = "handoff:\(exception.entityKind.rawValue):\(exception.entityID):\(purpose.rawValue):\(reason)"
        return await perform(identity: identity, success: "A new secure handoff code is ready.") { key in
            switch exception.entityKind {
            case .merchantOrder:
                _ = try await self.merchantClient.ownerResetHandoffCode(
                    orderID: exception.entityID,
                    purpose: purpose,
                    reason: reason,
                    idempotencyKey: key
                )
            case .parcelDelivery:
                _ = try await self.operationsClient.resetParcelHandoff(
                    parcelID: exception.entityID,
                    purpose: purpose,
                    reason: reason,
                    idempotencyKey: key
                )
            }
        }
    }

    func reviewRefund(
        _ exception: OwnerOrderException,
        outcome: OwnerRefundOutcome,
        faultSource: OwnerRefundFaultSource?,
        reason: String
    ) async -> Bool {
        let identity = "refund:\(exception.entityID):\(outcome.rawValue):\(faultSource?.rawValue ?? "none"):\(reason)"
        return await perform(identity: identity, success: outcome == .deny ? "Refund request declined." : "Refund approved and queued.") { key in
            let order = try await self.operationsClient.reviewRefund(
                orderID: exception.entityID,
                outcome: outcome,
                faultSource: faultSource,
                reason: reason,
                idempotencyKey: key
            )
            if outcome != .deny,
               order.paymentState == .refundPending,
               order.status != .returningToMerchant {
                _ = try await self.checkoutClient.processMerchantOrderRefund(
                    orderID: order.orderID,
                    idempotencyKey: self.key()
                )
            }
        }
    }

    func reconcile() async {
        let succeeded = await perform(identity: "reconcile", success: "Lifecycle recovery completed.") { key in
            let result = try await self.operationsClient.reconcile(idempotencyKey: key)
            self.notice = "Recovered \(result.merchantOrdersRecovered + result.parcelsRecovered) orders and created \(result.merchantOffersCreated + result.parcelOffersCreated) assignments."
        }
        if !succeeded { notice = nil }
    }

    private func perform(
        identity: String,
        success: String,
        operation: (IdempotencyKey) async throws -> Void
    ) async -> Bool {
        guard !isBusy else { return false }
        busyIdentity = identity
        defer { busyIdentity = nil }
        do {
            let actionKey = actionKeys[identity] ?? key()
            actionKeys[identity] = actionKey
            try await operation(actionKey)
            actionKeys[identity] = nil
            notice = success
            errorMessage = nil
            await refresh()
            return true
        } catch {
            errorMessage = message(for: error, fallback: "The owner action could not be completed.")
            return false
        }
    }

    private func key() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }

    private func message(for error: Error, fallback: String) -> String {
        if case let FunctionClientError.api(_, _, message) = error { return message }
        if case FunctionClientError.authenticationRequired = error { return "Your owner session has expired. Sign in again." }
        return fallback
    }
}

public struct DastakOwnerOperationsRootView: View {
    private enum Tab: Hashable { case operations, account }

    private let services: MarketplaceAuthenticatedServices
    @StateObject private var model: DastakOwnerOperationsModel
    @State private var tab: Tab = .operations
    @Environment(\.scenePhase) private var scenePhase

    public init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        _model = StateObject(wrappedValue: DastakOwnerOperationsModel(services: services))
    }

    public var body: some View {
        TabView(selection: $tab) {
            DastakOwnerOperationsView(model: model)
                .tabItem { Label("Operations", systemImage: "exclamationmark.shield") }
                .tag(Tab.operations)

            DastakIdentityAccountView(
                roleName: "Owner",
                accessLabel: "Full access",
                allowsAccountDeletion: false,
                openWorkspace: { tab = .operations },
                services: services
            )
            .tabItem { Label("Account", systemImage: "person") }
            .tag(Tab.account)
        }
        .tint(MarketplaceColors.dastakAccent.color)
        .task { await model.bootstrap() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await model.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
        .alert(
            "Dastak Admin",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct DastakOwnerOperationsView: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    @State private var selectedException: OwnerOrderException?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    header
                    if let notice = model.notice {
                        noticeView(notice)
                    }
                    if model.isLoading, model.snapshot == nil {
                        ProgressView("Loading operations")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if let snapshot = model.snapshot {
                        summary(snapshot.summary)
                        exceptions(snapshot.exceptions)
                    } else {
                        unavailable
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(MarketplaceSpacing.large)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refresh() }
        }
        .marketplacePage()
        .sheet(item: $selectedException) { exception in
            DastakOwnerExceptionSheet(exception: exception, model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Text("OWNER OPERATIONS")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text("Marketplace control")
                    .font(MarketplaceTypography.instrumentSerif(fixedSize: 48))
                Text("Support, refunds, handoff security and lifecycle recovery.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(MarketplaceIconButtonStyle())
            .disabled(model.isRefreshing)
            .accessibilityLabel("Refresh operations")
        }
    }

    private func summary(_ summary: OwnerOrderOperationsSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MarketplaceSpacing.compact) {
            metric("Support", value: summary.openSupport, icon: "message.badge")
            metric("Refunds", value: summary.refundReviews, icon: "arrow.uturn.backward.circle")
            metric("Locked codes", value: summary.lockedHandoffs, icon: "lock.trianglebadge.exclamationmark")
            metric("Stalled", value: summary.stalledOrders, icon: "clock.badge.exclamationmark")
        }
    }

    private func metric(_ title: String, value: Int, icon: String) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: icon)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)").font(.title2.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    @ViewBuilder
    private func exceptions(_ exceptions: [OwnerOrderException]) -> some View {
        HStack {
            Text("Needs attention").font(.title2.bold())
            Spacer()
            Button("Run recovery") { Task { await model.reconcile() } }
                .font(.subheadline.weight(.semibold))
                .disabled(model.isBusy)
        }
        if exceptions.isEmpty {
            ContentUnavailableView(
                "Operations are clear",
                systemImage: "checkmark.shield",
                description: Text("No support, refund, handoff or lifecycle exception needs owner action.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            LazyVStack(spacing: MarketplaceSpacing.compact) {
                ForEach(exceptions) { exception in
                    Button { selectedException = exception } label: {
                        exceptionRow(exception)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func exceptionRow(_ exception: OwnerOrderException) -> some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: exceptionIcon(exception.kind))
                .font(.title3)
                .foregroundStyle(exception.severity == .critical ? MarketplaceColors.destructive.color : MarketplaceColors.dastakAccent.color)
                .frame(width: 38, height: 38)
                .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: MarketplaceSpacing.xSmall) {
                Text(exception.title).font(.headline)
                Text(exception.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                Text("\(exception.entityKind.label) · \(exception.status.labelled)")
                    .font(.caption)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            Spacer(minLength: MarketplaceSpacing.small)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(MarketplaceSpacing.medium)
        .contentShape(Rectangle())
        .marketplaceFlatSurface()
    }

    private func noticeView(_ text: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(MarketplaceColors.success.color)
            Text(text).font(.subheadline)
            Spacer()
            Button { model.notice = nil } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Dismiss")
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("Operations unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Check your connection and try again.")
        } actions: {
            Button("Retry") { Task { await model.refresh() } }
                .buttonStyle(MarketplacePrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func exceptionIcon(_ kind: OwnerOrderExceptionKind) -> String {
        switch kind {
        case .support: "message.badge"
        case .refundReview: "arrow.uturn.backward.circle"
        case .handoffLocked: "lock.trianglebadge.exclamationmark"
        case .stalledOrder: "clock.badge.exclamationmark"
        }
    }
}

private struct DastakOwnerExceptionSheet: View {
    let exception: OwnerOrderException
    @ObservedObject var model: DastakOwnerOperationsModel
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var refundOutcome: OwnerRefundOutcome = .approveItemsOnly
    @State private var faultSource: OwnerRefundFaultSource?

    private var requiresFault: Bool {
        refundOutcome == .approveFull && ["picked_up", "in_transit", "returning_to_merchant"].contains(exception.status)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    Label(exception.title, systemImage: "exclamationmark.shield")
                        .font(.title2.bold())
                    Text(exception.detail).foregroundStyle(.secondary)
                    LabeledContent("Reference", value: exception.entityID.uuidString.prefix(8).uppercased())
                    LabeledContent("Status", value: exception.status.labelled)

                    if exception.kind == .refundReview {
                        Picker("Decision", selection: $refundOutcome) {
                            Text("Refund items and delivery").tag(OwnerRefundOutcome.approveFull)
                            Text("Refund items only").tag(OwnerRefundOutcome.approveItemsOnly)
                            Text("Decline refund").tag(OwnerRefundOutcome.deny)
                        }
                        .pickerStyle(.inline)

                        if requiresFault {
                            Picker("Responsible party", selection: $faultSource) {
                                Text("Select").tag(OwnerRefundFaultSource?.none)
                                Text("Merchant").tag(OwnerRefundFaultSource?.some(.merchant))
                                Text("Dastak").tag(OwnerRefundFaultSource?.some(.dastak))
                            }
                        }
                    }

                    if exception.kind == .support || exception.kind == .handoffLocked || exception.kind == .refundReview {
                        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                            Text(actionPrompt).font(.headline)
                            TextEditor(text: $note)
                                .frame(minHeight: 110)
                                .padding(MarketplaceSpacing.small)
                                .scrollContentBackground(.hidden)
                                .marketplaceFlatSurface()
                        }
                    }

                    Button(actionTitle) { Task { await submit() } }
                        .buttonStyle(MarketplacePrimaryButtonStyle())
                        .disabled(!canSubmit || model.isBusy)
                }
                .padding(MarketplaceSpacing.large)
            }
            .navigationTitle("Exception")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .marketplacePage()
    }

    private var canSubmit: Bool {
        if exception.kind == .stalledOrder { return true }
        return note.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 && (!requiresFault || faultSource != nil)
    }

    private var actionTitle: String {
        switch exception.kind {
        case .support: "Resolve support case"
        case .refundReview: "Confirm refund decision"
        case .handoffLocked: "Issue new secure code"
        case .stalledOrder: "Recover lifecycle"
        }
    }

    private var actionPrompt: String {
        switch exception.kind {
        case .support: "Resolution shared with the customer"
        case .refundReview: "Reason recorded in the order audit"
        case .handoffLocked: "Reason for replacing the secure code"
        case .stalledOrder: ""
        }
    }

    private func submit() async {
        let normalized = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let succeeded: Bool
        switch exception.kind {
        case .support:
            succeeded = await model.resolveSupport(exception, resolution: normalized)
        case .refundReview:
            succeeded = await model.reviewRefund(
                exception,
                outcome: refundOutcome,
                faultSource: requiresFault ? faultSource : nil,
                reason: normalized
            )
        case .handoffLocked:
            succeeded = await model.resetHandoff(exception, reason: normalized)
        case .stalledOrder:
            await model.reconcile()
            succeeded = model.errorMessage == nil
        }
        if succeeded { dismiss() }
    }
}

private extension OwnerOrderEntityKind {
    var label: String {
        switch self {
        case .merchantOrder: "Merchant order"
        case .parcelDelivery: "Parcel delivery"
        }
    }
}

private extension String {
    var labelled: String {
        replacingOccurrences(of: "_", with: " ").capitalized
    }
}
