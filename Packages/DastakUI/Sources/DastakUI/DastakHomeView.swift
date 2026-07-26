import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakHomeView: View {
    @ObservedObject var model: DastakCustomerModel
    let chooseLocation: () -> Void
    let openSearch: () -> Void
    let openCart: () -> Void
    let sendParcel: () -> Void

    @State private var pendingStoreReplacement: CatalogueProduct?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                header
                searchButton
                parcelBand
                catalogueContent
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .dastakNavigationBarHidden()
        .refreshable {
            await model.refreshCatalogue()
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
            Button("Keep current basket", role: .cancel) {
                pendingStoreReplacement = nil
            }
        } message: {
            Text("Your basket can contain items from one store at a time.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack {
                DastakWordmark(size: 30)
                Spacer()
                cartButton
            }

            HStack(spacing: MarketplaceSpacing.small) {
                Button(action: chooseLocation) {
                    HStack(spacing: MarketplaceSpacing.small) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Deliver to")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.selectedLocation?.address ?? "Choose location")
                                .font(.subheadline.bold())
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: MarketplaceSpacing.small)

                Menu {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { radius in
                        Button {
                            Task { await model.setDiscoveryRadius(radius) }
                        } label: {
                            if radius == model.discoveryRadiusKilometres {
                                Label("\(radius) km", systemImage: "checkmark")
                            } else {
                                Text("\(radius) km")
                            }
                        }
                    }
                } label: {
                    Label(
                        "\(model.discoveryRadiusKilometres) km",
                        systemImage: "scope"
                    )
                    .font(.subheadline.bold())
                    .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
                }
            }
        }
        .padding(.top, MarketplaceSpacing.medium)
    }

    private var searchButton: some View {
        Button(action: openSearch) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: "magnifyingglass")
                Text("Search stores and products")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .frame(minHeight: 50)
            .background(.regularMaterial)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MarketplaceMetrics.controlCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
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
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var catalogueContent: some View {
        if model.selectedLocation == nil {
            DastakEmptyState(
                symbol: "location",
                title: "Choose a delivery location",
                message: "Dastak will show stores within your selected range.",
                actionTitle: "Choose location",
                action: chooseLocation
            )
            .frame(minHeight: 320)
        } else if model.isLoadingCatalogue, model.catalogue == nil {
            ProgressView("Finding nearby stores")
                .frame(maxWidth: .infinity, minHeight: 320)
        } else if let catalogue = model.catalogue, catalogue.stores.isEmpty {
            DastakEmptyState(
                symbol: "storefront",
                title: "No stores in this range",
                message: "Increase the range up to 30 km or choose another location."
            )
            .frame(minHeight: 320)
        } else {
            ForEach(model.catalogue?.stores ?? [], id: \.storeID) { store in
                storeSection(store)
            }
        }
    }

    private func storeSection(_ store: CatalogueStore) -> some View {
        let products = (model.catalogue?.products ?? []).filter {
            $0.storeID == store.storeID && $0.isActive
        }
        return VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.name)
                        .font(MarketplaceTypography.sectionTitle)
                    Text(store.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                DastakStatusPill(
                    text: store.acceptingOrders ? "Open" : "Paused",
                    emphasis: store.acceptingOrders
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: MarketplaceSpacing.compact),
                    GridItem(.flexible(), spacing: MarketplaceSpacing.compact)
                ],
                spacing: MarketplaceSpacing.compact
            ) {
                ForEach(products, id: \.productID) { product in
                    DastakProductTile(product: product) {
                        add(product)
                    }
                }
            }
        }
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

    private func add(_ product: CatalogueProduct) {
        if model.cart.add(product) == .differentStore {
            pendingStoreReplacement = product
        }
    }
}

private struct DastakProductTile: View {
    let product: CatalogueProduct
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            DastakProductArtwork(kind: product.catalogueKind)

            Text(product.name)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)

            Text(product.unitLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .center) {
                Text(DastakFormatting.money(product.price))
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .foregroundStyle(.white)
                        .background(
                            MarketplaceColors.primaryAction.color,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(product.availability != .inStock)
                .accessibilityLabel("Add \(product.name)")
            }
        }
        .padding(MarketplaceSpacing.small)
        .marketplaceFlatSurface()
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
        .previewDisplayName("Customer home")
    }
}
#endif
