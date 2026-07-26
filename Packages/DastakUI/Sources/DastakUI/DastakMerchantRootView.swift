import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

public struct DastakMerchantRootView: View {
    @StateObject private var model: DastakMerchantModel
    @Environment(\.marketplaceSignOut) private var signOut

    public init(services: MarketplaceAuthenticatedServices) {
        _model = StateObject(wrappedValue: DastakMerchantModel(services: services))
    }

    public var body: some View {
        TabView {
            DastakMerchantOrdersView(model: model)
                .tabItem { Label("Orders", systemImage: "list.bullet.clipboard") }

            DastakMerchantCatalogueView(model: model)
                .tabItem { Label("Catalogue", systemImage: "square.grid.2x2") }

            DastakMerchantStoreView(model: model)
                .tabItem { Label("Store", systemImage: "storefront") }

            merchantAccount
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
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

    private var merchantAccount: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: MarketplaceSpacing.compact) {
                        Image(systemName: "storefront")
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.store?.name ?? "Dastak Merchant")
                                .font(.headline)
                            Text(storeState)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Store") {
                    LabeledContent(
                        "Published",
                        value: model.store?.isPublished == true ? "Yes" : "No"
                    )
                    LabeledContent(
                        "Accepting orders",
                        value: model.store?.acceptingOrders == true ? "Yes" : "No"
                    )
                    LabeledContent("Products", value: model.products.count.formatted())
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await signOut() }
                    }
                }
            }
            .navigationTitle("Account")
        }
    }

    private var storeState: String {
        guard let store = model.store else { return "Store setup required" }
        if !store.isPublished { return "Store is not published" }
        return store.acceptingOrders ? "Open for orders" : "Not accepting orders"
    }
}
