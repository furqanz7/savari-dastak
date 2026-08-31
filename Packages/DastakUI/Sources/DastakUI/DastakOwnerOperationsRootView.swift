import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

@MainActor
private final class DastakOwnerOperationsModel: ObservableObject {
    @Published private(set) var snapshot: OwnerOrderOperationsSnapshot?
    @Published private(set) var v1Orders: [DastakV1AdminOrder] = []
    @Published private(set) var v1Trace: DastakV1AdminExecutionTrace?
    @Published private(set) var adminAccess: DastakAdminAccessSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyIdentity: String?
    @Published var errorMessage: String?
    @Published var notice: String?

    private let operationsClient: any OwnerOrderOperationsClient
    private let merchantClient: any MerchantOrderClient
    private let checkoutClient: any DastakCheckoutClient
    private let v1Client: any DastakV1AdminClient
    private var actionKeys: [String: IdempotencyKey] = [:]

    init(services: MarketplaceAuthenticatedServices) {
        operationsClient = SupabaseOwnerOrderOperationsClient(functions: services.functions)
        merchantClient = SupabaseMerchantOrderClient(functions: services.functions)
        checkoutClient = SupabaseDastakCheckoutClient(functions: services.functions)
        v1Client = SupabaseDastakV1AdminClient(functions: services.functions)
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
            async let operations = operationsClient.snapshot(limit: 100, idempotencyKey: key())
            async let currentOrders = v1Client.orders(limit: 50, idempotencyKey: key())
            async let currentAdminAccess = v1Client.access(idempotencyKey: key())
            let loaded = try await (operations, currentOrders, currentAdminAccess)
            snapshot = loaded.0
            v1Orders = loaded.1
            adminAccess = loaded.2
            let selectedID = v1Trace.map(\.order.id).flatMap { current in
                loaded.1.contains(where: { $0.id == current }) ? current : nil
            } ?? loaded.1.first?.id
            if let selectedID {
                v1Trace = try await v1Client.trace(orderID: selectedID, idempotencyKey: key())
            } else {
                v1Trace = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = message(for: error, fallback: "Marketplace operations could not be refreshed.")
        }
    }

    func selectV1Order(_ orderID: UUID) async {
        guard !isBusy else { return }
        do {
            v1Trace = try await v1Client.trace(orderID: orderID, idempotencyKey: key())
            errorMessage = nil
        } catch {
            errorMessage = message(for: error, fallback: "The launch-payment trace could not be loaded.")
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

    func setExecutiveAdmin(_ slot: DastakAdminSlot, email: String?) async {
        let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let assignment = normalized?.isEmpty == false ? normalized : nil
        _ = await perform(
            identity: "admin-access:\(slot.slot):\(assignment ?? "clear"):\(slot.version)",
            success: assignment == nil
                ? "Executive Admin access removed."
                : "Executive Admin access saved."
        ) { key in
            _ = try await self.v1Client.setExecutiveAdmin(
                slot: slot.slot,
                email: assignment,
                expectedVersion: slot.version,
                reason: assignment == nil
                    ? "Cleared from protected Dastak Admin access settings."
                    : "Updated from protected Dastak Admin access settings.",
                idempotencyKey: key
            )
        }
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
            errorMessage = message(for: error, fallback: "The Admin action could not be completed.")
            return false
        }
    }

    private func key() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }

    private func message(for error: Error, fallback: String) -> String {
        if case let FunctionClientError.api(_, _, message) = error { return message }
        if case FunctionClientError.authenticationRequired = error { return "Your Admin session has expired. Sign in again." }
        return fallback
    }
}

public struct DastakOwnerOperationsRootView: View {
    private enum Tab: Hashable { case operations, access, account }

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

            if model.adminAccess?.canManageAdmins == true {
                DastakAdminAccessView(model: model)
                    .tabItem { Label("Access", systemImage: "person.2.badge.gearshape") }
                    .tag(Tab.access)
            }

