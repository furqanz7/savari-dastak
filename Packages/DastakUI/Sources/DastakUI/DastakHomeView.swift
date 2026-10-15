import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

private enum DastakHomeMode: String, CaseIterable, Identifiable {
    case food = "Food"
    case grocery = "Grocery"
    case parcel = "Parcel"
    case print = "Print"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .grocery: "bag"
        case .parcel: "shippingbox"
        case .print: "printer"
        }
    }
    var isComingSoon: Bool { self == .parcel || self == .print }
}

struct DastakHomeView: View {
    @ObservedObject var model: DastakCustomerModel
    let chooseLocation: () -> Void
    let openCart: () -> Void
    let sendParcel: () -> Void
    var shellService: DastakCustomerService? = nil
    var homeRevision = 0
    var startsWithSearch = false
    var directoryKey: String? = nil
    var directoryRevision = 0
    var isActive = true
    var onBrowseDestinationChanged: (String?) -> Void = { _ in }
    @State private var selectedRestaurant: DastakV1RestaurantMenu?
    @State private var cartAfterDetails: DastakBasketService?
    @Environment(\.dastakOpenCart) private var requestCart
    @Environment(\.marketplaceHapticScope) private var haptics
    @State private var selectedProduct: CustomerProductSelection?
    @State private var selectedCategoryTypeID: UUID?
    @State private var selectedCategoryID: UUID?
    @State private var selectedSubcategoryID: UUID?
    @State private var selectedBrowseDestinationKey: String?
    @State private var selectedBrowseRailKey: String?
    @State private var legacyHomeMode: DastakHomeMode = .grocery
    private var homeMode: DastakHomeMode { shellService.map { $0 == .food ? .food : .grocery } ?? legacyHomeMode }
    private var selectedBrowseNodeKey: String? {
        guard let map = model.v1BrowseMap,
              let destination = map.nodes.first(where: { $0.key == selectedBrowseDestinationKey && $0.kind == "DESTINATION" }) else { return nil }
        return map.children(of: destination.key).first(where: { $0.key == selectedBrowseRailKey })?.key ?? destination.key
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSearchPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if shellService != nil {
                header
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .padding(.bottom, MarketplaceSpacing.small)
            }
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if let map = model.v1BrowseMap, homeMode == .grocery {
                    referenceCatalogue(map)
                        .opacity(isSearchPresented ? 0 : 1)
                        .allowsHitTesting(!isSearchPresented)
                        .accessibilityHidden(isSearchPresented)
                } else if let selectedCategoryType {
                    selectedDepartmentBrowser(selectedCategoryType)
                        .opacity(isSearchPresented ? 0 : 1)
                        .allowsHitTesting(!isSearchPresented)
                        .accessibilityHidden(isSearchPresented)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                            panelIntroduction
                            if shellService == nil { commerceNavigation }
                            switch homeMode {
                            case .grocery:
                                if shellService != nil {
                                    groceryDiscovery(map: model.v1BrowseMap)
                                } else {
                                    categoryRail
                                    if selectedCategoryTypeID == nil { catalogueContent }
                                }
                            case .food:
                                foodHero
                                restaurantRail
                            case .parcel, .print:
                                comingSoon
                            }
                        }
                        .padding(.horizontal, MarketplaceSpacing.medium)
                        .padding(.bottom, shellService == nil ? 148 : 24)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        if homeMode == .food { await model.refreshFood() }
                        else { await model.refreshV1Catalogue() }
                    }
                    .opacity(isSearchPresented ? 0 : 1)
                    .allowsHitTesting(!isSearchPresented)
                    .accessibilityHidden(isSearchPresented)
                }

                if isSearchPresented {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        // Background interaction is inert; use the explicit search Close control.

                    searchOverlay
                        .frame(maxHeight: max(0, geometry.size.height - MarketplaceSpacing.small), alignment: .top)
                        .padding(.horizontal, MarketplaceSpacing.medium)
                        .padding(.top, MarketplaceSpacing.small)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isSearchPresented)
        .overlay(alignment: .bottom) {
            if shellService == nil, model.showsBasketDock(model.cartService), !model.cart.isEmpty, !isSearchPresented {
                floatingCartButton
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .padding(.bottom, MarketplaceSpacing.small)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.cart.itemCount)
        .onChange(of: model.cartService) { _, service in
            if shellService == nil { legacyHomeMode = service == .food ? .food : .grocery }
        }
        .onChange(of: homeRevision) { _, _ in resetExploration() }
        .task {
            // An explicit Search shortcut opens the existing search UI once on
            // this Home revision. Foregrounding does not recreate exploration.
            guard startsWithSearch, isActive else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled, isActive else { return }
            presentSearch()
        }
        .onChange(of: selectedBrowseDestinationKey) { _, key in onBrowseDestinationChanged(key) }
        .onChange(of: directoryRevision) { _, _ in
            guard shellService == .grocery,
                  let key = directoryKey,
                  model.v1BrowseMap?.nodes.contains(where: { $0.key == key && $0.kind == "DESTINATION" }) == true else { return }
            resetExploration()
            selectedBrowseDestinationKey = key
        }
        .onChange(of: isActive) { _, active in
            if !active { isSearchFieldFocused = false; isSearchPresented = false }
        }
        .marketplacePage()
        .dastakNavigationBarHidden()
        .task(id: "\(model.availabilityRefreshKey)|\(isActive)") {
            guard isActive else { return }
            repeat {
                await model.refreshAreaAvailability(force: true)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
        .task(id: priorityArtworkKeys) {
            guard isActive else { return }
            await DastakProductArtwork.prefetch(imageKeys: priorityArtworkKeys)
        }
        .task(id: "\(selectedCategoryID?.uuidString ?? "")|\(model.catalogueRevision)|\(isActive)") {
            if isActive, let selectedCategoryID { await model.loadV1Category(selectedCategoryID) }
        }
        .task(id: "\(selectedBrowseNodeKey ?? "")|\(model.catalogueRevision)|\(isActive)|\(homeMode.rawValue)") {
            guard isActive, homeMode == .grocery,
                  let key = selectedBrowseNodeKey else { return }
            await model.loadV1BrowseNode(key)
        }
        .task(id: "\(homeMode.rawValue)|\(isActive)") {
            guard isActive, homeMode == .food, !model.requiresAreaChecks else { return }
            await model.refreshV1Restaurants()
        }
        .sheet(item: $selectedRestaurant, onDismiss: finishDetailCartRequest) { restaurant in
            DastakRestaurantMenuView(model: model, restaurant: restaurant, openCart: {
                cartAfterDetails = .food
                selectedRestaurant = nil
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .dastakProductOverlay(item: $selectedProduct, onDismiss: finishDetailCartRequest) { selection in
            DastakCustomerProductDetailView(model: model, initial: selection.product, products: selection.products, close: { selectedProduct = nil }, openCart: {
                cartAfterDetails = .grocery
                selectedProduct = nil
            })
        }
    }

    private func finishDetailCartRequest() {
        guard let service = cartAfterDetails else { return }
        cartAfterDetails = nil
        requestCart(service)
    }

    @ViewBuilder
    private var panelIntroduction: some View {
        if shellService == nil { header }
        if let message = model.browsingAreaMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.footnote)
                MarketplaceFeedbackButton("Refresh availability") { Task { await model.refreshAreaAvailability(force: true) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MarketplaceSpacing.compact)
            .background((colorScheme == .light ? Color.white.opacity(DastakPanelReadability.lightNoticeOpacity)
                         : Color.black.opacity(0.16)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var commerceNavigation: some View {
        HStack(spacing: 4) {
            ForEach(DastakHomeMode.allCases) { mode in
                MarketplaceFeedbackButton {
                    legacyHomeMode = mode
                    if mode == .food { model.cartService = .food }
                    if mode == .grocery { model.cartService = .grocery }
                    selectedCategoryTypeID = nil
                    selectedCategoryID = nil
                    selectedSubcategoryID = nil
                    selectedBrowseDestinationKey = nil
                    selectedBrowseRailKey = nil
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.symbol).font(.subheadline.weight(.semibold))
                        Text(mode.rawValue).font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(homeMode == mode ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(alignment: .topTrailing) {
                        if mode.isComingSoon {
                            Text("SOON")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(MarketplaceColors.dastakAccentSoft.color, in: Capsule())
                        }
                    }
                    .background(homeMode == mode ? MarketplaceColors.dastakAccent.color : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(mode.isComingSoon)
                .accessibilityAddTraits(homeMode == mode ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shop by service")
    }

    private var foodHero: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text("FOOD, MADE NEARBY")
                .font(.caption2.weight(.bold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Find your next favourite.")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Browse nearby restaurants and cafés. Choose a menu to get started.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MarketplaceSpacing.medium)
        .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var comingSoon: some View {
        VStack(spacing: MarketplaceSpacing.medium) {
            Image(systemName: homeMode.symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 84, height: 84)
                .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text("COMING SOON")
                .font(.caption2.weight(.bold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text(homeMode == .print ? "Print, without the errand." : "Send it with Dastak.")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 36))
                .multilineTextAlignment(.center)
            Text(homeMode == .print
                 ? "Documents and everyday print jobs, prepared carefully and delivered to your doorstep."
                 : "A simple, secure way to send parcels across your city is on its way.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(.horizontal, MarketplaceSpacing.large)
    }

    @ViewBuilder
    private var restaurantRail: some View {
        if model.isLoadingV1Restaurants {
            ProgressView("Loading restaurants near you")
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        if let failure = model.v1RestaurantsRefreshFailure {
            DastakEmptyState(symbol: failure.symbol, title: failure.title,
                             message: failure.message, actionTitle: "Retry restaurants",
                             action: { Task { await model.retryV1Restaurants() } })
        }
        if !model.v1Restaurants.isEmpty {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("RESTAURANTS & CAFES")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text("Restaurants near you")
                            .font(.title2.bold())
                    }
                    Spacer()
                    Text("\(model.v1Restaurants.count) loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    LazyVStack(spacing: MarketplaceSpacing.compact) {
                        ForEach(model.v1Restaurants) { restaurant in
                            MarketplaceFeedbackButton { selectedRestaurant = restaurant } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    DastakRestaurantBanner(imageKey: restaurant.restaurant.imageKey)
                                        .frame(height: 136)
                                        .frame(maxWidth: .infinity)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(DastakRestaurantPresentation.customerFacingName(
                                            name: restaurant.restaurant.name, branchName: restaurant.restaurant.branchName
                                        ))
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Label(model.restaurantIssue(restaurant) ?? "Accepting orders",
                                              systemImage: model.restaurantIssue(restaurant) == nil ? "checkmark.circle" : "clock")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(model.restaurantIssue(restaurant) == nil ? MarketplaceColors.dastakAccent.color : Color.secondary)
                                        HStack {
                                            let dishCount = restaurant.categories.flatMap(\.items).count
                                            Text("\(dishCount) \(dishCount == 1 ? "dish" : "dishes")")
                                            Spacer()
                                            Label(model.restaurantIssue(restaurant) == nil ? "View menu" : "Not accepting orders", systemImage: "arrow.right")
                                        }.font(.caption)
                                    }
                                    .padding(MarketplaceSpacing.small)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .marketplaceFlatSurface()
                            }
                            .buttonStyle(.plain)
                            .disabled(model.restaurantIssue(restaurant) != nil)
                            .accessibilityLabel(DastakRestaurantPresentation.accessibilityLabel(
                                name: restaurant.restaurant.name,
                                branchName: restaurant.restaurant.branchName,
                                status: model.restaurantIssue(restaurant) ?? "Accepting orders"
                            ))
                            .accessibilityHint(model.restaurantIssue(restaurant) == nil ? "Open menu" : "This restaurant cannot accept an order right now")
                        }
                    }
            }
        } else if !model.isLoadingV1Restaurants, model.v1RestaurantsRefreshFailure == nil {
            DastakEmptyState(symbol: "fork.knife", title: "No restaurants to show",
                             message: model.browsingAreaMessage ?? "Choose a delivery location or refresh to check restaurants in your area.")
                .frame(maxWidth: .infinity, minHeight: 180)
            MarketplaceFeedbackButton("Refresh restaurants") { Task { await model.refreshFood() } }
                .buttonStyle(.bordered).frame(minHeight: 44)
        }
        if model.hasMoreV1Restaurants {
            MarketplaceFeedbackButton("Load more restaurants") { Task { await model.refreshV1Restaurants(loadMore: true) } }
                .buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(model.isLoadingV1Restaurants)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            if shellService != nil {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                    if dynamicTypeSize >= .xxxLarge {
                        headerActions.frame(maxWidth: .infinity, alignment: .trailing)
                        headerGreeting
                    } else {
                        HStack(alignment: .top, spacing: MarketplaceSpacing.small) {
                            headerGreeting.frame(maxWidth: .infinity, alignment: .leading)
                            headerActions.fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    if homeMode == .food || selectedBrowseDestinationKey != nil {
                        HStack(alignment: .top, spacing: MarketplaceSpacing.small) {
                            panelHeading.frame(maxWidth: .infinity, alignment: .leading)
                            if homeMode == .grocery { categoryHomeButton }
                        }
                    }
                }
            } else if dynamicTypeSize >= .xxxLarge {
                headerTitle
                headerActions.frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { headerTitle; Spacer(); headerActions }
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        headerTitle
                        headerActions.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }

            if shellService == nil { MarketplaceFeedbackButton(action: chooseLocation) {
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
            .buttonStyle(.plain) }
        }
        .padding(.top, MarketplaceSpacing.medium)
    }

    @ViewBuilder
    private var headerTitle: some View {
        if shellService == nil { DastakWordmark(size: 31) }
        else {
            VStack(alignment: .leading, spacing: 5) {
                headerGreeting
                panelHeading
            }
        }
    }

    private var headerGreeting: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(DastakGroceryHomePresentation.greeting(
                hour: Calendar.current.component(.hour, from: context.date),
                displayName: model.checkoutCustomer?.displayName).uppercased())
                .font(.caption2.weight(.semibold)).tracking(1)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var panelHeading: some View {
        let heading = homeMode == .food ? "Food" : model.v1BrowseMap?.nodes.first(where: {
            $0.key == selectedBrowseDestinationKey && $0.kind == "DESTINATION"
        })?.label
        if let heading {
            Text(heading)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var headerActions: some View {
        HStack {
            if shellService != nil {
                MarketplaceFeedbackNavigationLink { DastakWishlistView(model: model) } label: {
                    Image(systemName: "bookmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Saved items")
            }
            searchIconButton
            cartButton
        }
    }

    private var categoryHomeButton: some View {
        MarketplaceFeedbackButton(action: resetExploration) {
            Image(systemName: "house")
                .frame(width: MarketplaceMetrics.minimumTouchTarget,
                       height: MarketplaceMetrics.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Grocery Home")
        .accessibilityIdentifier("dastak.category.home")
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
        if !model.canonicalCategoryTypes.isEmpty {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                HStack(alignment: .firstTextBaseline, spacing: MarketplaceSpacing.small) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SHOP DASTAK")
                            .font(.caption2.bold())
                            .tracking(1.1)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text(selectedCategoryType?.name ?? "Everything, beautifully organised")
                            .font(.title2.bold())
                            .lineLimit(2)
                    }
                    Spacer()
                    if selectedCategoryTypeID != nil {
                        MarketplaceFeedbackButton("All departments") {
                            selectedCategoryTypeID = nil
                            selectedCategoryID = nil
                            selectedSubcategoryID = nil
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    }
                }

                Group {
                    ForEach(navigationSections, id: \.key) { section in
                        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                            Text(section.name).font(.title3.bold())
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                spacing: MarketplaceSpacing.medium
                            ) {
                                ForEach(section.types) { type in
                                    MarketplaceFeedbackButton {
                                        selectedCategoryTypeID = type.id
                                        let children = categories(in: type.id)
                                        selectedCategoryID = (children.first { $0.status == "ACTIVE" } ?? children.first)?.id
                                        selectedSubcategoryID = nil
                                    } label: {
                                        DastakDepartmentTile(categoryType: type)
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

    private func referenceCatalogue(_ map: DastakV1CatalogueBrowseMap) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                panelIntroduction
                if let failure = model.v1CatalogueRefreshFailure {
                    DastakEmptyState(symbol: failure.symbol, title: failure.title,
                                     message: failure.message, actionTitle: "Retry catalogue",
                                     action: { Task { await model.refreshV1Catalogue() } })
                }
                if shellService == nil { commerceNavigation }
                if let destination = map.nodes.first(where: { $0.key == selectedBrowseDestinationKey && $0.kind == "DESTINATION" }) {
                    if shellService == nil {
                        categoryHomeButton.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    let rails = map.children(of: destination.key)
                    let selectedNode = rails.first(where: { $0.key == selectedBrowseRailKey }) ?? destination
                    let products = model.products(forBrowseNode: selectedNode.key)
                    let categories = model.categories(forBrowseNode: selectedNode.key)
                    let incomplete = categories.contains { model.v1CategoryProducts[$0] == nil }
                    let failed = categories.contains { model.failedV1CategoryIDs.contains($0) }
                    let loading = categories.contains { model.loadingV1CategoryIDs.contains($0) }
                    HStack {
                        if selectedNode.key != destination.key { Text(selectedNode.label).font(.headline) }
                        Spacer()
                        Text("\(DastakGroceryPresentation.families(products).count) products\(incomplete ? " loaded" : "")").font(.caption).foregroundStyle(.secondary)
                    }
                    if loading || (incomplete && !failed) {
                        ProgressView("Loading category products")
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    if failed {
                        Text("Some products could not be loaded. Your cart is saved.").font(.footnote)
                        MarketplaceFeedbackButton("Retry category") { Task { await model.loadV1BrowseNode(selectedNode.key, force: true) } }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                        MarketplaceFeedbackButton("Refresh catalogue") { Task { await model.refreshV1Catalogue() } }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                    }
                    if products.isEmpty, !incomplete, !loading, !failed {
                        DastakEmptyState(
                            symbol: "shippingbox",
                            title: "No products here yet",
                            message: "Choose another category."
                        )
                        .frame(minHeight: 280)
                    } else if !products.isEmpty {
                        if selectedBrowseRailKey == nil, !rails.isEmpty {
                            ForEach(rails) { rail in
                                let railProducts = model.products(forBrowseNode: rail.key)
                                if !railProducts.isEmpty {
                                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                                        Text(rail.label).font(.headline)
                                        Text("\(DastakGroceryPresentation.families(railProducts).count) products")
                                            .font(.caption).foregroundStyle(.secondary)
                                        productRail(railProducts)
                                    }
                                }
                            }
                        } else {
                            productRail(products)
                        }
                    }
                } else {
                    groceryDiscovery(map: map)
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.bottom, shellService == nil ? 148 : 24)
        }
        .refreshable { await model.refreshV1Catalogue() }
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
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Text("POPULAR NOW").font(.caption2.bold()).tracking(1.1).foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text("Everyday essentials").font(MarketplaceTypography.sectionTitle)
                productGrid(Array(model.activeProducts.prefix(12)))
            }
        }
    }

    private func selectedDepartmentBrowser(_ type: DastakV1CatalogueCategory) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            panelIntroduction
                .padding(.horizontal, MarketplaceSpacing.medium)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("SHOP DASTAK")
                        .font(.caption2.bold())
                        .tracking(1.1)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Spacer()
                    MarketplaceFeedbackButton("All categories") {
                        selectedCategoryTypeID = nil
                        selectedCategoryID = nil
                        selectedSubcategoryID = nil
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                Text(type.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedCategory?.name ?? "Products")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(selectedProducts.count) products")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)

            if !visibleSubcategories.isEmpty {
                Picker("Type", selection: $selectedSubcategoryID) {
                    Text("All types").tag(UUID?.none)
                    ForEach(visibleSubcategories) { item in
                        Text(item.name).tag(UUID?.some(item.id))
                    }
                }
                .pickerStyle(.menu)
                .marketplaceSelectionFeedback(selectedSubcategoryID)
                .tint(MarketplaceColors.dastakAccent.color)
                .padding(.horizontal, MarketplaceSpacing.medium)
            }

            HStack(alignment: .top, spacing: 8) {
                ScrollView(.vertical) {
                    subcategoryRail
                        .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .frame(width: 76)

                ScrollView(.vertical) {
                    Group {
                        if let category = selectedCategory, model.loadingV1CategoryIDs.contains(category.id), selectedProducts.isEmpty {
                            ProgressView("Loading \(category.name)")
                                .frame(maxWidth: .infinity, minHeight: 320)
                        } else if let category = selectedCategory, model.failedV1CategoryIDs.contains(category.id), selectedProducts.isEmpty {
                            DastakEmptyState(
                                symbol: "arrow.clockwise",
                                title: "Products could not be loaded",
                                message: "Your catalogue is still here. Try loading this category again.",
                                actionTitle: "Try again",
                                action: { Task { await model.loadV1Category(category.id, force: true) } }
                            )
                            .frame(minHeight: 320)
                        } else if selectedProducts.isEmpty {
                            DastakEmptyState(
                                symbol: DastakCatalogueSymbol.symbol(
                                    for: selectedSubcategory?.slug ?? selectedCategory?.slug ?? type.slug
                                ),
                                title: "Approved products coming soon",
                                message: "This collection is already organised in Dastak. Products will appear here after catalogue and safety checks are complete."
                            )
                            .frame(minHeight: 320)
                        } else {
                            productGrid(selectedProducts)
                        }
                    }
                    .padding(.bottom, 148)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.refreshV1Catalogue() }
                .frame(maxWidth: .infinity)
                .id(selectedCategoryID)
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var subcategoryRail: some View {
        LazyVStack(spacing: MarketplaceSpacing.compact) {
            ForEach(selectedCategoryType.map { categories(in: $0.id) } ?? []) { category in
                MarketplaceFeedbackButton {
                    selectedCategoryID = category.id
                    selectedSubcategoryID = nil
                } label: {
                    DastakCategoryTile(category: category, selected: selectedCategoryID == category.id)
                        .padding(4)
                        .background(selectedCategoryID == category.id ? MarketplaceColors.dastakAccentSoft.color : .clear, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedCategoryID == category.id ? .isSelected : [])
            }
        }
    }

    private var priorityArtworkKeys: [String] {
        var keys: [String] = []
        if let selectedCategory {
            if let key = selectedCategory.imageKey {
                keys.append(key)
            }
            keys.append(contentsOf: (selectedCategoryType.map { categories(in: $0.id) } ?? []).compactMap(\.imageKey))
            keys.append(contentsOf: selectedProducts.prefix(16).compactMap(\.imageKey))
        } else {
            let destinations = selectedCategoryType.map { categories(in: $0.id) }
                ?? model.canonicalCategoryTypes
            for destination in destinations {
                if let imageKey = destination.imageKey { keys.append(imageKey) }
            }
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }.prefix(32).map { $0 }
    }

    private func groceryDiscovery(map: DastakV1CatalogueBrowseMap?) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Text("Quick picks").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                if let map, let catalogue = model.v1Catalogue {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                    let picks = DastakGroceryHomePresentation.quickPicks(map: map, catalogue: catalogue,
                        products: model.v1BrowseProducts, date: context.date)
                    if !picks.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: MarketplaceSpacing.medium) {
                                ForEach(picks) { pick in
                                    MarketplaceFeedbackButton {
                                        selectedBrowseDestinationKey = pick.destinationKey
                                        selectedBrowseRailKey = pick.id
                                    } label: {
                                        VStack(spacing: MarketplaceSpacing.small) {
                                            DastakQuickPickArtwork(imageKeys: pick.imageKeys)
                                            Text(pick.label).font(.caption.weight(.medium))
                                                .multilineTextAlignment(.center)
                                                .foregroundStyle(.primary)
                                        }
                                        .frame(width: dynamicTypeSize.isAccessibilitySize ? 128 : 84)
                                        .padding(.vertical, MarketplaceSpacing.small)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Browse \(pick.label)")
                                }
                            }
                        }
                        .scrollIndicators(.visible)
                    } else {
                        Text("Quick picks will appear as products become available. Browse categories from the Grocery button.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    }
                } else {
                    Text("Quick picks will appear when the catalogue is ready.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Text("Trending in your city").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                if let products = model.localTrendingProducts, !products.isEmpty {
                    #if DEBUG
                    if !model.requiresAreaChecks {
                        Text("Preview ranking · sample products").font(.caption).foregroundStyle(.secondary)
                    }
                    #endif
                    productRail(products)
                } else {
                HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(MarketplaceColors.accent(for: colorScheme))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.localTrendingProducts == nil ? "Local favourites are unavailable." : "No local favourites yet.").font(.headline)
                        Text(model.localTrendingProducts == nil ? "Choose your delivery location and check again." : "Popular products will appear here as orders are delivered nearby.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if model.localTrendingProducts == nil, model.deliveryAddress != nil {
                            MarketplaceFeedbackButton("Retry") { Task { await model.refreshAreaAvailability(force: true) } }
                                .frame(minHeight: 44)
                        }
                    }
                }
                .padding(MarketplaceSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .marketplaceFlatSurface()
                }
            }
        }
    }

    private func productRail(_ products: [DastakV1CatalogueSKU]) -> some View {
        let families = DastakGroceryPresentation.families(products)
        return ScrollView(.horizontal) {
            // Measure every card at its final width before sizing this nested
            // horizontal scroller. Lazy estimates can clip taller size buttons.
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                ForEach(families) { family in
                    productTile(family, products: products)
                        .containerRelativeFrame(.horizontal,
                            count: dynamicTypeSize >= .xxxLarge ? 1 : 2,
                            spacing: MarketplaceSpacing.compact)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 1)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func productGrid(_ products: [DastakV1CatalogueSKU]) -> some View {
        let families = DastakGroceryPresentation.families(products)
        return LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: MarketplaceSpacing.compact, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                spacing: MarketplaceSpacing.compact
        ) {
                ForEach(families) { family in
                    productTile(family, products: products)
                }
        }
    }

    private func productTile(_ family: DastakGroceryPresentation.Family,
                             products: [DastakV1CatalogueSKU]) -> some View {
        let basket = DastakGroceryPresentation.shelfBasketSelection(family, cart: model.baskets[.grocery])
        let product = basket.product
        return DastakV1ProductTile(
                        product: product,
                        isWishlisted: model.isWishlisted(kind: .retailSKU, itemID: product.id),
                        isUpdatingWishlist: model.wishlistChangeDisabled(product.id),
                        add: {
                            if family.packs.count > 1 && (basket.quantity == 0 || basket.hasMultipleSizes) { selectedProduct = CustomerProductSelection(product: product, products: products) }
                            else { model.addShoppingProduct(product) }
                        },
                        toggleWishlist: {
                            Task { await model.toggleWishlist(kind: .retailSKU, itemID: product.id) }
                        },
                        openDetail: { selectedProduct = CustomerProductSelection(product: product, products: products) },
                        addIssue: basket.quantity > 0 && !basket.hasMultipleSizes ? model.groceryAddIssue(product.id) : family.packs.contains(where: { model.groceryAddIssue($0.id) == nil }) ? nil : model.groceryAddIssue(product.id),
                        packCount: family.packs.count,
                        isOutOfStock: family.packs.count == 1 && model.groceryStockQuantity(product.id) == 0,
                        quantity: basket.quantity,
                        remove: {
                            if basket.hasMultipleSizes { selectedProduct = CustomerProductSelection(product: product, products: products) }
                            else { model.decrementCartItem(product.id) }
                        },
                        selectedPack: family.packs.count > 1 && basket.quantity > 0 && !basket.hasMultipleSizes ? product.packSize : nil,
                        quantityLimitReached: !basket.hasMultipleSizes && basket.quantity >= DastakCart.maximumQuantity
                    )
    }

    private var selectedCategory: DastakV1CatalogueCategory? {
        model.canonicalCategories.first { $0.id == selectedCategoryID }
    }

    private var selectedCategoryType: DastakV1CatalogueCategory? {
        model.canonicalCategoryTypes.first { $0.id == selectedCategoryTypeID }
    }

    private func categories(in categoryTypeID: UUID) -> [DastakV1CatalogueCategory] {
        model.canonicalCategories.filter { $0.categoryTypeID == categoryTypeID }
    }

    private var navigationSections: [DastakCatalogueNavigationGroup] {
        let grouped = Dictionary(grouping: model.canonicalCategoryTypes) {
            $0.navigationSection?.key ?? "more"
        }
        return grouped.map { key, types in
            let metadata = types.compactMap(\.navigationSection).first
            return DastakCatalogueNavigationGroup(
                key: key,
                name: metadata?.name ?? "More to explore",
                sortOrder: metadata?.sortOrder ?? 999,
                types: types.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            )
        }
        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var visibleSubcategories: [DastakV1CatalogueSubcategory] {
        model.canonicalSubcategories.filter { $0.categoryID == selectedCategoryID }
    }

    private var selectedSubcategory: DastakV1CatalogueSubcategory? {
        visibleSubcategories.first { $0.id == selectedSubcategoryID }
    }

    private var selectedProducts: [DastakV1CatalogueSKU] {
        if let selectedSubcategoryID { return model.products(inSubcategory: selectedSubcategoryID) }
        guard let selectedCategoryID else { return selectedCategoryTypeID == nil ? model.activeProducts : [] }
        return model.products(in: selectedCategoryID)
    }

    private var parcelBand: some View {
        MarketplaceFeedbackButton(action: sendParcel) {
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
        DastakBasketPickupButton(model: model, service: homeMode == .food ? .food : .grocery)
    }

    @ViewBuilder
    private var floatingCartButton: some View {
        let button = MarketplaceFeedbackButton(action: openCart) {
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
        MarketplaceFeedbackButton(action: presentSearch) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .frame(width: MarketplaceMetrics.minimumTouchTarget,
                       height: MarketplaceMetrics.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            guard !trimmedSearchText.isEmpty else {
                await model.searchV1Catalogue()
                return
            }
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
                .accessibilityHidden(true)

            TextField("Search products and essentials", text: $model.searchText)
#if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
#endif
                .focused($isSearchFieldFocused)
                .accessibilityLabel("Search products and essentials")
                .accessibilityIdentifier("dastak.search.field")
                .onSubmit {
                    haptics?.play(.tap)
                    isSearchFieldFocused = false
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
        let button = MarketplaceFeedbackButton(action: closeSearch) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .frame(
                    width: MarketplaceMetrics.minimumTouchTarget,
                    height: MarketplaceMetrics.minimumTouchTarget
                )
        }
        .accessibilityLabel("Close search")
        .accessibilityIdentifier("dastak.search.close")

        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            button.buttonStyle(MarketplaceIconButtonStyle())
        }
    }

    private var searchResults: some View {
        ScrollView {
            LazyVStack(spacing: MarketplaceSpacing.small) {
                if model.isSearchingV1Catalogue, model.activeProducts.isEmpty {
                    DastakLoadingOverlay(title: "Searching Dastak")
                } else if let failure = model.v1SearchRefreshFailure {
                    DastakEmptyState(symbol: failure.symbol, title: failure.title,
                                     message: failure.message, actionTitle: "Retry search",
                                     action: { Task { await model.searchV1Catalogue() } })
                } else {
                    if model.activeProducts.isEmpty {
                        ContentUnavailableView.search(text: trimmedSearchText)
                            .padding(.vertical, MarketplaceSpacing.large)
                    } else {
                        ForEach(model.activeProducts) { product in
                            searchResultRow(product)
                        }
                    }
                }
            }
            .padding(MarketplaceSpacing.small)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxHeight: 520)
        .marketplaceGlass(cornerRadius: MarketplaceMetrics.sheetCornerRadius)
    }

    private func searchResultRow(_ product: DastakV1CatalogueSKU) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
          HStack(spacing: MarketplaceSpacing.compact) {
            DastakProductArtwork(imageKey: product.imageKey, fallbackSymbol: artworkSymbol(for: product))
                .frame(width: 66, height: 66)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                if let brand = product.brand?.name {
                    Text(brand.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .lineLimit(1)
                }
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !DastakGroceryPresentation.searchPackDescription(product).isEmpty {
                    Text(DastakGroceryPresentation.searchPackDescription(product))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(DastakFormatting.money(product.price))
                    .font(.subheadline.bold().monospacedDigit())
            }
            .accessibilityElement(children: .combine)

          }
          HStack {
            Spacer(minLength: 0)
            MarketplaceFeedbackButton {
                Task { await model.toggleWishlist(kind: .retailSKU, itemID: product.id) }
            } label: {
                Image(systemName: model.isWishlisted(kind: .retailSKU, itemID: product.id) ? "heart.fill" : "heart")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(MarketplaceColors.dastakAccent.color)
            .disabled(model.wishlistUpdatingIDs.contains(product.id))
            .accessibilityLabel(model.isWishlisted(kind: .retailSKU, itemID: product.id)
                ? "Remove \(DastakGroceryPresentation.searchAccessibilityIdentity(product)) from Wishlist"
                : "Save \(DastakGroceryPresentation.searchAccessibilityIdentity(product)) to Wishlist")

            MarketplaceFeedbackButton { model.addShoppingProduct(product) } label: {
                Group {
                    if model.groceryStockQuantity(product.id) == 0 {
                        Text("Out of stock").font(.caption.weight(.semibold)).padding(.horizontal, 10)
                    } else {
                        Image(systemName: "plus").font(.subheadline.bold())
                    }
                }
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(.white)
                    .background(
                        MarketplaceColors.primaryAction.color,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.groceryStockQuantity(product.id) == 0
                ? "\(DastakGroceryPresentation.searchAccessibilityIdentity(product)), Out of stock"
                : "Add \(DastakGroceryPresentation.searchAccessibilityIdentity(product))")
            .disabled(model.groceryStockQuantity(product.id) == 0 || model.groceryAddIssue(product.id) != nil)
            .dastakBasketAnchor(DastakBasketService.grocery.itemAnchor(product.id))
          }
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

    private func resetExploration() {
        selectedRestaurant = nil
        selectedProduct = nil
        selectedCategoryTypeID = nil
        selectedCategoryID = nil
        selectedSubcategoryID = nil
        selectedBrowseDestinationKey = nil
        selectedBrowseRailKey = nil
        isSearchPresented = false
        isSearchFieldFocused = false
        // Search is exploration, not a shopping/recovery record.
        model.searchText = ""
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

private struct DastakCatalogueNavigationGroup {
    let key: String
    let name: String
    let sortOrder: Int
    let types: [DastakV1CatalogueCategory]
}

private struct DastakDepartmentTile: View {
    let categoryType: DastakV1CatalogueCategory

    var body: some View {
        VStack(spacing: 7) {
            DastakCategoryArtwork(
                imageKey: categoryType.imageKey,
                fallbackSymbol: DastakCatalogueSymbol.symbol(for: categoryType.slug)
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            Text(categoryType.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 31, alignment: .top)
            if categoryType.status != nil, categoryType.status != "ACTIVE" {
                Text("COMING SOON")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct DastakCategoryTile: View {
    let category: DastakV1CatalogueCategory
    var selected = false

    var body: some View {
        VStack(spacing: 7) {
            DastakCategoryArtwork(
                imageKey: category.imageKey,
                fallbackSymbol: DastakCatalogueSymbol.symbol(for: category.slug)
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            Text(category.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(selected ? MarketplaceColors.primaryActionForeground.color : Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 31, alignment: .top)
            if category.status != nil, category.status != "ACTIVE" {
                Text("COMING SOON")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
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
                imageKey: subcategory.imageKey,
                fallbackSymbol: DastakCatalogueSymbol.symbol(for: subcategory.slug)
            )
            .frame(width: 64, height: 58)
            Text(subcategory.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? MarketplaceColors.primaryActionForeground.color : Color.primary)
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
    var initialItemID: UUID? = nil
    let openCart: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.marketplaceHapticScope) private var haptics
    private func categoryNavigation(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            Button("Top of menu") {
                haptics?.play(.selection)
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo("restaurant-menu-top", anchor: .top)
                }
            }
            ForEach(restaurant.categories) { category in
                Button(category.name) {
                    guard let target = DastakRestaurantPresentation.menuCategoryScrollTarget(
                        restaurant.categories, categoryID: category.id
                    ) else { return }
                    haptics?.play(.selection)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .tint(MarketplaceColors.dastakAccent.color)
        .accessibilityLabel("Jump to menu category")
        .accessibilityHint("Scrolls to a category without hiding any dishes")
        .accessibilityIdentifier("dastak.restaurant.category-filter")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    DastakRestaurantBanner(imageKey: restaurant.restaurant.imageKey)
                    .frame(height: 144)
                    .frame(maxWidth: .infinity)
                    .id("restaurant-menu-top")

                    ForEach(restaurant.categories) { category in
                        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                            HStack(alignment: .center) {
                                Text(category.name).font(.title2.bold())
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: MarketplaceSpacing.small)
                                categoryNavigation(proxy)
                            }
                            if let description = category.description {
                                Text(description).font(.footnote).foregroundStyle(.secondary)
                            }
                            ForEach(category.items) { item in
                                DastakRestaurantItemCard(
                                    item: item,
                                    isWishlisted: model.isWishlisted(kind: .menuItem, itemID: item.id),
                                    isUpdatingWishlist: model.wishlistChangeDisabled(item.id),
                                    add: { item, optionIDs in
                                        model.addShoppingFood(
                                            restaurant: restaurant,
                                            item: item,
                                            optionIDs: optionIDs
                                        )
                                    },
                                    toggleWishlist: {
                                        Task { await model.toggleWishlist(kind: .menuItem, itemID: item.id) }
                                    }
                                )
                                .disabled(model.restaurantIssue(restaurant) != nil)
                                .dastakBasketAnchor(DastakBasketService.food.itemAnchor(item.id))
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, MarketplaceSpacing.medium)
                        .id(category.id)
                    }
                }
                .padding(.bottom, MarketplaceSpacing.medium)
            }
            .task(id: initialItemID) {
                guard let id = initialItemID, restaurant.categories.flatMap(\.items).contains(where: { $0.id == id }) else { return }
                await Task.yield()
                proxy.scrollTo(id, anchor: .top)
            }
            }
            .navigationTitle(DastakRestaurantPresentation.customerFacingName(
                name: restaurant.restaurant.name, branchName: restaurant.restaurant.branchName
            ))
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MarketplaceFeedbackButton("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if !model.hasBasket(.food) {
                        DastakBasketPickupButton(model: model, service: .food)
                    }
                }
            }
        }
        .marketplacePage()
        .dastakBasketExperience(model: model, service: .food, openCart: openCart)
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
                VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                    if item.imageKey != nil {
                        DastakProductArtwork(imageKey: item.imageKey, fallbackSymbol: "fork.knife")
                            .frame(width: 104)
                    }
                    Text(item.name).font(.headline)
                }
                Spacer(minLength: 8)
                MarketplaceFeedbackButton(action: toggleWishlist) {
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
                        MarketplaceFeedbackButton(haptic: .selection) { toggle(option.id, in: group) } label: {
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
            MarketplaceFeedbackButton { add(item, selectedIDs) } label: {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.marketplaceHapticScope) private var haptics
    let product: DastakV1CatalogueSKU
    let isWishlisted: Bool
    let isUpdatingWishlist: Bool
    let add: () -> Void
    let toggleWishlist: () -> Void
    var openDetail: (() -> Void)? = nil
    var addIssue: String? = nil
    var packCount = 1
    var isOutOfStock = false
    var quantity = 0
    var remove: (() -> Void)? = nil
    var selectedPack: String? = nil
    var quantityLimitReached = false

    private var stacksPurchaseControls: Bool { quantity > 0 || packCount > 1 || isOutOfStock || dynamicTypeSize >= .xxxLarge }
    private var purchaseLayout: AnyLayout {
        if stacksPurchaseControls { AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) }
        else { AnyLayout(HStackLayout(alignment: .center)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let brand = product.brand?.name {
                    Text(brand.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                MarketplaceFeedbackButton(action: toggleWishlist) {
                    Image(systemName: isWishlisted ? "heart.fill" : "heart")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingWishlist)
                .accessibilityLabel(isWishlisted ? "Remove \(product.name) from Wishlist" : "Save \(product.name) to Wishlist")
            }
            GeometryReader { bounds in
                DastakProductArtwork(imageKey: product.imageKey, fallbackSymbol: artworkSymbol)
                    .frame(width: bounds.size.width, height: bounds.size.height)
            }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 140 : 104)
                .dastakBasketAnchor(DastakBasketService.grocery.itemAnchor(product.id))
                .onTapGesture { if let openDetail { openDetail(); haptics?.play(.tap) } }
                .accessibilityHidden(false)
                .accessibilityLabel("View \(product.name) details")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if let openDetail { openDetail(); haptics?.play(.tap) } }
            Text(product.name)
                .font(.subheadline.bold())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 0 : 42, alignment: .topLeading)
                .onTapGesture { if let openDetail { openDetail(); haptics?.play(.tap) } }
            Text(selectedPack.map { "\($0) · \(packCount) sizes" } ?? (packCount > 1 ? "\(packCount) pack sizes" : DastakGroceryPresentation.searchPackDescription(product)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            purchaseLayout {
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
                if !stacksPurchaseControls { Spacer(minLength: 4) }
                if quantity > 0, let remove {
                    HStack(spacing: 0) {
                        MarketplaceFeedbackButton(action: remove) {
                            Image(systemName: "minus").font(.subheadline.bold())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove one \(product.name)")
                        .accessibilityIdentifier("grocery.shelf.minus.\(product.id)")
                        Text("\(quantity)")
                            .font(.subheadline.bold().monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityLabel("\(quantity) in basket")
                        MarketplaceFeedbackButton(action: add) {
                            Image(systemName: "plus").font(.subheadline.bold())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(isOutOfStock || addIssue != nil || quantityLimitReached)
                        .accessibilityLabel("Add one \(product.name)")
                        .accessibilityIdentifier("grocery.shelf.plus.\(product.id)")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(MarketplaceColors.primaryAction.color, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                MarketplaceFeedbackButton(action: add) {
                    Group {
                        if packCount > 1 || isOutOfStock {
                            Text(DastakGroceryPresentation.purchaseTitle(stockQuantity: isOutOfStock ? 0 : nil,
                                chooseSize: packCount > 1)).font(.caption.weight(.semibold))
                        }
                        else { Image(systemName: "plus").font(.headline) }
                    }
                        .frame(minWidth: 44, maxWidth: stacksPurchaseControls ? .infinity : nil, minHeight: 44)
                        .padding(.horizontal, packCount > 1 ? 6 : 0)
                        .foregroundStyle(.white)
                        .background(
                            isOutOfStock ? Color.secondary.opacity(0.25) : MarketplaceColors.primaryAction.color,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOutOfStock ? "\(product.name), Out of stock" : packCount > 1 ? "Choose pack size for \(product.name)" : "Add \(product.name)")
                .disabled(isOutOfStock || (packCount == 1 && addIssue != nil))
                }
            }
            if let addIssue, addIssue != "Out of stock" {
                Text(addIssue).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
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

// Capture the chosen SKU and its browsing context in one presentation value.
// Separate @State writes can leave the first full-screen cover with a stale list.
private struct CustomerProductSelection: Identifiable {
    let product: DastakV1CatalogueSKU
    let products: [DastakV1CatalogueSKU]
    var id: UUID { product.id }
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
