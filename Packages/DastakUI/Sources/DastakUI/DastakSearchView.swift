import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakSearchView: View {
    @ObservedObject var model: DastakCustomerModel
    let chooseLocation: () -> Void
    let openCart: () -> Void

    var body: some View {
        Group {
            if model.isSearchingV1Catalogue {
                ProgressView("Searching products")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = model.v1SearchRefreshFailure, model.v1SearchResults.isEmpty,
                      !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DastakEmptyState(symbol: failure.symbol, title: failure.title,
                                 message: failure.message,
                                 actionTitle: model.hasMoreV1SearchResults ? "Retry loading more" : "Retry search",
                                 action: {
                                     Task {
                                         if model.hasMoreV1SearchResults { await model.loadMoreV1SearchResults() }
                                         else { await model.searchV1Catalogue() }
                                     }
                                 })
            } else if model.isLoadingV1Catalogue, model.v1Catalogue == nil,
                      model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ProgressView("Loading products")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.v1Catalogue == nil, let failure = model.v1CatalogueRefreshFailure,
                      model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DastakEmptyState(
                    symbol: failure.symbol,
                    title: failure.title,
                    message: failure.message,
                    actionTitle: failure.actionTitle,
                    action: { Task { await model.refreshV1Catalogue() } }
                )
            } else if model.activeProducts.isEmpty, !model.hasMoreV1SearchResults {
                DastakEmptyState(
                    symbol: "magnifyingglass",
                    title: model.searchText.isEmpty ? "Catalogue is empty" : "No matches",
                    message: model.searchText.isEmpty
                        ? "Dastak is preparing products for launch."
                        : "Try a product, brand or category name."
                )
            } else {
                List {
                    ForEach(model.activeProducts) { product in
                        productRow(product).listRowBackground(Color.clear)
                    }
                    if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchPagination.listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await model.refreshV1Catalogue() }
                    else { await model.searchV1Catalogue() }
                }
            }
        }
        .dastakBasketExperience(model: model, service: .grocery, openCart: openCart)
        .marketplacePage()
        .navigationTitle("Search")
        .searchable(text: $model.searchText, prompt: "Products, brands and categories")
        .task(id: model.searchText) {
            guard !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await model.searchV1Catalogue()
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.searchV1Catalogue()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !model.hasBasket(.grocery) { DastakBasketPickupButton(model: model, service: .grocery) }
            }
        }
    }

    @ViewBuilder
    private var searchPagination: some View {
        if model.isLoadingMoreV1SearchResults {
            ProgressView("Loading more products")
        } else if let failure = model.v1SearchRefreshFailure {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not all matching products could be loaded. \(failure.message)")
                    .font(.subheadline).foregroundStyle(.secondary)
                MarketplaceFeedbackButton(model.hasMoreV1SearchResults ? "Retry loading more" : "Refresh search") {
                    Task {
                        if model.hasMoreV1SearchResults { await model.loadMoreV1SearchResults() }
                        else { await model.searchV1Catalogue() }
                    }
                }
                .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
            }
        } else if model.hasMoreV1SearchResults {
            MarketplaceFeedbackButton("Load more products") {
                Task { await model.loadMoreV1SearchResults() }
            }
            .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
        }
    }

    private func productRow(_ product: DastakV1CatalogueSKU) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            DastakProductArtwork(imageKey: product.imageKey, fallbackSymbol: artworkSymbol(for: product))
                .frame(width: 68)
                .dastakBasketAnchor(DastakBasketService.grocery.itemAnchor(product.id))

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

            MarketplaceFeedbackButton {
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

            MarketplaceFeedbackButton { model.addShoppingProduct(product) } label: {
                Image(systemName: "plus")
                    .frame(
                        width: MarketplaceMetrics.minimumTouchTarget,
                        height: MarketplaceMetrics.minimumTouchTarget
                    )
            }
            .buttonStyle(.bordered)
            .tint(MarketplaceColors.dastakAccent.color)
            .accessibilityLabel("Add \(product.name)")
            .disabled(model.groceryAddIssue(product.id) != nil)
        }
    }

    private func artworkSymbol(for product: DastakV1CatalogueSKU) -> String {
        switch product.logisticsAttributes.temperatureClass {
        case "CHILLED", "FROZEN": "snowflake"
        default: product.logisticsAttributes.fragile == true ? "shippingbox" : "basket"
        }
    }
}
