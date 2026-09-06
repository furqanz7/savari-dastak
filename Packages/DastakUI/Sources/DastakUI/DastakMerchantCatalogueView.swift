import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct DastakMerchantStoreAndCatalogueView: View {
    private enum LegacySection: String, CaseIterable, Identifiable {
        case store = "Store"
        case catalogue = "Catalogue"
        var id: String { rawValue }
    }

    @ObservedObject var model: DastakMerchantModel
    @State private var legacySection = LegacySection.store

    var body: some View {
        if model.isLoading {
            DastakLoadingOverlay(title: "Loading store")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.canonicalCatalogue != nil {
            DastakMerchantCanonicalCatalogueView(model: model)
        } else {
            VStack(spacing: 0) {
                Picker("Store workspace", selection: $legacySection) {
                    ForEach(LegacySection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.top, MarketplaceSpacing.compact)

                if legacySection == .store {
                    DastakMerchantStoreView(model: model)
                } else {
                    DastakMerchantCatalogueView(model: model)
                }
            }
        }
    }
}

private struct DastakMerchantCanonicalCatalogueView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var query = ""
    @State private var selectedOnly = false
    @State private var categoryTypeID: UUID?
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @State private var selectedProduct: DastakV1MerchantCatalogueSnapshot.SKU?

    private let columns = [
        GridItem(.flexible(), spacing: MarketplaceSpacing.compact),
        GridItem(.flexible(), spacing: MarketplaceSpacing.compact),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = model.canonicalCatalogue, categoryTypeID != nil {
                    categoryBrowser(categoryID: categoryID, snapshot: snapshot)
                } else if let snapshot = model.canonicalCatalogue {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                            storeHeader(snapshot)
                            operatingControls(snapshot)
                            libraryNote
                            catalogueTools(snapshot)
                            productGrid(snapshot)
                        }
                        .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                        .padding(.horizontal, MarketplaceSpacing.medium)
                        .padding(.bottom, 148)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { await model.refreshCanonicalCatalogue() }
                }
            }
            .navigationTitle("Store & Catalogue")
            .dastakInlineNavigationTitle()
            .searchable(text: $query, prompt: "Products, brands, packs or categories")
            .safeAreaInset(edge: .bottom) {
                if model.hasPendingCanonicalSelections {
                    pendingSelectionBar
                }
            }
            .task(id: priorityArtworkKeys) {
                await DastakProductArtwork.prefetch(imageKeys: priorityArtworkKeys)
            }
            .dastakProductOverlay(item: $selectedProduct) { sku in
                DastakMerchantProductDetailView(model: model, initial: sku, close: { if !model.isBusy { selectedProduct = nil } })
            }
        }
    }

    private func categoryBrowser(
        categoryID: UUID?,
        snapshot: DastakV1MerchantCatalogueSnapshot
    ) -> some View {
        let products = visibleProducts(snapshot)
        let categoryName = snapshot.categories.first { $0.id == categoryID }?.name ?? "Products"
        let departmentName = snapshot.categoryTypes.first { $0.id == categoryTypeID }?.name ?? categoryName
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Picker("Catalogue scope", selection: $selectedOnly) {
                    Text("All products").tag(false)
                    Text("My storefront").tag(true)
                }
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline, spacing: MarketplaceSpacing.small) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DASTAK CATALOGUE")
                            .font(.caption2.bold())
                            .tracking(1.1)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text(departmentName)
                            .font(.title3.bold())
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text("\(products.count) products")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("All categories") {
                        categoryTypeID = nil
                        self.categoryID = nil
                        subcategoryID = nil
                        query = ""
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                Picker("Type", selection: $subcategoryID) {
                    Text("All types").tag(UUID?.none)
                    ForEach(snapshot.subcategories.filter { $0.categoryID == categoryID }) { item in
                        Text(item.name).tag(UUID?.some(item.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(MarketplaceColors.dastakAccent.color)
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.vertical, MarketplaceSpacing.small)

            Divider()

            HStack(alignment: .top, spacing: 8) {
                ScrollView(.vertical) {
                    merchantSubcategoryRail(snapshot: snapshot)
                        .padding(.vertical, MarketplaceSpacing.small)
                        .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .frame(width: 76)

                ScrollView(.vertical) {
                    Group {
                        if products.isEmpty {
                            DastakEmptyState(
                                symbol: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? DastakCatalogueSymbol.symbol(for: categoryName)
                                    : "magnifyingglass",
                                title: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Approved products coming soon"
                                    : "No matching products",
                                message: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "This category is in the master catalogue. Selectable SKUs will appear after catalogue and safety checks are complete."
                                    : "Try a different product, brand, pack or category."
                            )
                            .frame(minHeight: 300)
                        } else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: MarketplaceSpacing.compact) {
                                ForEach(products) { sku in
                                    canonicalProductCard(sku)
                                }
                            }
                        }
                    }
                    .padding(.vertical, MarketplaceSpacing.small)
                    .padding(.bottom, 148)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.refreshCanonicalCatalogue() }
                .frame(maxWidth: .infinity)
                .id(categoryID)
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private var pendingSelectionBar: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.pendingCanonicalSelections.count) unsaved \(model.pendingCanonicalSelections.count == 1 ? "change" : "changes")")
                    .font(.subheadline.bold())
                Text("Keep selecting, then save once")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Discard") { model.discardCanonicalSelections() }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
            Button(model.busyIdentity == "canonical-catalogue-save" ? "Saving…" : "Save") {
                Task { await model.saveCanonicalSelections() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MarketplaceColors.dastakAccent.color)
            .disabled(model.isBusy)
        }
        .padding(.horizontal, MarketplaceSpacing.medium)
        .frame(minHeight: 72)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func storeHeader(_ snapshot: DastakV1MerchantCatalogueSnapshot) -> some View {
        HStack(alignment: .center, spacing: MarketplaceSpacing.compact) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR STOREFRONT")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(snapshot.branch.branchName)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(snapshot.branch.organizationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: MarketplaceSpacing.small)
            VStack(alignment: .trailing, spacing: 6) {
                DastakStatusPill(
                    text: snapshot.branch.operationalState.isOpen ? "Open" : "Closed",
                    emphasis: snapshot.branch.operationalState.isOpen
                )
                DastakStatusPill(
                    text: snapshot.branch.operationalState.acceptingOrders ? "Accepting orders" : "Orders paused",
                    emphasis: snapshot.branch.operationalState.acceptingOrders
                )
            }
        }
        .padding(.top, MarketplaceSpacing.compact)
    }

    private func operatingControls(_ snapshot: DastakV1MerchantCatalogueSnapshot) -> some View {
        let state = snapshot.branch.operationalState
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MarketplaceSpacing.small) {
                merchantControl(
                    symbol: "storefront",
                    title: state.isOpen ? "Store open" : "Store closed",
                    detail: "Branch availability",
                    action: state.isOpen ? "Close" : "Open"
                ) {
                    Task { await model.setCanonicalBranch(isOpen: !state.isOpen, acceptingOrders: false) }
                }
                merchantControl(
                    symbol: "shippingbox",
                    title: "\(snapshot.branch.capacity.available) slots",
                    detail: state.acceptingOrders ? "Taking new orders" : "New orders paused",
                    action: state.acceptingOrders ? "Pause" : "Accept"
                ) {
                    Task { await model.setCanonicalBranch(isOpen: true, acceptingOrders: !state.acceptingOrders) }
                }
            }
        }
    }

    private func merchantControl(
        symbol: String,
        title: String,
        detail: String,
        action: String,
        perform: @escaping () -> Void
    ) -> some View {
        HStack(spacing: MarketplaceSpacing.small) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 34, height: 34)
                .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            Button(action, action: perform)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(model.isBusy)
        }
        .frame(width: 250)
        .frame(minHeight: 62, alignment: .leading)
        .padding(MarketplaceSpacing.small)
        .marketplaceFlatSurface()
    }

    private var libraryNote: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Dastak product library").font(.subheadline.bold())
                Text("Select freely, then save all storefront changes once.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }

    private func catalogueTools(_ snapshot: DastakV1MerchantCatalogueSnapshot) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Picker("Catalogue scope", selection: $selectedOnly) {
                Text("All products").tag(false)
                Text("My storefront").tag(true)
            }
            .pickerStyle(.segmented)

            if let selectedType = snapshot.categoryTypes.first(where: { $0.id == categoryTypeID }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DEPARTMENT").font(.caption2.bold()).tracking(1)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text(selectedType.name).font(.headline)
                    }
                    Spacer()
                    Button("All departments") {
                        categoryTypeID = nil; categoryID = nil; subcategoryID = nil
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if categoryID == nil, categoryTypeID == nil {
                departmentDirectory(snapshot)
            }
        }
    }

    private func departmentDirectory(_ snapshot: DastakV1MerchantCatalogueSnapshot) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
            ForEach(merchantNavigationGroups(snapshot), id: \.key) { group in
                VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                    Text(group.name).font(.headline)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        alignment: .leading,
                        spacing: MarketplaceSpacing.compact
                    ) {
                        ForEach(group.types) { type in
                            Button {
                                categoryTypeID = type.id
                                let children = snapshot.categories.filter { $0.categoryTypeID == type.id }
                                categoryID = (children.first { $0.status == "ACTIVE" } ?? children.first)?.id
                                subcategoryID = nil
                            } label: {
                                VStack(spacing: 7) {
                                    DastakCategoryArtwork(
                                        imageKey: type.imageKey,
                                        previewImageKeys: type.previewImageKeys,
                                        fallbackSymbol: DastakCatalogueSymbol.symbol(for: type.slug)
                                    )
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    Text(type.name)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
                                    if type.status != nil, type.status != "ACTIVE" {
                                        Text("COMING SOON")
                                            .font(.system(size: 8, weight: .bold))
                                            .tracking(0.5)
                                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func productGrid(_ snapshot: DastakV1MerchantCatalogueSnapshot) -> some View {
        let products = visibleProducts(snapshot)
        return Group {
            if categoryID == nil && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedOnly {
                EmptyView()
            } else if products.isEmpty {
                DastakEmptyState(
                    symbol: "magnifyingglass",
                    title: "No matching products",
                    message: "Try a different product, brand, pack or category."
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: MarketplaceSpacing.compact) {
                    ForEach(products) { sku in
                        canonicalProductCard(sku)
                    }
                }
            }
        }
    }

    private func merchantSubcategoryRail(
        snapshot: DastakV1MerchantCatalogueSnapshot
    ) -> some View {
        LazyVStack(spacing: MarketplaceSpacing.compact) {
            ForEach(snapshot.categories.filter { $0.categoryTypeID == categoryTypeID }) { item in
                Button { categoryID = item.id; subcategoryID = nil } label: {
                    merchantCollectionTile(
                        title: item.name,
                        imageKey: item.imageKey ?? item.previewImageKeys?.first ?? categoryArtworkKey(item.id, in: snapshot),
                        selected: categoryID == item.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(categoryID == item.id ? .isSelected : [])
            }
        }
        .frame(width: 72)
    }

    private func merchantCollectionTile(title: String, imageKey: String?, selected: Bool) -> some View {
        VStack(spacing: 6) {
            DastakProductArtwork(
                imageKey: imageKey,
                fallbackSymbol: title == "All" ? "sparkles" : DastakCatalogueSymbol.symbol(for: title)
            )
                .frame(width: 64, height: 58)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 68)
                .frame(minHeight: 30, alignment: .top)
        }
        .padding(4)
        .background(selected ? MarketplaceColors.dastakAccentSoft.color : .clear, in: RoundedRectangle(cornerRadius: 15))
    }

    private func canonicalProductCard(
        _ sku: DastakV1MerchantCatalogueSnapshot.SKU
    ) -> some View {
        let selected = model.canonicalSelection(for: sku)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                DastakProductArtwork(imageKey: sku.imageKey, fallbackSymbol: "shippingbox")
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.04, contentMode: .fit)
                    .onTapGesture { selectedProduct = sku }
                    .accessibilityHidden(false)
                    .accessibilityLabel("View \(sku.name) details and stock")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { selectedProduct = sku }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MarketplaceColors.success.color)
                        .padding(8)
                }
            }
            if let brand = sku.brandName {
                Text(brand.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            Text(sku.name)
                .font(.subheadline.bold())
                .onTapGesture { selectedProduct = sku }
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            Text([sku.variant, sku.packSize].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 5) {
                Text(DastakFormatting.money(Money(paise: sku.sellingPricePaise)))
                    .font(.subheadline.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                Button {
                    if sku.stockQuantity == 0 && !selected { selectedProduct = sku }
                    else { model.stageCanonicalSelection(sku) }
                } label: {
                    Image(systemName: selected ? "minus" : "plus")
                        .font(.subheadline.bold())
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 11))
                .tint(MarketplaceColors.dastakAccent.color)
                .disabled(model.busyIdentity == "canonical-catalogue-save" || sku.catalogueStatus != "ACTIVE")
                .accessibilityLabel(selected ? "Remove \(sku.name)" : "Select \(sku.name)")
            }
        }
        .padding(8)
        .marketplaceFlatSurface()
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: MarketplaceMetrics.compactCornerRadius, style: .continuous)
                    .stroke(MarketplaceColors.success.color.opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    private func visibleProducts(_ snapshot: DastakV1MerchantCatalogueSnapshot) -> [DastakV1MerchantCatalogueSnapshot.SKU] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let categories = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0.name) })
        let subcategories = Dictionary(uniqueKeysWithValues: snapshot.subcategories.map { ($0.id, $0.name) })
        return snapshot.skus.filter { sku in
            guard categoryTypeID == nil || sku.categoryTypeID == categoryTypeID,
                  categoryID == nil || sku.categoryID == categoryID,
                  subcategoryID == nil || sku.subcategoryID == subcategoryID,
                  !selectedOnly || model.canonicalSelection(for: sku)
            else { return false }
            guard !normalized.isEmpty else { return true }
            return [sku.name, sku.brandName, sku.variant, sku.packSize, categories[sku.categoryID], subcategories[sku.subcategoryID]]
                .compactMap { $0 }
                .joined(separator: " ")
                .appending(" " + sku.searchTerms.joined(separator: " "))
                .lowercased()
                .contains(normalized)
        }
    }

    private func categoryArtworkKey(_ categoryID: UUID, in snapshot: DastakV1MerchantCatalogueSnapshot) -> String? {
        snapshot.skus.first { $0.categoryID == categoryID && $0.imageKey != nil }?.imageKey
    }

    private var priorityArtworkKeys: [String] {
        guard let snapshot = model.canonicalCatalogue else { return [] }
        var keys: [String] = []
        if let categoryID {
            if let key = snapshot.categories.first(where: { $0.id == categoryID })
                .flatMap({ $0.imageKey ?? categoryArtworkKey($0.id, in: snapshot) }) {
                keys.append(key)
            }
            keys.append(contentsOf: snapshot.categories
                .filter { $0.categoryTypeID == categoryTypeID }
                .compactMap { $0.imageKey ?? $0.previewImageKeys?.first ?? categoryArtworkKey($0.id, in: snapshot) })
            keys.append(contentsOf: visibleProducts(snapshot).prefix(16).compactMap(\.imageKey))
        } else {
            let destinations: [(String?, [String]?)]
            if let categoryTypeID {
                destinations = snapshot.categories
                    .filter { $0.categoryTypeID == categoryTypeID }
                    .map { ($0.imageKey ?? categoryArtworkKey($0.id, in: snapshot), $0.previewImageKeys) }
            } else {
                destinations = snapshot.categoryTypes.map { ($0.imageKey, $0.previewImageKeys) }
            }
            for destination in destinations {
                keys.append(contentsOf: ([destination.0].compactMap { $0 }
                    + (destination.1 ?? [])).prefix(2))
            }
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }.prefix(32).map { $0 }
    }

    private func merchantNavigationGroups(
        _ snapshot: DastakV1MerchantCatalogueSnapshot
    ) -> [MerchantCatalogueNavigationGroup] {
        let grouped = Dictionary(grouping: snapshot.categoryTypes) {
            $0.navigationSection?.key ?? "more"
        }
        return grouped.map { key, types in
            let metadata = types.compactMap(\.navigationSection).first
            return MerchantCatalogueNavigationGroup(
                key: key,
                name: metadata?.name ?? "More to explore",
                sortOrder: metadata?.sortOrder ?? 999,
                types: types.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            )
        }
        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}

