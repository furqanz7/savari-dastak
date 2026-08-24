import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakSearchView: View {
    @ObservedObject var model: DastakCustomerModel
    let chooseLocation: () -> Void
    let openCart: () -> Void

    var body: some View {
        Group {
            if model.isLoadingV1Catalogue, model.v1Catalogue == nil {
                ProgressView("Loading products")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.v1Catalogue == nil, let failure = model.v1CatalogueRefreshFailure {
                DastakEmptyState(
                    symbol: failure.symbol,
                    title: failure.title,
                    message: failure.message,
                    actionTitle: failure.actionTitle,
                    action: { Task { await model.refreshV1Catalogue() } }
                )
            } else if model.activeProducts.isEmpty {
                DastakEmptyState(
                    symbol: "magnifyingglass",
                    title: model.searchText.isEmpty ? "Catalogue is empty" : "No matches",
                    message: model.searchText.isEmpty
                        ? "Dastak is preparing products for launch."
                        : "Try a product, brand or category name."
                )
            } else {
                List(model.activeProducts) { product in
                    productRow(product).listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .refreshable { await model.refreshV1Catalogue() }
            }
        }
        .marketplacePage()
        .navigationTitle("Search")
        .searchable(text: $model.searchText, prompt: "Products, brands and categories")
        .task(id: model.searchText) {
            guard !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.searchV1Catalogue()
        }
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
                                    .background(MarketplaceColors.dastakAccent.color, in: Circle())
                                    .offset(x: 7, y: -7)
                            }
                        }
                }
                .accessibilityLabel("Basket, \(model.cart.itemCount) items")
            }
        }
    }

    private func productRow(_ product: DastakV1CatalogueSKU) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            DastakProductArtwork(symbol: artworkSymbol(for: product))
                .frame(width: 68)

            VStack(alignment: .leading, spacing: 4) {
                if let brand = product.brand?.name {
                    Text(brand.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                Text(product.name).font(.headline)
                Text([product.variant, product.packSize].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(DastakFormatting.money(product.price))
                        .font(.subheadline.bold().monospacedDigit())
                    if product.listPricePaise > product.sellingPricePaise {
                        Text(DastakFormatting.money(product.listPrice))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .strikethrough()
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                Task { await model.toggleWishlist(kind: .retailSKU, itemID: product.id) }
            } label: {
                Image(systemName: model.isWishlisted(kind: .retailSKU, itemID: product.id) ? "heart.fill" : "heart")
                    .frame(
                        width: MarketplaceMetrics.minimumTouchTarget,
                        height: MarketplaceMetrics.minimumTouchTarget
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(MarketplaceColors.dastakAccent.color)
            .disabled(model.wishlistUpdatingIDs.contains(product.id))
            .accessibilityLabel(
                model.isWishlisted(kind: .retailSKU, itemID: product.id)
                    ? "Remove \(product.name) from Wishlist"
                    : "Save \(product.name) to Wishlist"
            )

            Button { model.addToCart(product) } label: {
                Image(systemName: "plus")
                    .frame(
                        width: MarketplaceMetrics.minimumTouchTarget,
                        height: MarketplaceMetrics.minimumTouchTarget
                    )
            }
            .buttonStyle(.bordered)
            .tint(MarketplaceColors.dastakAccent.color)
            .accessibilityLabel("Add \(product.name)")
        }
    }

    private func artworkSymbol(for product: DastakV1CatalogueSKU) -> String {
        switch product.logisticsAttributes.temperatureClass {
        case "CHILLED", "FROZEN": "snowflake"
        default: product.logisticsAttributes.fragile == true ? "shippingbox" : "basket"
        }
    }
}
