import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakWishlistView: View {
    @ObservedObject var model: DastakCustomerModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedMenuSelection: DastakWishlistMenuSelection?
    @State private var selectedProduct: DastakV1CatalogueSKU?
    @State private var cartAfterDetails: DastakBasketService?
    @Environment(\.dastakOpenCart) private var requestCart

    private var usesStackedRows: Bool { dynamicTypeSize >= .xxxLarge }
    private var rowLayout: AnyLayout {
        usesStackedRows
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: MarketplaceSpacing.compact))
            : AnyLayout(HStackLayout(spacing: MarketplaceSpacing.compact))
    }
    private var actionsLayout: AnyLayout {
        usesStackedRows
            ? AnyLayout(HStackLayout(spacing: 10))
            : AnyLayout(VStackLayout(spacing: 5))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                header
                content
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.top, MarketplaceSpacing.medium)
            .padding(.bottom, MarketplaceSpacing.xxLarge)
        }
        .scrollIndicators(.hidden)
        .marketplacePage()
        .navigationTitle("Wishlist")
        .dastakInlineNavigationTitle()
        .refreshable {
            await refreshSavedItems(forceAvailability: true)
        }
        .task {
            await refreshSavedItems()
        }
        .toolbar {
            MarketplaceFeedbackButton("Refresh") { Task { await refreshSavedItems(forceAvailability: true) } }
                .disabled(model.isLoadingWishlist || model.isResolvingSavedItems)
                .accessibilityLabel("Refresh Wishlist and local availability")
        }
        .sheet(item: $selectedMenuSelection, onDismiss: finishDetailCartRequest) { selection in
            DastakRestaurantMenuView(model: model, restaurant: selection.restaurant, initialItemID: selection.item.id, openCart: {
                cartAfterDetails = .food
                selectedMenuSelection = nil
            })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .dastakProductOverlay(item: $selectedProduct, onDismiss: finishDetailCartRequest) { product in
            DastakCustomerProductDetailView(model: model, initial: product, products: model.knownCatalogueProducts, close: { selectedProduct = nil }, openCart: {
                cartAfterDetails = .grocery
                selectedProduct = nil
            })
        }
        .dastakBasketExperience(model: model, service: model.cartService, openCart: { requestCart(model.cartService) })
    }
    private func finishDetailCartRequest() {
        guard let service = cartAfterDetails else { return }
        cartAfterDetails = nil
        requestCart(service)
    }
    private func refreshSavedItems(forceAvailability: Bool = false) async {
        await model.refreshWishlist()
        await model.refreshAreaAvailability(force: forceAvailability)
        await model.resolveWishlistContents()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            if usesStackedRows {
                Text("Saved items").font(.title2.bold())
            } else {
                Text("SAVED FOR LATER")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text("Things worth remembering")
                    .font(MarketplaceTypography.instrumentSerif(size: 40, relativeTo: .largeTitle))
            }
            Text("Your saved products and dishes. Stock and final prices are checked again at checkout.")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isResolvingSavedItems {
            ProgressView("Checking saved items")
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        if let failure = model.savedItemsRefreshFailure {
            DastakEmptyState(symbol: failure.symbol, title: failure.title, message: failure.message,
                             actionTitle: "Retry saved items", action: { Task { await refreshSavedItems(forceAvailability: true) } })
        }
        if let failure = model.wishlistRefreshFailure {
            DastakEmptyState(symbol: failure.symbol, title: "Wishlist could not refresh", message: failure.message + " Your saved entries were not discarded.", actionTitle: "Retry Wishlist", action: { Task { await refreshSavedItems(forceAvailability: true) } })
        }
        if model.isLoadingWishlist, !model.hasLoadedWishlist {
            ProgressView("Opening your Wishlist")
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if !model.hasLoadedWishlist {
            if model.wishlistRefreshFailure == nil { Text("Your Wishlist has not been loaded yet.").foregroundStyle(.secondary) }
        } else if model.wishlistItems.isEmpty && model.wishlistRefreshFailure == nil {
            DastakEmptyState(
                symbol: "heart",
                title: "Your Wishlist is ready",
                message: "Tap the heart on a product or Restaurant/Cafe item to save it here."
            )
            .frame(minHeight: 300)
        } else {
            if !model.wishlistRetailProducts.isEmpty {
                wishlistSection(title: "Retail essentials", count: model.wishlistRetailProducts.count) {
                    ForEach(model.wishlistRetailProducts) { product in
                        retailRow(product)
                    }
                }
            }

            if !model.wishlistMenuSelections.isEmpty {
                wishlistSection(title: "Restaurant & Cafe", count: model.wishlistMenuSelections.count) {
                    ForEach(model.wishlistMenuSelections) { selection in
                        menuRow(selection)
                    }
                }
            }

            if model.unresolvedWishlistItemCount > 0 {
                wishlistSection(title: "Saved entries not loaded", count: model.unresolvedWishlistItemCount) {
                    ForEach(model.unresolvedWishlistItems) { item in
                        rowLayout {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.kind == .retailSKU ? "Saved Grocery product" : "Saved Food item").font(.headline)
                                Text("Not resolved in the loaded catalogue. It may need a refresh or may not currently be listed.").font(.footnote).foregroundStyle(.secondary)
                                Text(item.itemID.uuidString).font(.caption2).textSelection(.enabled)
                            }
                            if !usesStackedRows { Spacer(minLength: 0) }
                            MarketplaceFeedbackButton("Remove") { Task { await model.removeWishlistItem(kind: item.kind, itemID: item.itemID) } }
                                .frame(minHeight: 44)
                                .disabled(model.wishlistUpdatingIDs.contains(item.itemID))
                                .accessibilityIdentifier("wishlist.remove.\(item.id)")
                        }.padding(MarketplaceSpacing.compact).dastakAccountSurface()
                    }
                }
            }
        }
    }

    private func wishlistSection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            rowLayout {
                Text(title).font(MarketplaceTypography.sectionTitle)
                if !usesStackedRows { Spacer() }
                Text(count.formatted())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LazyVStack(spacing: MarketplaceSpacing.compact) { content() }
        }
    }

    private func retailRow(_ product: DastakV1CatalogueSKU) -> some View {
        rowLayout {
            DastakProductArtwork(imageKey: product.imageKey)
                .frame(width: 82, height: usesStackedRows ? 82 : nil)
                .dastakBasketAnchor(DastakBasketService.grocery.itemAnchor(product.id))
            VStack(alignment: .leading, spacing: 4) {
                if let brand = product.brand?.name {
                    Text(brand.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                Text(product.name).font(.headline).lineLimit(usesStackedRows ? nil : 2)
                Text([product.variant, product.packSize].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(usesStackedRows ? nil : 1)
                Text(DastakFormatting.money(product.price))
                    .font(.subheadline.bold().monospacedDigit())
            }
            if !usesStackedRows { Spacer(minLength: 4) }
            actionsLayout {
                MarketplaceFeedbackButton("Details") { selectedProduct = product }
                    .frame(minHeight: 44)
                    .accessibilityLabel("View saved \(product.name)")
                MarketplaceFeedbackButton {
                    Task { await model.removeWishlistItem(kind: .retailSKU, itemID: product.id) }
                } label: {
                    Image(systemName: "heart.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .disabled(model.wishlistUpdatingIDs.contains(product.id))
                .accessibilityLabel("Remove \(product.name) from Wishlist")

                MarketplaceFeedbackButton { model.addShoppingProduct(product) } label: {
                    Group {
                        if model.groceryStockQuantity(product.id) == 0 {
                            Text("Out of stock").font(.caption.weight(.semibold)).padding(.horizontal, 10)
                        } else {
                            Image(systemName: "plus").font(.headline)
                        }
                    }
                        .foregroundStyle(.white)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(MarketplaceColors.primaryAction.color, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.groceryStockQuantity(product.id) == 0
                    ? "\(product.name), \(product.packSize), Out of stock" : "Add \(product.name) to basket")
                .disabled(model.groceryStockQuantity(product.id) == 0 || model.groceryAddIssue(product.id) != nil)
            }
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }

    private func menuRow(_ selection: DastakWishlistMenuSelection) -> some View {
        rowLayout {
            DastakProductArtwork(imageKey: selection.item.imageKey, fallbackSymbol: "fork.knife")
                .frame(width: 82, height: usesStackedRows ? 82 : nil)
                .dastakBasketAnchor(DastakBasketService.food.itemAnchor(selection.item.id))
            VStack(alignment: .leading, spacing: 4) {
                Text(DastakRestaurantPresentation.customerFacingName(
                    name: selection.restaurant.restaurant.name,
                    branchName: selection.restaurant.restaurant.branchName
                ).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(selection.item.name).font(.headline).lineLimit(usesStackedRows ? nil : 2)
                Text(DastakFormatting.money(selection.item.basePrice))
                    .font(.subheadline.bold().monospacedDigit())
            }
            if !usesStackedRows { Spacer(minLength: 4) }
            actionsLayout {
                MarketplaceFeedbackButton("Details") { selectedMenuSelection = selection }
                    .frame(minHeight: 44)
                    .accessibilityLabel("View saved \(selection.item.name)")
                    .disabled(model.restaurantIssue(selection.restaurant) != nil)
                MarketplaceFeedbackButton {
                    Task { await model.removeWishlistItem(kind: .menuItem, itemID: selection.item.id) }
                } label: {
                    Image(systemName: "heart.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .disabled(model.wishlistUpdatingIDs.contains(selection.item.id))
                .accessibilityLabel("Remove \(selection.item.name) from Wishlist")

                MarketplaceFeedbackButton {
                    if selection.item.optionGroups.isEmpty {
                        model.addShoppingFood(
                            restaurant: selection.restaurant,
                            item: selection.item,
                            optionIDs: []
                        )
                    } else {
                        selectedMenuSelection = selection
                    }
                } label: {
                    Image(systemName: selection.item.optionGroups.isEmpty ? "plus" : "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(MarketplaceColors.primaryAction.color, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selection.item.optionGroups.isEmpty ? "Add \(selection.item.name) to basket" : "Choose options for \(selection.item.name)")
                .disabled(model.restaurantIssue(selection.restaurant) != nil)
            }
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }
}

struct DastakPaymentSettingsView: View {
    @ObservedObject var model: DastakCustomerModel

    private var paymentOrders: [DastakV1OrderSnapshot] {
        model.v1Orders.filter { DastakPaymentActivity.title($0) != nil || !($0.support?.refunds.isEmpty ?? true) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PAYMENTS")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text("Pay at delivery")
                        .font(MarketplaceTypography.instrumentSerif(size: 40, relativeTo: .largeTitle))
                    Text("Confirm your secured order, then pay the delivery partner by UPI or cash. No charge at confirmation.")
                        .font(MarketplaceTypography.supporting)
                        .foregroundStyle(.secondary)
                }

                paymentSecurityCard
                acceptedMethods
                confirmationRecovery
                recentActivity
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.top, MarketplaceSpacing.medium)
            .padding(.bottom, MarketplaceSpacing.xxLarge)
        }
        .scrollIndicators(.hidden)
        .marketplacePage()
        .navigationTitle("Payments")
        .dastakInlineNavigationTitle()
        .refreshable { await model.refreshV1Orders() }
        .task { await model.refreshV1Orders() }
    }

    private var paymentSecurityCard: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(MarketplaceColors.dastakAccentDark.color)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text("UPI / Cash on Delivery")
                    .font(.headline)
                    .foregroundStyle(MarketplaceColors.textPrimaryDark.color)
                Text("An order confirmation is not a completed payment. Collection is shown only when it has been recorded against your order.")
                    .font(.footnote)
                    .foregroundStyle(MarketplaceColors.textSecondaryDark.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background { DastakMatteBackground(style: .dark) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var acceptedMethods: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Ways to pay").font(MarketplaceTypography.sectionTitle)
            VStack(spacing: 0) {
                paymentMethodRow("UPI", symbol: "arrow.up.right.circle")
                Divider().padding(.leading, 62)
                paymentMethodRow("Cash", symbol: "banknote")
            }
            .padding(.horizontal, MarketplaceSpacing.compact)
            .dastakAccountSurface()
            Text("Pay the delivery partner at your doorstep.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func paymentMethodRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 42, height: 42)
                .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 13))
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text("AT DELIVERY")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 68)
    }

    @ViewBuilder
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                Text("Recent payment activity").font(MarketplaceTypography.sectionTitle)
                Spacer()
                Text(paymentOrders.count.formatted()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if paymentOrders.isEmpty {
                DastakEmptyState(
                    symbol: "creditcard",
                    title: "No payment activity loaded",
                    message: "Order confirmations, recorded collections and refunds appear here."
                )
                .frame(minHeight: 220)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(paymentOrders.enumerated()), id: \.element.id) { index, order in
                        HStack(spacing: MarketplaceSpacing.compact) {
                            Image(systemName: order.launchPayment?.collectedAt != nil || (order.launchPayment == nil && order.paidAt != nil) ? "checkmark.shield.fill" : "clock")
                                .foregroundStyle(MarketplaceColors.success.color)
                                .frame(width: 42, height: 42)
                                .background(MarketplaceColors.success.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(order.displayOrderNumber).font(.subheadline.weight(.semibold))
                                Text(DastakPaymentActivity.title(order) ?? "Refund activity")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let date = DastakV1OrderPresentation.date(DastakPaymentActivity.timestamp(order)) {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(DastakFormatting.money(order.price.total))
                                .font(.subheadline.bold().monospacedDigit())
                        }
                        .frame(minHeight: 72)
                        ForEach(order.support?.refunds ?? []) { refund in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Refund · \(refund.status.replacingOccurrences(of: "_", with: " ").capitalized)")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(DastakFormatting.money(refund.amount)) · \(refund.destination.replacingOccurrences(of: "_", with: " ").capitalized)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let date = DastakV1OrderPresentation.date(refund.completedAt ?? refund.createdAt) {
                                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }
                        if index < paymentOrders.count - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .padding(.horizontal, MarketplaceSpacing.compact)
                .dastakAccountSurface()
            }
            if let issue = model.v1OrderErrorMessage { Text(issue).font(.footnote).foregroundStyle(.secondary) }
            if model.isLoadingV1Orders { ProgressView("Loading activity…") }
            if model.canLoadMoreV1Orders {
                MarketplaceFeedbackButton("Load earlier orders") { Task { await model.loadMoreV1Orders() } }
                    .disabled(model.isLoadingV1Orders || model.isLoadingMoreV1Orders)
            }
            Text("Activity reflects loaded orders. Pull to refresh for the latest status.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var confirmationRecovery: some View {
        if let issue = model.checkoutRecoveryIssue {
            Text(issue).font(.footnote).foregroundStyle(.secondary)
            MarketplaceFeedbackButton("Retry loading saved checkout") { Task { await model.restoreCartStorage(force: true) } }
                .disabled(model.isCheckingOut)
        }
        if !model.pendingConfirmations.isEmpty {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Text("Confirmations to check").font(MarketplaceTypography.sectionTitle)
                Text("Check these original orders before trying to confirm again.").font(.footnote).foregroundStyle(.secondary)
                ForEach(model.pendingConfirmations.keys.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                    MarketplaceFeedbackButton {
                        Task { await model.recoverConfirmation(orderID: id) }
                    } label: {
                        Label("Recover \(model.v1Orders.first { $0.id == id }?.displayOrderNumber ?? String(id.uuidString.prefix(8)))", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isCheckingOut || !model.isCartStorageReady)
                }
            }
        }
    }
}