private struct MerchantCatalogueNavigationGroup {
    let key: String
    let name: String
    let sortOrder: Int
    let types: [DastakV1MerchantCatalogueSnapshot.CategoryType]
}

struct DastakMerchantStoreView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var showsEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        DastakWordmark(size: 30)
                        Text("Your customer-facing storefront")
                            .font(MarketplaceTypography.supporting)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, MarketplaceSpacing.compact)

                    if model.isLoading {
                        DastakLoadingOverlay(title: "Loading store")
                            .frame(maxWidth: .infinity)
                            .padding(.top, MarketplaceSpacing.xxLarge)
                    } else if let store = model.store {
                        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                            Image(systemName: "storefront")
                                .font(.title3)
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                .frame(width: 44, height: 44)
                                .background(MarketplaceColors.dastakAccentSoft.color)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: MarketplaceMetrics.compactCornerRadius,
                                        style: .continuous
                                    )
                                )

                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.name)
                                    .font(.headline)
                                Text(store.address)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    DastakStatusPill(
                                        text: store.isPublished ? "Published" : "Not published",
                                        emphasis: store.isPublished
                                    )
                                    DastakStatusPill(
                                        text: store.acceptingOrders ? "Accepting orders" : "Closed"
                                    )
                                }
                            }
                        }
                        .padding(MarketplaceSpacing.medium)
                        .marketplaceFlatSurface()

                        Button("Edit store") {
                            showsEditor = true
                        }
                        .buttonStyle(MarketplacePrimaryButtonStyle())
                    } else {
                        DastakEmptyState(
                            symbol: "storefront",
                            title: "Set up your storefront",
                            message: "Add the store customers will discover and order from.",
                            actionTitle: "Set up store",
                            action: { showsEditor = true }
                        )
                        .frame(minHeight: 280)
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refreshAll() }
            .navigationTitle("Store")
            .dastakInlineNavigationTitle()
            .toolbar {
                if model.store != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showsEditor = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(MarketplaceIconButtonStyle())
                        .accessibilityLabel("Edit store")
                    }
                }
            }
        }
        .sheet(isPresented: $showsEditor) {
            DastakStoreEditor(store: model.store, model: model)
        }
    }
}

