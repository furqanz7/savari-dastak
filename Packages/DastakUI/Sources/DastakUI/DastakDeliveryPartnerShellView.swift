import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

public struct DastakDeliveryPartnerRootView: View {
    private enum Tab: Hashable {
        case deliveries
        case history
        case earnings
        case account
    }

    private let services: MarketplaceAuthenticatedServices
    @State private var selectedTab: Tab = .deliveries
    @State private var deliveryRefreshToken = 0
    @StateObject private var model: DastakDeliveryPartnerModel
    @StateObject private var operations: DastakDeliveryOperations
    @StateObject private var earningsModel: DastakDeliveryEarningsModel
    @Environment(\.scenePhase) private var scenePhase

    public init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        let operations = DastakDeliveryOperations(services: services)
        _operations = StateObject(wrappedValue: operations)
        _model = StateObject(wrappedValue: DastakDeliveryPartnerModel(functions: services.functions, operations: operations))
        _earningsModel = StateObject(wrappedValue: DastakDeliveryEarningsModel(services: services))
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            DastakDeliveryPartnerWorkspaceView(
                services: services,
                model: model,
                operations: operations,
                refreshToken: deliveryRefreshToken
            )
                .tabItem { Label("Deliveries", systemImage: "shippingbox") }
                .tag(Tab.deliveries)

            NavigationStack {
                ScrollView {
                    VStack(spacing: 18) {
                        activeJobButton
                        DastakDeliveryHistoryView(operations: operations, services: services, standalone: true)
                    }.padding(16).padding(.bottom, 24)
                }
                .refreshable { await operations.refreshHistory() }
                .navigationTitle("History")
                .dastakInlineNavigationTitle()
            }
            .marketplacePage()
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(Tab.history)

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        activeJobButton
                        if let earnings = model.earnings {
                            DastakEarningsCard(earnings: earnings, title: "Delivery earnings")
                        } else {
                            Text("Earnings are unavailable. Pull to refresh; no balance is assumed.")
                        }
                        Text("Delivery summaries are not a withdrawable balance. Your ledger and payout records are below.")
                            .font(.footnote).foregroundStyle(.secondary)
                        DastakDeliveryEarningsView(model: earningsModel)
                    }.padding(16)
                }
                .refreshable { await model.refresh(); await earningsModel.load() }
                .navigationTitle("Earnings")
                .dastakInlineNavigationTitle()
            }
            .marketplacePage()
            .tabItem { Label("Earnings", systemImage: "indianrupeesign.circle") }
            .tag(Tab.earnings)

            DastakIdentityAccountView(
                roleName: "Delivery Partner",
                openWorkspace: { selectedTab = .deliveries },
                services: services
            )
            .tabItem { Label("Account", systemImage: "person") }
            .tag(Tab.account)
        }
        .tint(MarketplaceColors.dastakAccent.color)
        .marketplaceSelectionFeedback(selectedTab)
        .marketplaceHaptics()
        .modifier(DastakDeliveryScreenAwake(enabled: model.hasActiveJob && scenePhase == .active))
        .background {
            DastakDeliveryTrackerBridge(dispatch: model.v1Dispatch, isAuthoritative: !model.isLoading)
        }
        .task { await operations.restore(); await model.bootstrap() }
        .task { await observeOrderChanges() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(model.hasActiveJob || operations.pending != nil ? 10 : 30))
                guard !Task.isCancelled else { return }
                if scenePhase == .active {
                    if model.hasActiveJob || operations.pending != nil || !operations.restored { await model.recoverDesk(force: false) }
                    else { await model.refresh() }
                }
            }
        }
        .onChange(of: scenePhase) { _, value in
            if value == .active { Task { await model.recoverDesk(force: false) } }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .history { Task { await operations.refreshHistory() } }
            guard tab == .deliveries else { return }
            deliveryRefreshToken &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dastak.notification.orderOpened"))) { event in
            if event.userInfo?["entityType"] as? String == "delivery" {
                selectedTab = .deliveries
                deliveryRefreshToken &+= 1
            }
        }
    }

    @ViewBuilder private var activeJobButton: some View {
        if model.hasActiveJob {
            Button { selectedTab = .deliveries } label: {
                Label("Return to your active delivery", systemImage: "location.north.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(MarketplacePrimaryButtonStyle())
        }
    }

    private func observeOrderChanges() async {
        while !Task.isCancelled {
            do {
                let accountID = try await services.accountID()
                for try await event in services.orderEvents.events(accountID: accountID) {
                    guard !Task.isCancelled else { return }
                    await model.refreshOrderChange(event.entityKind)
                }
            } catch is CancellationError { return }
            catch { /* The independent poll keeps assignments current while reconnecting. */ }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
