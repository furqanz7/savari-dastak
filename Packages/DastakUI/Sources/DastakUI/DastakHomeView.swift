import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakHomeView: View {
    @ObservedObject var model: DastakCustomerModel
    let chooseLocation: () -> Void
    let openSearch: () -> Void
    let openCart: () -> Void
    let sendParcel: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                header
                promise
                searchButton
                categoryRail
                catalogueContent
                parcelBand
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .dastakNavigationBarHidden()
        .refreshable { await model.refreshV1Catalogue() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack {
                DastakWordmark(size: 31)
                Spacer()
                cartButton
            }

            Button(action: chooseLocation) {
                HStack(spacing: MarketplaceSpacing.small) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DELIVER TO")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(model.selectedLocation?.displayAddress ?? "Choose your delivery area")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, MarketplaceSpacing.medium)
    }

    private var promise: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text("YOUR EVERYDAY, DELIVERED")
                .font(.caption.weight(.bold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("One basket.\nDastak finds every item.")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 38))
                .fixedSize(horizontal: false, vertical: true)
            Label("You pay only after your full basket is secured", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(.vertical, MarketplaceSpacing.small)
    }

    private var searchButton: some View {
        Button(action: openSearch) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text("Search products and essentials")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .frame(minHeight: 52)
            .background(.regularMaterial)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MarketplaceMetrics.controlCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Search the Dastak product catalogue")
    }

    @ViewBuilder
    private var categoryRail: some View {
        if !model.canonicalCategories.isEmpty {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Text("Browse categories")
                    .font(MarketplaceTypography.sectionTitle)
                ScrollView(.horizontal) {
                    HStack(spacing: MarketplaceSpacing.compact) {
                        ForEach(model.canonicalCategories) { category in
                            Button(action: openSearch) {
                                VStack(spacing: 8) {
                                    Image(systemName: categorySymbol(category.slug))
                                        .font(.title2.weight(.light))
                                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                        .frame(width: 54, height: 54)
                                        .background(
                                            MarketplaceColors.dastakAccentSoft.color,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        )
                                    Text(category.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 84)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var catalogueContent: some View {
        if model.isLoadingV1Catalogue, model.v1Catalogue == nil {
            ProgressView("Loading Dastak catalogue")
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if model.v1Catalogue == nil, let failure = model.v1CatalogueRefreshFailure {
            DastakEmptyState(
                symbol: failure.symbol,
                title: failure.title,
                message: failure.message,
                actionTitle: failure.actionTitle,
                action: { Task { await model.refreshV1Catalogue() } }
            )
            .frame(minHeight: 280)
        } else if model.activeProducts.isEmpty {
            DastakEmptyState(
                symbol: "shippingbox",
                title: "Catalogue opening soon",
                message: "Dastak is preparing the first canonical products for your area."
            )
            .frame(minHeight: 280)
        } else {
            if let failure = model.v1CatalogueRefreshFailure {
                DastakRefreshNotice(
                    failure: failure,
                    action: { Task { await model.refreshV1Catalogue() } }
                )
            }
            ForEach(model.canonicalCategories) { category in
                let products = Array(model.products(in: category.id).prefix(6))
                if !products.isEmpty {
                    categorySection(category, products: products)
                }
            }
        }
    }

    private func categorySection(
        _ category: DastakV1CatalogueCategory,
        products: [DastakV1CatalogueSKU]
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.name)
                    .font(MarketplaceTypography.sectionTitle)
                Spacer()
                Button("See all", action: openSearch)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: MarketplaceSpacing.compact),
                    GridItem(.flexible(), spacing: MarketplaceSpacing.compact)
                ],
                spacing: MarketplaceSpacing.compact
            ) {
                ForEach(products) { product in
                    DastakV1ProductTile(product: product) {
                        model.addToCart(product)
                    }
                }
            }
        }
    }

    private var parcelBand: some View {
        Button(action: sendParcel) {
            HStack(spacing: MarketplaceSpacing.medium) {
                Image(systemName: "shippingbox.fill")
                    .font(.title2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 48, height: 48)
                    .background(
                        MarketplaceColors.dastakAccentSoft.color,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Send a parcel")
                        .font(.headline)
                    Text("Door-to-door delivery across your city")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(MarketplaceSpacing.compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marketplaceFlatSurface()
    }

    private var cartButton: some View {
        Button(action: openCart) {
            Image(systemName: "bag")
                .overlay(alignment: .topTrailing) {
                    if model.cart.itemCount > 0 {
                        Text(model.cart.itemCount.formatted())
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(MarketplaceColors.dastakAccent.color, in: Circle())
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .buttonStyle(MarketplaceIconButtonStyle())
        .accessibilityLabel("Basket, \(model.cart.itemCount) items")
    }

    private func categorySymbol(_ slug: String) -> String {
        if slug.contains("health") || slug.contains("care") { return "cross.case" }
        if slug.contains("food") || slug.contains("grocery") { return "basket" }
        if slug.contains("home") { return "house" }
        return "square.grid.2x2"
    }
}

struct DastakV1ProductTile: View {
    let product: DastakV1CatalogueSKU
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            DastakProductArtwork(symbol: artworkSymbol)

            if let brand = product.brand?.name {
                Text(brand.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .lineLimit(1)
            }
            Text(product.name)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
            Text([product.variant, product.packSize].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DastakFormatting.money(product.price))
                        .font(.headline.monospacedDigit())
                    if product.listPricePaise > product.sellingPricePaise {
                        Text(DastakFormatting.money(product.listPrice))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .strikethrough()
                    }
                }
                Spacer(minLength: 4)
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.white)
                        .background(
                            MarketplaceColors.primaryAction.color,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(product.name)")
            }
        }
        .padding(MarketplaceSpacing.small)
        .marketplaceFlatSurface()
    }

    private var artworkSymbol: String {
        switch product.logisticsAttributes.temperatureClass {
        case "CHILLED", "FROZEN": "snowflake"
        default: product.logisticsAttributes.fragile == true ? "shippingbox" : "basket"
        }
    }
}

#if DEBUG
private struct DastakHomeView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        NavigationStack {
            DastakHomeView(
                model: .preview(),
                chooseLocation: {},
                openSearch: {},
                openCart: {},
                sendParcel: {}
            )
        }
        .previewDisplayName("Customer V1 home")
    }
}
#endif
