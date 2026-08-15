import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

public struct DastakMerchantRootView: View {
    private enum Section: Hashable {
        case orders
        case catalogue
        case store
        case account
    }

    @StateObject private var model: DastakMerchantModel
    @State private var section: Section = .orders
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

            DastakMerchantCatalogueView(model: model)
                .tabItem { Label("Catalogue", systemImage: "square.grid.2x2") }
                .tag(Section.catalogue)

            DastakMerchantStoreView(model: model)
                .tabItem { Label("Store", systemImage: "storefront") }
                .tag(Section.store)

            DastakIdentityAccountView(
                roleName: "Merchant",
                openWorkspace: { section = .store },
                services: services
            )
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(Section.account)
        }
        .tint(MarketplaceColors.dastakAccent.color)
        .marketplacePage()
        .task {
            await model.bootstrap()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await model.refreshOrders()
            }
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

}