struct DastakMerchantCatalogueView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var editor: DastakMerchantEditor?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    header

                    if model.isLoading {
                        DastakLoadingOverlay(title: "Loading catalogue")
                            .frame(maxWidth: .infinity)
                            .padding(.top, MarketplaceSpacing.xxLarge)
                    } else {
                        if let notice = model.notice {
                            Label(notice, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(MarketplaceColors.success.color)
                        }
                        if model.store == nil {
                            DastakEmptyState(
                                symbol: "storefront",
                                title: "Store setup required",
                                message: "Set up your store before adding categories and products."
                            )
                            .frame(minHeight: 280)
                        } else {
                            categorySection
                            productSection
                        }
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refreshAll() }
            .navigationTitle("Catalogue")
            .dastakInlineNavigationTitle()
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case let .category(category):
                DastakCategoryEditor(
                    category: category,
                    nextDisplayOrder: model.categories.count,
                    model: model
                )
            case let .product(draft):
                DastakProductEditor(
                    draft: draft,
                    categories: model.categories.filter(\.isActive),
                    model: model
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            DastakWordmark(size: 30)
            Text("Categories and products")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
        }
        .padding(.top, MarketplaceSpacing.compact)
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            sectionHeader(
                title: "Categories",
                actionTitle: "Add",
                actionSymbol: "plus"
            ) {
                editor = .category(nil)
            }

            if model.categories.isEmpty {
                Text("Add a category before adding products.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, MarketplaceSpacing.medium)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.categories, id: \.categoryID) { category in
                        Button {
                            editor = .category(category)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(category.name)
                                        .font(.headline)
                                    Text(category.isActive ? "Visible" : "Hidden")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(
                                    model.products
                                        .filter { $0.categoryID == category.categoryID }
                                        .count
                                        .formatted()
                                )
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, MarketplaceSpacing.compact)
                        }
                        .buttonStyle(.plain)
                        if category.categoryID != model.categories.last?.categoryID {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, MarketplaceSpacing.medium)
                .marketplaceFlatSurface()
            }
        }
    }

    private var productSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            sectionHeader(
                title: "Products",
                actionTitle: "Add",
                actionSymbol: "plus"
            ) {
                guard let categoryID = model.categories.first(where: \.isActive)?.categoryID else {
                    model.errorMessage = "Add an active category first."
                    return
                }
                editor = .product(DastakMerchantProductDraft(categoryID: categoryID))
            }

            if model.products.isEmpty {
                DastakEmptyState(
                    symbol: "shippingbox",
                    title: "No products yet",
                    message: "Add products with prices and stock availability."
                )
                .frame(minHeight: 240)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.products, id: \.productID) { product in
                        Button {
                            editor = .product(DastakMerchantProductDraft(product: product))
                        } label: {
                            HStack(spacing: MarketplaceSpacing.compact) {
                                DastakProductArtwork(kind: product.catalogueKind)
                                    .frame(width: 54, height: 54)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(product.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(product.unitLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if product.restrictedApprovalState != .notApplicable {
                                        Text(approvalLabel(product.restrictedApprovalState))
                                            .font(.caption.bold())
                                            .foregroundStyle(MarketplaceColors.warning.color)
                                    }
                                }

                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(DastakFormatting.money(product.price))
                                        .font(.headline.monospacedDigit())
                                    Text(product.availability == .inStock ? "In stock" : "Out of stock")
                                        .font(.caption)
                                        .foregroundStyle(
                                            product.availability == .inStock
                                                ? MarketplaceColors.success.color
                                                : Color.secondary
                                        )
                                }
                            }
                            .padding(.vertical, MarketplaceSpacing.compact)
                            .opacity(product.isActive ? 1 : 0.5)
                        }
                        .buttonStyle(.plain)
                        if product.productID != model.products.last?.productID {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, MarketplaceSpacing.medium)
                .marketplaceFlatSurface()
            }
        }
    }

    private func sectionHeader(
        title: String,
        actionTitle: String,
        actionSymbol: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(MarketplaceTypography.sectionTitle)
            Spacer()
            Button(action: action) {
                Label(actionTitle, systemImage: actionSymbol)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func approvalLabel(_ state: RestrictedApprovalState) -> String {
        switch state {
        case .notApplicable: ""
        case .pending: "Approval pending"
        case .approved: "Approved"
        case .rejected: "Approval rejected"
        case .suspended: "Approval suspended"
        }
    }
}

private enum DastakMerchantEditor: Identifiable {
    case category(CatalogueCategory?)
    case product(DastakMerchantProductDraft)

    var id: String {
        switch self {
        case let .category(category): "category:\(category?.categoryID.uuidString ?? "new")"
        case let .product(draft): "product:\(draft.id.uuidString)"
        }
    }
}

private struct DastakStoreEditor: View {
    @ObservedObject var model: DastakMerchantModel
    @StateObject private var locationManager = DastakLocationManager()
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var isPublished: Bool
    @State private var acceptingOrders: Bool

    init(store: CatalogueStore?, model: DastakMerchantModel) {
        self.model = model
        _name = State(initialValue: store?.name ?? "")
        _address = State(initialValue: store?.address ?? "")
        _latitude = State(initialValue: store.map { String($0.location.latitude) } ?? "")
        _longitude = State(initialValue: store.map { String($0.location.longitude) } ?? "")
        _isPublished = State(initialValue: store?.isPublished ?? false)
        _acceptingOrders = State(initialValue: store?.acceptingOrders ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Store details") {
                    TextField("Store name", text: $name)
                        .textContentType(.organizationName)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                        .textContentType(.fullStreetAddress)
                }

                Section("Location") {
                    TextField("Latitude", text: $latitude)
                    TextField("Longitude", text: $longitude)
                    Button {
                        locationManager.requestLocation()
                    } label: {
                        Label("Use current location", systemImage: "location")
                    }
                    if let location = locationManager.location {
                        Button("Use \(location.address)") {
                            latitude = String(location.point.latitude)
                            longitude = String(location.point.longitude)
                            if address.isEmpty {
                                address = location.address
                            }
                        }
                    }
                }

                Section("Availability") {
                    Toggle("Published", isOn: $isPublished)
                        .onChange(of: isPublished) { _, value in
                            if !value { acceptingOrders = false }
                        }
                    Toggle("Accepting orders", isOn: $acceptingOrders)
                        .disabled(!isPublished)
                }
            }
            .navigationTitle(model.store == nil ? "Set up store" : "Edit store")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let point else { return }
                            if await model.saveStore(
                                name: name,
                                address: address,
                                location: point,
                                isPublished: isPublished,
                                acceptingOrders: acceptingOrders
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isValid || model.isBusy)
                }
            }
        }
    }

    private var point: GeoPoint? {
        guard let latitude = Double(latitude),
              let longitude = Double(longitude),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && point != nil
    }
}

