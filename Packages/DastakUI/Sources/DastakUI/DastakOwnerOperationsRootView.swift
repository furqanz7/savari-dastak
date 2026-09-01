import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

enum DastakAdminWorkspace: String, CaseIterable, Hashable, Sendable {
    case operations
    case liveOrders
    case adminAccess
    case commandCenter
    case merchantApprovals
    case deliveryApprovals
    case systemHealth
    case operationalSafety
    case royaltyPayouts
    case network
    case catalogue

    var displayName: String {
        switch self {
        case .operations: "Order operations"
        case .liveOrders: "Live order trace"
        case .adminAccess: "Admin access"
        case .commandCenter: "Command center"
        case .merchantApprovals: "Merchant approvals"
        case .deliveryApprovals: "Delivery approvals"
        case .systemHealth: "System health"
        case .operationalSafety: "Operational safety"
        case .royaltyPayouts: "Royalty payouts"
        case .network: "Marketplace network"
        case .catalogue: "Master catalogue"
        }
    }
}

struct DastakAdminWorkspaceIssue: Equatable, Identifiable, Sendable {
    let workspace: DastakAdminWorkspace
    let message: String
    let occurredAt: Date

    var id: DastakAdminWorkspace { workspace }
}

struct DastakAdminWorkspaceState: Equatable, Sendable {
    private(set) var issues: [DastakAdminWorkspace: DastakAdminWorkspaceIssue] = [:]
    private(set) var lastSuccessfulRefresh: [DastakAdminWorkspace: Date] = [:]

    mutating func recordSuccess(_ workspace: DastakAdminWorkspace, at date: Date = Date()) {
        issues.removeValue(forKey: workspace)
        lastSuccessfulRefresh[workspace] = date
    }

    mutating func recordFailure(_ issue: DastakAdminWorkspaceIssue) {
        issues[issue.workspace] = issue
    }
}

private enum DastakAdminLoadResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(DastakAdminWorkspaceIssue)
}

private func loadAdminWorkspace<Value: Sendable>(
    _ workspace: DastakAdminWorkspace,
    fallback: String,
    operation: @escaping @Sendable () async throws -> Value
) async -> DastakAdminLoadResult<Value> {
    do {
        return .success(try await operation())
    } catch {
        let message: String
        switch error {
        case FunctionClientError.authenticationRequired,
             FunctionClientError.api(statusCode: 401, code: _, message: _):
            message = "Your Admin session needs to be refreshed. Reopen the app or sign in again."
        default:
            message = fallback
        }
        return .failure(
            DastakAdminWorkspaceIssue(
                workspace: workspace,
                message: message,
                occurredAt: Date()
            )
        )
    }
}

@MainActor
final class DastakOwnerOperationsModel: ObservableObject {
    @Published private(set) var snapshot: OwnerOrderOperationsSnapshot?
    @Published private(set) var v1Orders: [DastakV1AdminOrder] = []
    @Published private(set) var v1Trace: DastakV1AdminExecutionTrace?
    @Published private(set) var adminAccess: DastakAdminAccessSnapshot?
    @Published private(set) var commandCenter: DastakAdminCommandCenter?
    @Published private(set) var systemHealth: DastakAdminSystemHealth?
    @Published private(set) var operationalSafety: DastakAdminOperationalSafety?
    @Published private(set) var royaltyPayouts: [DastakAdminRoyaltyPayout] = []
    @Published private(set) var merchantApplications: [MerchantApplication] = []
    @Published private(set) var deliveryApplications: [DeliveryPartnerApplication] = []
    @Published private(set) var networkPeople: [DastakAdminNetworkPerson] = []
    @Published private(set) var networkHasMore = false
    @Published private(set) var catalogueTaxonomy: DastakAdminCatalogueTaxonomy?
    @Published private(set) var catalogueSKUs: [DastakAdminCatalogueSKU] = []
    @Published private(set) var catalogueHasMore = false
    @Published private(set) var isLoadingNetwork = false
    @Published private(set) var isLoadingCatalogue = false
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyIdentity: String?
    @Published private(set) var workspaceState = DastakAdminWorkspaceState()
    @Published var actionErrorMessage: String?
    @Published var notice: String?

