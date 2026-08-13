import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakSearchView: View {
    @ObservedObject var model: DastakCustomerModel
    let openCart: () -> Void

    @State private var pendingStoreReplacement: CatalogueProduct?

    var body: some View {
        Group {
            if model.selectedLocation == nil {
                DastakEmptyState(
                    symbol: "location",
                    title: "Location needed",
                    message: "Choose a delivery location from Home before searching."
                )
            } else if model.catalogue == nil, let failure = model.catalogueRefreshFailure {
                DastakEmptyState(
                    symbol: failure.symbol,
                    title: failure.title,
                    message: failure.message,
                    actionTitle: failure.actionTitle,
                    action: { Task { await model.refreshCatalogue() } }
                )
            } else if model.activeProducts.isEmpty {
                DastakEmptyState(
                    symbol: "magnifyingglass",
                    title: model.searchText.isEmpty ? "Nothing nearby" : "No matches",
                    message: model.searchText.isEmpty
                        ? "No products are available in this range."
                        : "Try a product, store, or category name."
                )
            } else {
                List(model.activeProducts, id: \.productID) { product in
                    HStack(spacing: MarketplaceSpacing.compact) {
                        DastakProductArtwork(kind: product.catalogueKind)
                            .frame(width: 68)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                                .font(.headline)
                            Text(product.unitLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(DastakFormatting.money(product.price))
                                .font(.subheadline.bold().monospacedDigit())
                        }

                        Spacer()

                        Button {
                            if model.cart.add(product) == .differentStore {
                                pendingStoreReplacement = product
                            }
                        } label: {
                            Image(systemName: "plus")
                                .frame(
                                    width: MarketplaceMetrics.minimumTouchTarget,
                                    height: MarketplaceMetrics.minimumTouchTarget
                                )
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Add \(product.name)")
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $model.searchText, prompt: "Products and stores")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openCart) {
                    Image(systemName: "bag")
                        .overlay(alignment: .topTrailing) {
                            if model.cart.itemCount > 0 {
                                Text(model.cart.itemCount.formatted())
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(
                                        MarketplaceColors.dastakAccent.color,
                                        in: Circle()
                                    )
                                    .offset(x: 7, y: -7)
                            }
                        }
                }
                .accessibilityLabel("Basket, \(model.cart.itemCount) items")
            }
        }
        .confirmationDialog(
            "Start a new basket?",
            isPresented: Binding(
                get: { pendingStoreReplacement != nil },
                set: { if !$0 { pendingStoreReplacement = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace basket", role: .destructive) {
                if let product = pendingStoreReplacement {
                    model.cart.replaceStore(with: product)
                }
                pendingStoreReplacement = nil
            }
            Button("Keep current basket", role: .cancel) {}
        } message: {
            Text("Your basket can contain items from one store at a time.")
        }
    }
}
