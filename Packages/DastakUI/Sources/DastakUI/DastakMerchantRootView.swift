import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

public struct DastakMerchantRootView: View {
    private enum Section: Hashable {
        case orders
        case store
        case account
    }

    @StateObject private var model: DastakMerchantModel
    @State private var section: Section = .orders
    @Environment(\.scenePhase) private var scenePhase
    private let services: MarketplaceAuthenticatedServices

    public init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        _model = StateObject(wrappedValue: DastakMerchantModel(services: services))
    }

    public var body: some View {
        TabView(selection: $section) {
            DastakMerchantOrdersView(model: model)
                .tabItem { Label("Orders", systemImage: "list.bullet.clipboard") }
                .tag(Section.orders)

            DastakMerchantStoreAndCatalogueView(model: model)
                .tabItem { Label("Store", systemImage: "square.grid.2x2") }
                .tag(Section.store)

            DastakIdentityAccountView(
                roleName: "Merchant",
                openWorkspace: { section = .store },
                services: services
            )
                .tabItem { Label("Account", systemImage: "person.text.rectangle") }
                .tag(Section.account)
        }
        .tint(MarketplaceColors.dastakAccent.color)
        .marketplacePage()
        .task {
            await model.bootstrap()
            openPendingOrders()
        }
        .task {
            await observeOrderChanges()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.notifications.refresh()
            while !Task.isCancelled {
                await model.refreshOrders()
                // Realtime is primary; this slower pass is outage recovery.
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dastak.merchant.ordersChanged"))) { _ in
            Task { await model.refreshOrders() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dastak.merchant.deviceTokenRegistered"))) { event in
            guard let token = event.object as? String else { return }
            Task { await model.notifications.receiveDeviceToken(token) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dastak.merchant.deviceTokenRegistrationFailed"))) { _ in
            model.notifications.registrationFailed()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dastak.merchant.openOrders"))) { _ in
            openPendingOrders()
            Task { await model.refreshOrders() }
        }
        .alert(
            "Dastak Merchant",
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

    private func openPendingOrders() {
        guard UserDefaults.standard.bool(forKey: "dastak.merchant.openOrders") else { return }
        section = .orders
        UserDefaults.standard.removeObject(forKey: "dastak.merchant.openOrders")
    }

    private func observeOrderChanges() async {
        while !Task.isCancelled {
            do {
                let accountID = try await services.accountID()
                for try await event in services.orderEvents.events(accountID: accountID) {
                    guard !Task.isCancelled else { return }
                    if event.entityKind == .merchantOrder,
                       model.v1Fulfilments.contains(where: { $0.orderID == event.entityID }) {
                        await model.refreshV1Fulfilments()
                    } else {
                        await model.refreshOrders()
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                // The fallback poll keeps the queue current while realtime reconnects.
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

}