    private let operationsClient: any OwnerOrderOperationsClient
    private let merchantClient: any MerchantOrderClient
    private let checkoutClient: any DastakCheckoutClient
    private let v1Client: any DastakV1AdminClient
    private let merchantApplicationClient: any MerchantApplicationClient
    private let deliveryApplicationClient: any DeliveryPartnerClient
    private var networkCursor: DastakAdminNetworkCursor?
    private var catalogueCursor: DastakAdminCatalogueCursor?
    private var actionKeys: [String: IdempotencyKey] = [:]

    init(services: MarketplaceAuthenticatedServices) {
        operationsClient = SupabaseOwnerOrderOperationsClient(functions: services.functions)
        merchantClient = SupabaseMerchantOrderClient(functions: services.functions)
        checkoutClient = SupabaseDastakCheckoutClient(functions: services.functions)
        v1Client = SupabaseDastakV1AdminClient(functions: services.functions)
        merchantApplicationClient = SupabaseMerchantApplicationClient(functions: services.functions)
        deliveryApplicationClient = SupabaseDeliveryPartnerClient(functions: services.functions)
    }

    var isBusy: Bool { busyIdentity != nil }
    var workspaceIssues: [DastakAdminWorkspaceIssue] {
        workspaceState.issues.values.sorted { $0.workspace.rawValue < $1.workspace.rawValue }
    }

    func issue(for workspace: DastakAdminWorkspace) -> DastakAdminWorkspaceIssue? {
        workspaceState.issues[workspace]
    }

    func lastSuccessfulRefresh(for workspace: DastakAdminWorkspace) -> Date? {
        workspaceState.lastSuccessfulRefresh[workspace]
    }

    func bootstrap() async {
        await refresh()
        isLoading = false
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let operationsClient = operationsClient
        let v1Client = v1Client
        let merchantApplicationClient = merchantApplicationClient
        let deliveryApplicationClient = deliveryApplicationClient
        let keys = (key(), key(), key(), key(), key(), key(), key(), key(), key())
        async let operations = loadAdminWorkspace(
            .operations,
            fallback: "Order support and recovery could not be refreshed."
        ) { try await operationsClient.snapshot(limit: 100, idempotencyKey: keys.0) }
        async let currentOrders = loadAdminWorkspace(
            .liveOrders,
            fallback: "Live order and collection trace could not be refreshed."
        ) { try await v1Client.orders(limit: 50, idempotencyKey: keys.1) }
        async let currentAdminAccess = loadAdminWorkspace(
            .adminAccess,
            fallback: "Protected Admin access settings could not be refreshed."
        ) { try await v1Client.access(idempotencyKey: keys.2) }
        async let currentCommandCenter = loadAdminWorkspace(
            .commandCenter,
            fallback: "Command center metrics could not be refreshed."
        ) { try await v1Client.commandCenter(idempotencyKey: keys.3) }
        async let currentHealth = loadAdminWorkspace(
            .systemHealth,
            fallback: "System health signals could not be refreshed."
        ) { try await v1Client.systemHealth(idempotencyKey: keys.4) }
        async let currentSafety = loadAdminWorkspace(
            .operationalSafety,
            fallback: "Safety controls and escalation signals could not be refreshed."
        ) { try await v1Client.operationalSafety(idempotencyKey: keys.5) }
        async let currentPayouts = loadAdminWorkspace(
            .royaltyPayouts,
            fallback: "Royalty payout reconciliation could not be refreshed."
        ) { try await v1Client.royaltyPayouts(limit: 100, idempotencyKey: keys.6) }
        async let currentMerchants = loadAdminWorkspace(
            .merchantApprovals,
            fallback: "Merchant applications could not be refreshed."
        ) { try await merchantApplicationClient.listPending(idempotencyKey: keys.7) }
        async let currentDeliveryPartners = loadAdminWorkspace(
            .deliveryApprovals,
            fallback: "Delivery Partner applications could not be refreshed."
        ) { try await deliveryApplicationClient.listPending(idempotencyKey: keys.8) }
        let loaded = await (
            operations, currentOrders, currentAdminAccess, currentCommandCenter,
            currentMerchants, currentDeliveryPartners, currentHealth, currentSafety, currentPayouts
        )
        if let value = resolve(loaded.0, workspace: .operations) { snapshot = value }
        let orders = resolve(loaded.1, workspace: .liveOrders)
        if let orders { v1Orders = orders }
        if let value = resolve(loaded.2, workspace: .adminAccess) { adminAccess = value }
        if let value = resolve(loaded.3, workspace: .commandCenter) { commandCenter = value }
        if let value = resolve(loaded.4, workspace: .merchantApprovals) { merchantApplications = value }
        if let value = resolve(loaded.5, workspace: .deliveryApprovals) { deliveryApplications = value }
        if let value = resolve(loaded.6, workspace: .systemHealth) { systemHealth = value }
        if let value = resolve(loaded.7, workspace: .operationalSafety) { operationalSafety = value }
        if let value = resolve(loaded.8, workspace: .royaltyPayouts) { royaltyPayouts = value }

        if let orders {
            let selectedID = v1Trace.map(\.order.id).flatMap { current in
                orders.contains(where: { $0.id == current }) ? current : nil
            } ?? orders.first?.id
            if let selectedID {
                let traceKey = key()
                let trace = await loadAdminWorkspace(
                    .liveOrders,
                    fallback: "The selected order trace could not be refreshed."
                ) { try await v1Client.trace(orderID: selectedID, idempotencyKey: traceKey) }
                if let value = resolve(trace, workspace: .liveOrders) { v1Trace = value }
            } else {
                v1Trace = nil
            }
        }
    }