            DastakIdentityAccountView(
                roleName: model.adminAccess?.role.displayName ?? "Admin",
                accessLabel: "Full operations access",
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

private struct DastakAdminAccessView: View {
    @ObservedObject var model: DastakOwnerOperationsModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        Text("SUPERADMIN CONTROL")
                            .font(.caption.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text("Admin access")
                            .font(.largeTitle.bold())
                        Text("One permanent Superadmin and two replaceable Executive Admin seats.")
                            .foregroundStyle(.secondary)
                    }

                    if let access = model.adminAccess {
                        if let superadmin = access.slots.first(where: { $0.role == .superadmin }) {
                            adminSeat(
                                title: "Superadmin",
                                email: superadmin.email ?? "",
                                detail: "Permanent · cannot be changed or removed",
                                symbol: "lock.shield.fill"
                            )
                        }

                        ForEach(access.slots.filter { $0.role == .executiveAdmin }) { slot in
                            DastakExecutiveAdminSeat(
                                slot: slot,
                                isBusy: model.isBusy,
                                onSave: { email in
                                    await model.setExecutiveAdmin(slot, email: email)
                                },
                                onClear: {
                                    await model.setExecutiveAdmin(slot, email: nil)
                                }
                            )
                        }
                    } else {
                        ProgressView("Loading Admin access")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }

                    Text("Executive Admins can use every current operations feature. Only the permanent Superadmin can change Admin access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(MarketplaceSpacing.large)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.opacity(0.015))
            .navigationTitle("Access")
            .refreshable { await model.refresh() }
        }
    }

    private func adminSeat(
        title: String,
        email: String,
        detail: String,
        symbol: String
    ) -> some View {
        HStack(spacing: MarketplaceSpacing.medium) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 44, height: 44)
                .background(MarketplaceColors.dastakIconBackground.color)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(email).font(.subheadline).textSelection(.enabled)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        }
        .padding(MarketplaceSpacing.medium)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct DastakExecutiveAdminSeat: View {
    let slot: DastakAdminSlot
    let isBusy: Bool
    let onSave: (String) async -> Void
    let onClear: () async -> Void

    @State private var email: String
    @State private var confirmsRemoval = false

    init(
        slot: DastakAdminSlot,
        isBusy: Bool,
        onSave: @escaping (String) async -> Void,
        onClear: @escaping () async -> Void
    ) {
        self.slot = slot
        self.isBusy = isBusy
        self.onSave = onSave
        self.onClear = onClear
        _email = State(initialValue: slot.email ?? "")
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var validEmail: Bool {
        let parts = normalizedEmail.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(spacing: MarketplaceSpacing.medium) {
                Image(systemName: "person.badge.key.fill")
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 40, height: 40)
                    .background(MarketplaceColors.dastakIconBackground.color)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Executive Admin \(slot.slot)").font(.headline)
                    Text(slot.email == nil ? "Empty seat" : slot.linked
                        ? "Active account"
                        : "Reserved · activates after this email signs in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if slot.email != nil {
                    Label(
                        slot.linked ? "Active" : "Pending",
                        systemImage: slot.linked ? "checkmark.circle.fill" : "clock.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(slot.linked ? .green : MarketplaceColors.dastakAccent.color)
                    .labelStyle(.titleAndIcon)
                }
            }

            TextField("name@example.com", text: $email)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
#endif
                .padding(.horizontal, 13)
                .frame(minHeight: 48)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isBusy)
                .accessibilityLabel("Executive Admin \(slot.slot) email")

            Button(slot.email == nil ? "Assign Executive Admin" : "Save change") {
                Task { await onSave(normalizedEmail) }
            }
            .buttonStyle(.borderedProminent)
            .tint(MarketplaceColors.dastakAccent.color)
            .disabled(isBusy || !validEmail || normalizedEmail == slot.email)

            if slot.email != nil {
                Button("Remove Executive Admin", role: .destructive) {
                    confirmsRemoval = true
                }
                .disabled(isBusy)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: slot) { _, updated in email = updated.email ?? "" }
        .confirmationDialog(
            "Remove Executive Admin?",
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove access", role: .destructive) { Task { await onClear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This email will immediately lose Dastak Admin access.")
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
                        launchPaymentTrace
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

    @ViewBuilder
    private var launchPaymentTrace: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LAUNCH PAYMENT")
                        .font(.caption2.bold())
                        .tracking(1.1)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text("Commitment and doorstep collection")
                        .font(.title2.bold())
                }
                Spacer()
                Image(systemName: "indianrupeesign.circle.fill")
                    .font(.title2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }

            if model.v1Orders.isEmpty {
                Text("No current-generation order trace is available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "Order",
                    selection: Binding(
                        get: { model.v1Trace?.order.id ?? model.v1Orders[0].id },
                        set: { orderID in Task { await model.selectV1Order(orderID) } }
                    )
                ) {
                    ForEach(model.v1Orders) { order in
                        Text("\(order.displayOrderNumber) · \(order.status.replacingOccurrences(of: "_", with: " "))")
                            .tag(order.id)
                    }
                }
                .pickerStyle(.menu)

                if let trace = model.v1Trace,
                   let launch = trace.launchPayment {
                    if let commitment = launch.commitment {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Pay via UPI/Cash on Delivery")
                                .font(.headline)
                            Text("\(DastakFormatting.money(Money(paise: commitment.amountPaise))) · \(launch.collectionStatus.replacingOccurrences(of: "_", with: " "))")
                                .font(.subheadline.weight(.semibold))
                            Text("Committed \(adminTime(commitment.committedAt)) · reservation secured \(adminTime(commitment.securedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(MarketplaceSpacing.medium)
                        .background(MarketplaceColors.dastakAccentSoft.color)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Text("No launch commitment; this may be a historical provider-paid order.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(launch.attempts) { attempt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(attempt.outcome) · \(attempt.method)")
                                .font(.subheadline.bold())
                            Text("\(adminTime(attempt.attemptedAt)) · rider \(short(attempt.riderID)) · mission \(short(attempt.missionID))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if let reason = attempt.reason {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(MarketplaceSpacing.compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .marketplaceFlatSurface()
                    }

                    if let fee = launch.platformFee {
                        Label(
                            "2% platform fee \(DastakFormatting.money(Money(paise: fee.amountPaise))) · \(fee.balanced ? "balanced" : "review required") · \(adminTime(fee.postedAt))",
                            systemImage: fee.balanced ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(fee.balanced ? MarketplaceColors.success.color : MarketplaceColors.warning.color)
                    } else if launch.commitment != nil {
                        Text("Platform fee posts exactly once only after successful collection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }

    private func adminTime(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable"
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
                description: Text("No support, refund, handoff or lifecycle exception needs Admin action.")
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