private struct DastakCategoryEditor: View {
    let category: CatalogueCategory?
    let nextDisplayOrder: Int
    @ObservedObject var model: DastakMerchantModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isActive: Bool

    init(
        category: CatalogueCategory?,
        nextDisplayOrder: Int,
        model: DastakMerchantModel
    ) {
        self.category = category
        self.nextDisplayOrder = nextDisplayOrder
        self.model = model
        _name = State(initialValue: category?.name ?? "")
        _isActive = State(initialValue: category?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Category name", text: $name)
                Toggle("Visible to customers", isOn: $isActive)
            }
            .navigationTitle(category == nil ? "Add category" : "Edit category")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.saveCategory(
                                categoryID: category?.categoryID,
                                name: name,
                                displayOrder: category?.displayOrder ?? nextDisplayOrder,
                                isActive: isActive
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct DastakProductEditor: View {
    let categories: [CatalogueCategory]
    @ObservedObject var model: DastakMerchantModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DastakMerchantProductDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var imageContentType: String?
    @State private var imageName: String?
    @State private var step = DastakProductEditorStep.details

    init(
        draft: DastakMerchantProductDraft,
        categories: [CatalogueCategory],
        model: DastakMerchantModel
    ) {
        self.categories = categories
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        let photoLabel = imageName ?? "Choose photo"

        NavigationStack {
            Form {
                if step == .details {
                    Section {
                        TextField("Name", text: $draft.name)
                        Picker("Category", selection: $draft.categoryID) {
                            ForEach(categories, id: \.categoryID) { category in
                                Text(category.name).tag(category.categoryID)
                            }
                        }
                        TextField("Unit, for example 1 kg", text: $draft.unitLabel)
                        TextField("Price in rupees", text: $draft.priceRupees)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        TextField("Description", text: $draft.description, axis: .vertical)
                            .lineLimit(2...5)
                    } header: {
                        Text("Product details")
                    } footer: {
                        Text("Step 1 of 2")
                    }
                } else {
                    Section("Availability") {
                        Picker("Stock", selection: $draft.availability) {
                            Text("In stock").tag(CatalogueAvailability.inStock)
                            Text("Out of stock").tag(CatalogueAvailability.outOfStock)
                        }
                        Picker("Type", selection: $draft.catalogueKind) {
                            Text("General").tag(CatalogueKind.general)
                            Text("OTC medicine").tag(CatalogueKind.otcMedicine)
                            Text("Prescription medicine").tag(CatalogueKind.prescriptionMedicine)
                            Text("Paan Corner").tag(CatalogueKind.paanCorner)
                        }
                        Toggle("Visible in catalogue", isOn: $draft.isActive)
                    }

                    Section {
                        PhotosPicker(
                            selection: $photoItem,
                            matching: .images
                        ) {
                            Label(photoLabel, systemImage: "photo.badge.plus")
                        }
                        Text("JPG, PNG, or WebP, up to 5 MB.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Product image")
                    } footer: {
                        Text("Step 2 of 2")
                    }
                }
            }
            .navigationTitle(draft.productID == nil ? "Add product" : "Edit product")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .details ? "Cancel" : "Back") {
                        if step == .details {
                            dismiss()
                        } else {
                            step = .details
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == .details {
                        Button("Continue") {
                            step = .availability
                        }
                        .disabled(!detailsAreValid)
                    } else {
                        Button("Save") {
                            Task {
                                if await model.saveProduct(
                                    draft,
                                    imageData: imageData,
                                    imageContentType: imageContentType
                                ) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(model.isBusy)
                    }
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    private var detailsAreValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.unitLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? DastakMerchantPriceParser.paise(from: draft.priceRupees)) != nil
            && categories.contains(where: { $0.categoryID == draft.categoryID })
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  data.count <= 5 * 1_024 * 1_024
            else {
                throw DastakProductPhotoError.invalid
            }
            let contentType = item.supportedContentTypes.first {
                $0.conforms(to: .jpeg) || $0.conforms(to: .png) || $0.identifier == "org.webmproject.webp"
            } ?? .jpeg
            imageData = data
            imageContentType = contentType.preferredMIMEType ?? "image/jpeg"
            imageName = "New product photo"
        } catch {
            model.errorMessage = "Choose a JPG, PNG, or WebP image up to 5 MB."
            photoItem = nil
            imageData = nil
            imageContentType = nil
            imageName = nil
        }
    }
}

private enum DastakProductPhotoError: Error {
    case invalid
}

private enum DastakProductEditorStep {
    case details
    case availability
}