    func selectV1Order(_ orderID: UUID) async {
        guard !isBusy else { return }
        let client = v1Client
        let traceKey = key()
        let result = await loadAdminWorkspace(
            .liveOrders,
            fallback: "The selected order trace could not be loaded."
        ) { try await client.trace(orderID: orderID, idempotencyKey: traceKey) }
        if let value = resolve(result, workspace: .liveOrders) { v1Trace = value }
    }

    func resolveSupport(_ exception: OwnerOrderException, resolution: String) async -> Bool {
        guard let caseID = UUID(uuidString: exception.exceptionID.replacingOccurrences(of: "support:", with: "")) else {
            actionErrorMessage = "This support case reference is invalid."
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
            actionErrorMessage = "This handoff exception has no code purpose."
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

    func reviewMerchant(_ application: MerchantApplication, approve: Bool, reason: String?) async -> Bool {
        await perform(
            identity: "merchant:\(application.applicationID):\(approve):\(reason ?? "")",
            success: approve ? "Merchant approved." : "Merchant application declined."
        ) { key in
            _ = try await self.merchantApplicationClient.review(
                applicationID: application.applicationID,
                decision: approve ? .approve : .reject,
                reason: reason,
                idempotencyKey: key
            )
        }
    }

    func reviewDelivery(_ application: DeliveryPartnerApplication, approve: Bool, reason: String?) async -> Bool {
        await perform(
            identity: "delivery:\(application.applicationID):\(approve):\(reason ?? "")",
            success: approve ? "Delivery Partner approved." : "Delivery Partner application declined."
        ) { key in
            _ = try await self.deliveryApplicationClient.review(
                applicationID: application.applicationID,
                decision: approve ? .approve : .reject,
                reason: reason,
                idempotencyKey: key
            )
        }
    }

    func evidenceURL(objectPath: String) async -> URL? {
        guard !isBusy else { return nil }
        busyIdentity = "evidence:\(objectPath)"
        defer { busyIdentity = nil }
        do {
            let download = try await v1Client.evidenceDownloadURL(
                objectPath: objectPath,
                idempotencyKey: key()
            )
            guard let url = URL(string: download.signedURL), url.scheme == "https", url.host != nil else {
                throw URLError(.badURL)
            }
            actionErrorMessage = nil
            return url
        } catch {
            actionErrorMessage = message(for: error, fallback: "This private evidence could not be opened. Try again.")
            return nil
        }
    }

    func setOperationalPause(
        scope: DastakAdminOperationalPauseScope,
        targetID: UUID,
        active: Bool,
        reason: String,
        expectedVersion: Int
    ) async -> Bool {
        await perform(
            identity: "pause:\(scope.rawValue):\(targetID):\(active):\(expectedVersion):\(reason)",
            success: active ? "New work paused for the selected scope." : "New work resumed for the selected scope."
        ) { key in
            _ = try await self.v1Client.setOperationalPause(
                scope: scope,
                targetID: targetID,
                active: active,
                reason: reason,
                expectedVersion: expectedVersion,
                idempotencyKey: key
            )
        }
    }

    func manageRiderEscalation(
        _ escalation: DastakAdminOperationalSafety.RiderEscalation,
        action: String,
        reason: String
    ) async -> Bool {
        await perform(
            identity: "rider-escalation:\(escalation.missionID):\(action):\(escalation.version):\(reason)",
            success: action == "RELEASE_REMATCH"
                ? "Rider released and matching restarted."
                : "Delivery recovery started with custody protected."
        ) { key in
            _ = try await self.v1Client.manageRiderEscalation(
                missionID: escalation.missionID,
                action: action,
                reason: reason,
                expectedVersion: escalation.version,
                idempotencyKey: key
            )
        }
    }

    func loadNetwork(
        query: String = "",
        persona: DastakAdminPersona? = nil,
        state: DastakAdminPersonaState? = nil,
        append: Bool = false
    ) async {
        guard !isLoadingNetwork else { return }
        isLoadingNetwork = true
        defer { isLoadingNetwork = false }
        do {
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let page = try await v1Client.networkPage(
                query: normalizedQuery.isEmpty ? nil : normalizedQuery,
                persona: persona,
                state: state,
                limit: 40,
                cursor: append ? networkCursor : nil,
                idempotencyKey: key()
            )
            networkPeople = append ? networkPeople + page.people : page.people
            networkCursor = page.nextCursor
            networkHasMore = page.hasMore
            recordSuccess(.network)
        } catch {
            recordFailure(
                .network,
                message: passiveMessage(for: error, fallback: "The marketplace network could not be loaded.")
            )
        }
    }

    func loadCatalogue(
        query: String = "",
        categoryTypeID: UUID? = nil,
        categoryID: UUID? = nil,
        subcategoryID: UUID? = nil,
        status: String? = nil,
        qaStatus: String? = nil,
        append: Bool = false
    ) async {
        guard !isLoadingCatalogue else { return }
        isLoadingCatalogue = true
        defer { isLoadingCatalogue = false }
        do {
            if !append, catalogueTaxonomy == nil {
                catalogueTaxonomy = try await v1Client.catalogueTaxonomy(
                    idempotencyKey: key()
                )
            }
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let page = try await v1Client.cataloguePage(
                query: normalizedQuery.isEmpty ? nil : normalizedQuery,
                categoryTypeID: categoryTypeID,
                categoryID: categoryID,
                subcategoryID: subcategoryID,
                status: status,
                qaStatus: qaStatus,
                limit: 40,
                cursor: append ? catalogueCursor : nil,
                idempotencyKey: key()
            )
            catalogueSKUs = append ? catalogueSKUs + page.skus : page.skus
            catalogueCursor = page.nextCursor
            catalogueHasMore = page.hasMore
            recordSuccess(.catalogue)
        } catch {
            recordFailure(
                .catalogue,
                message: passiveMessage(for: error, fallback: "The master catalogue could not be loaded.")
            )
        }
    }

    func updateCatalogueSKU(
        _ sku: DastakAdminCatalogueSKU,
        listPricePaise: Int,
        sellingPricePaise: Int,
        status: String
    ) async -> Bool {
        await perform(
            identity: "sku:\(sku.id):\(sku.version):\(listPricePaise):\(sellingPricePaise):\(status)",
            success: "Catalogue SKU updated."
        ) { key in
            _ = try await self.v1Client.updateCatalogueSKU(
                id: sku.id,
                expectedVersion: sku.version,
                listPricePaise: listPricePaise,
                sellingPricePaise: sellingPricePaise,
                status: status,
                idempotencyKey: key
            )
            await self.loadCatalogue()
        }
    }

    func retry(_ workspace: DastakAdminWorkspace) async {
        if workspace == .network {
            await loadNetwork()
            return
        }
        if workspace == .catalogue {
            await loadCatalogue()
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        switch workspace {
        case .operations:
            let client = operationsClient
            let requestKey = key()
            let result = await loadAdminWorkspace(
                .operations,
                fallback: "Order support and recovery could not be refreshed."
            ) { try await client.snapshot(limit: 100, idempotencyKey: requestKey) }
            if let value = resolve(result, workspace: .operations) { snapshot = value }
        case .liveOrders:
            await retryLiveOrders()
        case .adminAccess:
            let client = v1Client
            let requestKey = key()
            let result = await loadAdminWorkspace(
                .adminAccess,
                fallback: "Protected Admin access settings could not be refreshed."
            ) { try await client.access(idempotencyKey: requestKey) }
            if let value = resolve(result, workspace: .adminAccess) { adminAccess = value }
        case .commandCenter:
            let client = v1Client
            let requestKey = key()
            let result = await loadAdminWorkspace(
                .commandCenter,
                fallback: "Command center metrics could not be refreshed."
            ) { try await client.commandCenter(idempotencyKey: requestKey) }
            if let value = resolve(result, workspace: .commandCenter) { commandCenter = value }
        case .merchantApprovals:
            let client = merchantApplicationClient
            let requestKey = key()
            let result = await loadAdminWorkspace(
                .merchantApprovals,
                fallback: "Merchant applications could not be refreshed."
            ) { try await client.listPending(idempotencyKey: requestKey) }
            if let value = resolve(result, workspace: .merchantApprovals) { merchantApplications = value }
        case .deliveryApprovals:
            let client = deliveryApplicationClient
            let requestKey = key()
            let result = await loadAdminWorkspace(
                .deliveryApprovals,
                fallback: "Delivery Partner applications could not be refreshed."
            ) { try await client.listPending(idempotencyKey: requestKey) }
            if let value = resolve(result, workspace: .deliveryApprovals) { deliveryApplications = value }
        case .systemHealth:
            let client = v1Client
            let requestKey = key()
            let result = await loadAdminWorkspace(
                .systemHealth,
                fallback: "System health signals could not be refreshed."
            ) { try await client.systemHealth(idempotencyKey: requestKey) }
            if let value = resolve(result, workspace: .systemHealth) { systemHealth = value }
        case .operationalSafety:
            let client = v1Client
            let requestKey = key()
            let result = await loadAdminWorkspace(
                .operationalSafety,
                fallback: "Safety controls and escalation signals could not be refreshed."
            ) { try await client.operationalSafety(idempotencyKey: requestKey) }
            if let value = resolve(result, workspace: .operationalSafety) { operationalSafety = value }
        case .royaltyPayouts:
            let client = v1Client
            let requestKey = key()
            let result = await loadAdminWorkspace(
                .royaltyPayouts,
                fallback: "Royalty payout reconciliation could not be refreshed."
            ) { try await client.royaltyPayouts(limit: 100, idempotencyKey: requestKey) }
            if let value = resolve(result, workspace: .royaltyPayouts) { royaltyPayouts = value }
        case .network, .catalogue:
            break
        }
    }

    private func retryLiveOrders() async {
        let client = v1Client
        let ordersKey = key()
        let orderResult = await loadAdminWorkspace(
            .liveOrders,
            fallback: "Live order and collection trace could not be refreshed."
        ) { try await client.orders(limit: 50, idempotencyKey: ordersKey) }
        guard let orders = resolve(orderResult, workspace: .liveOrders) else { return }
        v1Orders = orders
        let selectedID = v1Trace.map(\.order.id).flatMap { current in
            orders.contains(where: { $0.id == current }) ? current : nil
        } ?? orders.first?.id
        guard let selectedID else {
            v1Trace = nil
            return
        }
        let traceKey = key()
        let traceResult = await loadAdminWorkspace(
            .liveOrders,
            fallback: "The selected order trace could not be refreshed."
        ) { try await client.trace(orderID: selectedID, idempotencyKey: traceKey) }
        if let value = resolve(traceResult, workspace: .liveOrders) { v1Trace = value }
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
            actionErrorMessage = nil
            await refresh()
            return true
        } catch {
            actionErrorMessage = message(for: error, fallback: "The Admin action could not be completed.")
            return false
        }
    }

    private func resolve<Value: Sendable>(
        _ result: DastakAdminLoadResult<Value>,
        workspace: DastakAdminWorkspace
    ) -> Value? {
        switch result {
        case let .success(value):
            recordSuccess(workspace)
            return value
        case let .failure(issue):
            var state = workspaceState
            state.recordFailure(issue)
            workspaceState = state
            return nil
        }
    }

    private func recordSuccess(_ workspace: DastakAdminWorkspace) {
        var state = workspaceState
        state.recordSuccess(workspace)
        workspaceState = state
    }

    private func recordFailure(_ workspace: DastakAdminWorkspace, message: String) {
        var state = workspaceState
        state.recordFailure(
            DastakAdminWorkspaceIssue(workspace: workspace, message: message, occurredAt: Date())
        )
        workspaceState = state
    }

    private func passiveMessage(for error: Error, fallback: String) -> String {
        switch error {
        case FunctionClientError.authenticationRequired,
             FunctionClientError.api(statusCode: 401, code: _, message: _):
            "Your Admin session needs to be refreshed. Reopen the app or sign in again."
        default:
            fallback
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
    private enum Tab: Hashable { case overview, approvals, operations, network, more }

    private let services: MarketplaceAuthenticatedServices
    @StateObject private var model: DastakOwnerOperationsModel
    @State private var tab: Tab = .overview
    @Environment(\.scenePhase) private var scenePhase

    public init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        _model = StateObject(wrappedValue: DastakOwnerOperationsModel(services: services))
    }

    public var body: some View {
        TabView(selection: $tab) {
            DastakAdminOverviewView(model: model)
                .tabItem { Label("Overview", systemImage: "rectangle.grid.2x2") }
                .tag(Tab.overview)

            DastakAdminApprovalsView(model: model)
                .tabItem { Label("Approvals", systemImage: "checkmark.shield") }
                .badge(model.merchantApplications.count + model.deliveryApplications.count)
                .tag(Tab.approvals)

            DastakOwnerOperationsView(model: model)
                .tabItem { Label("Orders", systemImage: "shippingbox.and.arrow.backward") }
                .tag(Tab.operations)

            DastakAdminNetworkView(model: model)
                .tabItem { Label("Network", systemImage: "person.3") }
                .tag(Tab.network)

            DastakAdminMoreView(model: model, services: services)
                .tabItem { Label("More", systemImage: "square.grid.2x2") }
                .tag(Tab.more)
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
        .overlay(alignment: .top) {
            if let message = model.actionErrorMessage ?? model.notice {
                let isError = model.actionErrorMessage != nil
                HStack(spacing: 10) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? MarketplaceColors.destructive.color : MarketplaceColors.success.color)
                    Text(message).font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                    Button {
                        if isError { model.actionErrorMessage = nil } else { model.notice = nil }
                    } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(isError ? "Dismiss error" : "Dismiss confirmation")
                }
                .padding(.horizontal, MarketplaceSpacing.medium)
                .frame(minHeight: 52)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 18, y: 7)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.actionErrorMessage ?? model.notice)
    }
}

struct DastakAdminRefreshSummaryCard: View {
    let issues: [DastakAdminWorkspaceIssue]
    let isRefreshing: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title2)
                    .foregroundStyle(MarketplaceColors.warning.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Some workspaces need a refresh")
                        .font(.headline)
                    Text("Current data remains available. Pull down to refresh \(workspaceNames).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(MarketplaceSpacing.medium)
        .background(MarketplaceColors.warning.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MarketplaceColors.warning.color.opacity(0.35))
        }
        .accessibilityElement(children: .contain)
    }

    private var workspaceNames: String {
        issues.map(\.workspace.displayName).joined(separator: ", ")
    }
}

struct DastakAdminWorkspaceIssueCard: View {
    let issue: DastakAdminWorkspaceIssue
    let lastSuccessfulRefresh: Date?
    let isRefreshing: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.warning.color)
                    .frame(width: 38, height: 38)
                    .background(MarketplaceColors.warning.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(issue.workspace.displayName) needs a refresh")
                        .font(.headline)
                    Text(issue.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(refreshDetail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            Label("Pull down to try this workspace again", systemImage: "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .accessibilityElement(children: .contain)
    }

    private var refreshDetail: String {
        if let lastSuccessfulRefresh {
            return "Last updated \(lastSuccessfulRefresh.formatted(date: .abbreviated, time: .shortened))"
        }
        return "No successful response has been received yet."
    }
}

struct DastakAdminAccessView: View {
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

                    if let issue = model.issue(for: .adminAccess) {
                        DastakAdminWorkspaceIssueCard(
                            issue: issue,
                            lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: .adminAccess),
                            isRefreshing: model.isRefreshing
                        ) { Task { await model.retry(.adminAccess) } }
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
                    } else if model.issue(for: .adminAccess) == nil {
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

struct DastakOwnerOperationsView: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    @State private var selectedException: OwnerOrderException?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    header
                    if let issue = model.issue(for: .operations) {
                        DastakAdminWorkspaceIssueCard(
                            issue: issue,
                            lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: .operations),
                            isRefreshing: model.isRefreshing
                        ) { Task { await model.retry(.operations) } }
                    }
                    if let issue = model.issue(for: .liveOrders) {
                        DastakAdminWorkspaceIssueCard(
                            issue: issue,
                            lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: .liveOrders),
                            isRefreshing: model.isRefreshing
                        ) { Task { await model.retry(.liveOrders) } }
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

    private var unavailable: some View {
        ContentUnavailableView {
            Label("Operations unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Check your connection, then pull down to refresh.")
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
            succeeded = model.actionErrorMessage == nil
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
