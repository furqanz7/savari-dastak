import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakHomeView: View {
    @ObservedObject var model: DastakCustomerModel
    let chooseLocation: () -> Void
    let openCart: () -> Void
    let sendParcel: () -> Void
    @State private var selectedRestaurant: DastakV1RestaurantMenu?
    @State private var selectedCategoryID: UUID?
    @State private var selectedSubcategoryID: UUID?
    @State private var isSearchPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    header
                    catalogueSearch
                    categoryRail
                    catalogueContent
                    restaurantRail
                    parcelBand
                }
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.bottom, 148)
            }
            .scrollIndicators(.hidden)
            .allowsHitTesting(!isSearchPresented)

            if isSearchPresented {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeSearch)

                searchOverlay
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .padding(.top, MarketplaceSpacing.small)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: isSearchPresented)
        .overlay(alignment: .bottom) {
            if !model.cart.isEmpty, !isSearchPresented {
                floatingCartButton
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .padding(.bottom, MarketplaceSpacing.small)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: model.cart.itemCount)
        .marketplacePage()
        .dastakNavigationBarHidden()
        .refreshable { await model.refreshV1Catalogue() }
        .sheet(item: $selectedRestaurant) { restaurant in
            DastakRestaurantMenuView(model: model, restaurant: restaurant)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var catalogueSearch: some View {
        Button(action: presentSearch) {
            HStack(spacing: MarketplaceSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                Text("Search products, brands and categories")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "mic.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .frame(minHeight: 52)
            .background(.ultraThinMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search Dastak catalogue")
    }

    @ViewBuilder
    private var restaurantRail: some View {
        if !model.v1Restaurants.isEmpty {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("RESTAURANTS & CAFES")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text("Food, in the same Dastak")
                            .font(MarketplaceTypography.sectionTitle)
                    }
                    Spacer()
                    Text("Choose one")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: MarketplaceSpacing.compact) {
                        ForEach(model.v1Restaurants) { restaurant in
                            Button { selectedRestaurant = restaurant } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: "fork.knife")
                                        .font(.title2)
                                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                        .frame(maxWidth: .infinity, minHeight: 72)
                                        .background(
                                            MarketplaceColors.dastakAccentSoft.color,
                                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        )
                                    Text(restaurant.restaurant.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(restaurant.restaurant.branchName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text("\(restaurant.categories.flatMap(\.items).count) items")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                }
                                .padding(MarketplaceSpacing.small)
                                .frame(width: 190, alignment: .leading)
                                .marketplaceFlatSurface()
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Open menu")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack {
                DastakWordmark(size: 31)
                Spacer()
                searchIconButton
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

    @ViewBuilder
    private var categoryRail: some View {
        if !model.canonicalCategories.isEmpty {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                HStack(alignment: .firstTextBaseline, spacing: MarketplaceSpacing.small) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SHOP DASTAK")
                            .font(.caption2.bold())
                            .tracking(1.1)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text(selectedCategory?.name ?? "Everything, beautifully organised")
                            .font(.title2.bold())
                            .lineLimit(2)
                    }
                    Spacer()
                    if selectedCategoryID != nil {
                        Button("All categories") {
                            selectedCategoryID = nil
                            selectedSubcategoryID = nil
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    }
                }

                if selectedCategoryID == nil {
                    ForEach(model.canonicalCategoryTypes) { type in
                        let categories = model.canonicalCategories.filter { $0.categoryTypeID == type.id }
                        if !categories.isEmpty {
                            VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                                Text(type.name).font(.title3.bold())
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                    spacing: MarketplaceSpacing.medium
                                ) {
                                    ForEach(categories) { category in
                                        Button {
                                            selectedCategoryID = category.id
                                            selectedSubcategoryID = nil
                                        } label: {
                                            DastakCategoryTile(category: category)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
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
                message: failure.message
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
            if let category = selectedCategory {
                categorySection(category, products: selectedProducts)
            } else {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                    Text("POPULAR NOW").font(.caption2.bold()).tracking(1.1).foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text("Everyday essentials").font(MarketplaceTypography.sectionTitle)
                    productGrid(Array(model.activeProducts.prefix(12)))
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
                Text(selectedSubcategory?.name ?? "All products")
                    .font(MarketplaceTypography.sectionTitle)
                Spacer()
                Text("\(products.count) products")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                LazyVStack(spacing: MarketplaceSpacing.compact) {
                    Button { selectedSubcategoryID = nil } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                .frame(width: 64, height: 58)
                                .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 14))
                            Text("All")
                                .font(.caption2.bold())
                                .foregroundStyle(.primary)
                        }
                        .padding(4)
                        .background(selectedSubcategoryID == nil ? MarketplaceColors.dastakAccentSoft.color : .clear, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    ForEach(visibleSubcategories) { subcategory in
                        Button { selectedSubcategoryID = subcategory.id } label: {
                            DastakSubcategoryTile(
                                subcategory: subcategory,
                                selected: selectedSubcategoryID == subcategory.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 72)

                productGrid(products)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func productGrid(_ products: [DastakV1CatalogueSKU]) -> some View {
        LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: MarketplaceSpacing.compact),
                    GridItem(.flexible(), spacing: MarketplaceSpacing.compact)
                ],
                spacing: MarketplaceSpacing.compact
        ) {
                ForEach(products) { product in
                    DastakV1ProductTile(
                        product: product,
                        isWishlisted: model.isWishlisted(kind: .retailSKU, itemID: product.id),
                        isUpdatingWishlist: model.wishlistUpdatingIDs.contains(product.id),
                        add: { model.addToCart(product) },
                        toggleWishlist: {
                            Task { await model.toggleWishlist(kind: .retailSKU, itemID: product.id) }
                        }
                    )
                }
        }
    }

    private var selectedCategory: DastakV1CatalogueCategory? {
        model.canonicalCategories.first { $0.id == selectedCategoryID }
    }

    private var visibleSubcategories: [DastakV1CatalogueSubcategory] {
        model.canonicalSubcategories.filter { $0.categoryID == selectedCategoryID }
    }

    private var selectedSubcategory: DastakV1CatalogueSubcategory? {
        visibleSubcategories.first { $0.id == selectedSubcategoryID }
    }

    private var selectedProducts: [DastakV1CatalogueSKU] {
        if let selectedSubcategoryID { return model.products(inSubcategory: selectedSubcategoryID) }
        guard let selectedCategoryID else { return model.activeProducts }
        return model.products(in: selectedCategoryID)
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

    @ViewBuilder
    private var floatingCartButton: some View {
        let button = Button(action: openCart) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: "bag.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 40, height: 40)
                    .background(
                        MarketplaceColors.dastakAccentSoft.color,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.cart.itemCount) \(model.cart.itemCount == 1 ? "item" : "items")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(DastakFormatting.money(model.cart.subtotal))
                        .font(.headline.monospacedDigit())
                }

                Spacer(minLength: MarketplaceSpacing.small)

                Text("View basket")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            .padding(.horizontal, MarketplaceSpacing.small)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "View basket, \(model.cart.itemCount) items, \(DastakFormatting.money(model.cart.subtotal))"
        )

        if #available(iOS 26.0, macOS 26.0, *) {
            button.glassEffect(
                .regular
                    .tint(MarketplaceColors.dastakAccent.color.opacity(0.14))
                    .interactive(),
                in: Capsule()
            )
        } else {
            button.marketplaceGlass(cornerRadius: 30)
        }
    }

    private var searchIconButton: some View {
        Button(action: presentSearch) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(MarketplaceIconButtonStyle())
        .accessibilityLabel("Search Dastak")
        .accessibilityHint("Opens product search")
    }

    private var searchOverlay: some View {
        VStack(spacing: MarketplaceSpacing.small) {
            HStack(spacing: MarketplaceSpacing.small) {
                searchField
                searchCloseButton
            }

            if !trimmedSearchText.isEmpty {
                searchResults
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: model.searchText) {
            guard !trimmedSearchText.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.searchV1Catalogue()
        }
    }

    @ViewBuilder
    private var searchField: some View {
        let field = HStack(spacing: MarketplaceSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)

            TextField("Search products and essentials", text: $model.searchText)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
#endif
                .focused($isSearchFieldFocused)
                .onSubmit {
                    Task { await model.searchV1Catalogue() }
                }
        }
        .padding(.horizontal, MarketplaceSpacing.medium)
        .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)

        if #available(iOS 26.0, macOS 26.0, *) {
            field.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            field.marketplaceGlass(cornerRadius: MarketplaceMetrics.minimumTouchTarget / 2)
        }
    }

    @ViewBuilder
    private var searchCloseButton: some View {
        let button = Button(action: closeSearch) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .frame(
                    width: MarketplaceMetrics.minimumTouchTarget,
                    height: MarketplaceMetrics.minimumTouchTarget
                )
        }
        .accessibilityLabel("Close search")

        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            button.buttonStyle(MarketplaceIconButtonStyle())
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if model.isSearchingV1Catalogue, model.activeProducts.isEmpty {
            DastakLoadingOverlay(title: "Searching Dastak")
        } else {
            ScrollView {
                LazyVStack(spacing: MarketplaceSpacing.small) {
                    if model.activeProducts.isEmpty {
                        ContentUnavailableView.search(text: trimmedSearchText)
                            .padding(.vertical, MarketplaceSpacing.large)
                    } else {
                        ForEach(model.activeProducts) { product in
                            searchResultRow(product)
                        }
                    }
                }
                .padding(MarketplaceSpacing.small)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 520)
            .marketplaceGlass(cornerRadius: MarketplaceMetrics.sheetCornerRadius)
        }
    }

    private func searchResultRow(_ product: DastakV1CatalogueSKU) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            DastakProductArtwork(imageKey: product.imageKey, fallbackSymbol: artworkSymbol(for: product))
                .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 3) {
                if let brand = product.brand?.name {
                    Text(brand.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .lineLimit(1)
                }
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(DastakFormatting.money(product.price))
                    .font(.subheadline.bold().monospacedDigit())
            }

            Spacer(minLength: 4)

            Button {
                Task { await model.toggleWishlist(kind: .retailSKU, itemID: product.id) }
            } label: {
                Image(systemName: model.isWishlisted(kind: .retailSKU, itemID: product.id) ? "heart.fill" : "heart")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(MarketplaceColors.dastakAccent.color)
            .disabled(model.wishlistUpdatingIDs.contains(product.id))
            .accessibilityLabel(model.isWishlisted(kind: .retailSKU, itemID: product.id) ? "Remove \(product.name) from Wishlist" : "Save \(product.name) to Wishlist")

            Button { model.addToCart(product) } label: {
                Image(systemName: "plus")
                    .font(.subheadline.bold())
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
        .padding(MarketplaceSpacing.small)
        .marketplaceFlatSurface()
    }

    private var trimmedSearchText: String {
        model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentSearch() {
        isSearchPresented = true
        Task { @MainActor in
            await Task.yield()
            isSearchFieldFocused = true
        }
    }

    private func closeSearch() {
        isSearchFieldFocused = false
        model.searchText = ""
        isSearchPresented = false
    }

    private func artworkSymbol(for product: DastakV1CatalogueSKU) -> String {
        switch product.logisticsAttributes.temperatureClass {
        case "CHILLED", "FROZEN": "snowflake"
        default: product.logisticsAttributes.fragile == true ? "shippingbox" : "basket"
        }
    }

    private func categorySymbol(_ slug: String) -> String {
        if slug.contains("health") || slug.contains("care") { return "cross.case" }
        if slug.contains("food") || slug.contains("grocery") { return "basket" }
        if slug.contains("home") { return "house" }
        return "square.grid.2x2"
    }
}

private struct DastakCategoryTile: View {
    let category: DastakV1CatalogueCategory

    var body: some View {
        VStack(spacing: 7) {
            DastakProductArtwork(
                imageKey: category.imageKey ?? category.previewImageKeys?.first,
                fallbackSymbol: "square.grid.2x2.fill"
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            Text(category.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 31, alignment: .top)
        }
        .contentShape(Rectangle())
    }
}

private struct DastakSubcategoryTile: View {
    let subcategory: DastakV1CatalogueSubcategory
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            DastakProductArtwork(
                imageKey: subcategory.imageKey ?? subcategory.previewImageKeys?.first,
                fallbackSymbol: "shippingbox.fill"
            )
            .frame(width: 64, height: 58)
            Text(subcategory.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 68)
                .frame(minHeight: 30, alignment: .top)
        }
        .padding(4)
        .background(selected ? MarketplaceColors.dastakAccentSoft.color : .clear, in: RoundedRectangle(cornerRadius: 15))
    }
}

struct DastakRestaurantMenuView: View {
    @ObservedObject var model: DastakCustomerModel
    let restaurant: DastakV1RestaurantMenu
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Exact restaurant confirmation")
                                .font(.subheadline.weight(.semibold))
                            Text("Dastak never silently reroutes your food. Confirm only after the whole basket is secured, then pay the rider at delivery.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    }
                    .padding(MarketplaceSpacing.compact)
                    .marketplaceFlatSurface()

                    ForEach(restaurant.categories) { category in
                        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                            Text(category.name).font(MarketplaceTypography.sectionTitle)
                            if let description = category.description {
                                Text(description).font(.footnote).foregroundStyle(.secondary)
                            }
                            ForEach(category.items) { item in
                                DastakRestaurantItemCard(
                                    item: item,
                                    isWishlisted: model.isWishlisted(kind: .menuItem, itemID: item.id),
                                    isUpdatingWishlist: model.wishlistUpdatingIDs.contains(item.id),
                                    add: { item, optionIDs in
                                        model.addFoodToCart(
                                            restaurant: restaurant,
                                            item: item,
                                            optionIDs: optionIDs
                                        )
                                    },
                                    toggleWishlist: {
                                        Task { await model.toggleWishlist(kind: .menuItem, itemID: item.id) }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(MarketplaceSpacing.medium)
            }
            .navigationTitle(restaurant.restaurant.name)
            .dastakInlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .marketplacePage()
    }
}

private struct DastakRestaurantItemCard: View {
    let item: DastakV1RestaurantMenuItem
    let isWishlisted: Bool
    let isUpdatingWishlist: Bool
    let add: (DastakV1RestaurantMenuItem, [UUID]) -> Void
    let toggleWishlist: () -> Void
    @State private var selections: [UUID: Set<UUID>]

    init(
        item: DastakV1RestaurantMenuItem,
        isWishlisted: Bool,
        isUpdatingWishlist: Bool,
        add: @escaping (DastakV1RestaurantMenuItem, [UUID]) -> Void,
        toggleWishlist: @escaping () -> Void
    ) {
        self.item = item
        self.isWishlisted = isWishlisted
        self.isUpdatingWishlist = isUpdatingWishlist
        self.add = add
        self.toggleWishlist = toggleWishlist
        _selections = State(initialValue: Dictionary(uniqueKeysWithValues: item.optionGroups.map {
            ($0.id, Set($0.options.prefix($0.minimumSelections).map(\.id)))
        }))
    }

    private var selectedIDs: [UUID] {
        item.optionGroups.flatMap { Array(selections[$0.id] ?? []).sorted { $0.uuidString < $1.uuidString } }
    }

    private var valid: Bool {
        item.optionGroups.allSatisfy {
            let count = selections[$0.id]?.count ?? 0
            return count >= $0.minimumSelections && count <= $0.maximumSelections
        }
    }

    private var total: Money {
        let options = item.optionGroups.flatMap(\.options).filter { selectedIDs.contains($0.id) }
        return Money(paise: item.basePricePaise + options.reduce(0) { $0 + $1.priceDeltaPaise })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.small) {
                Text(item.name).font(.headline)
                Spacer(minLength: 8)
                Button(action: toggleWishlist) {
                    Image(systemName: isWishlisted ? "heart.fill" : "heart")
                        .font(.headline)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingWishlist)
                .accessibilityLabel(isWishlisted ? "Remove \(item.name) from Wishlist" : "Save \(item.name) to Wishlist")
            }
            if let description = item.description {
                Text(description).font(.footnote).foregroundStyle(.secondary)
            }
            Text(DastakFormatting.money(item.basePrice))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            ForEach(item.optionGroups) { group in
                VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                    HStack {
                        Text(group.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(group.minimumSelections > 0 ? "Required" : "Optional")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.options) { option in
                        Button { toggle(option.id, in: group) } label: {
                            HStack {
                                Image(systemName: (selections[group.id] ?? []).contains(option.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                Text(option.name).foregroundStyle(.primary)
                                Spacer()
                                Text(option.priceDeltaPaise == 0 ? "Included" : "+\(DastakFormatting.money(Money(paise: option.priceDeltaPaise)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(MarketplaceSpacing.small)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button { add(item, selectedIDs) } label: {
                HStack { Text("Add to basket"); Spacer(); Text(DastakFormatting.money(total)) }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(!valid)
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }

    private func toggle(_ optionID: UUID, in group: DastakV1RestaurantMenuOptionGroup) {
        var selected = selections[group.id] ?? []
        if selected.contains(optionID) { selected.remove(optionID) }
        else if group.selectionType == "SINGLE" { selected = [optionID] }
        else if selected.count < group.maximumSelections { selected.insert(optionID) }
        selections[group.id] = selected
    }
}

struct DastakV1ProductTile: View {
    let product: DastakV1CatalogueSKU
    let isWishlisted: Bool
    let isUpdatingWishlist: Bool
    let add: () -> Void
    let toggleWishlist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DastakProductArtwork(imageKey: product.imageKey, fallbackSymbol: artworkSymbol)
                .aspectRatio(1.04, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    Button(action: toggleWishlist) {
                        Image(systemName: isWishlisted ? "heart.fill" : "heart")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingWishlist)
                    .padding(6)
                    .accessibilityLabel(isWishlisted ? "Remove \(product.name) from Wishlist" : "Save \(product.name) to Wishlist")
                }

            if let brand = product.brand?.name {
                Text(brand.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .lineLimit(1)
            }
            Text(product.name)
                .font(.subheadline.bold())
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            Text([product.variant, product.packSize].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DastakFormatting.money(product.price))
                        .font(.subheadline.bold().monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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
                            .frame(width: 36, height: 36)
                        .foregroundStyle(.white)
                        .background(
                            MarketplaceColors.primaryAction.color,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(product.name)")
            }
        }
        .padding(8)
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
                openCart: {},
                sendParcel: {}
            )
        }
        .previewDisplayName("Customer V1 home")
    }
}
#endif
