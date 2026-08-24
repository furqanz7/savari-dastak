import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakWishlistView: View {
    @ObservedObject var model: DastakCustomerModel
    @State private var selectedRestaurant: DastakV1RestaurantMenu?

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
        .refreshable { await model.refreshWishlist() }
        .task {
            if model.wishlistItems.isEmpty { await model.refreshWishlist() }
        }
        .sheet(item: $selectedRestaurant) { restaurant in
            DastakRestaurantMenuView(model: model, restaurant: restaurant)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("SAVED FOR LATER")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Things worth remembering")
                .font(MarketplaceTypography.instrumentSerif(size: 40, relativeTo: .largeTitle))
            Text("Prices and availability always refresh from Dastak's current catalogue before you add anything.")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingWishlist, model.wishlistItems.isEmpty {
            ProgressView("Opening your Wishlist")
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if model.wishlistItems.isEmpty {
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
                Label(
                    "\(model.unresolvedWishlistItemCount) saved \(model.unresolvedWishlistItemCount == 1 ? "item is" : "items are") not available in your current area.",
                    systemImage: "location.slash"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(MarketplaceSpacing.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dastakAccountSurface()
            }
        }
    }

    private func wishlistSection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                Text(title).font(MarketplaceTypography.sectionTitle)
                Spacer()
                Text(count.formatted())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LazyVStack(spacing: MarketplaceSpacing.compact) { content() }
        }
    }

    private func retailRow(_ product: DastakV1CatalogueSKU) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            DastakProductArtwork(imageKey: product.imageKey)
                .frame(width: 82)
            VStack(alignment: .leading, spacing: 4) {
                if let brand = product.brand?.name {
                    Text(brand.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                Text(product.name).font(.headline).lineLimit(2)
                Text([product.variant, product.packSize].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(DastakFormatting.money(product.price))
                    .font(.subheadline.bold().monospacedDigit())
            }
            Spacer(minLength: 4)
            VStack(spacing: 5) {
                Button {
                    Task { await model.toggleWishlist(kind: .retailSKU, itemID: product.id) }
                } label: {
                    Image(systemName: "heart.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .disabled(model.wishlistUpdatingIDs.contains(product.id))
                .accessibilityLabel("Remove \(product.name) from Wishlist")

                Button { model.addToCart(product) } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(MarketplaceColors.primaryAction.color, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(product.name) to basket")
            }
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }

    private func menuRow(_ selection: DastakWishlistMenuSelection) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            DastakProductArtwork(imageKey: selection.item.imageKey, fallbackSymbol: "fork.knife")
                .frame(width: 82)
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.restaurant.restaurant.name.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(selection.item.name).font(.headline).lineLimit(2)
                Text(DastakFormatting.money(selection.item.basePrice))
                    .font(.subheadline.bold().monospacedDigit())
            }
            Spacer(minLength: 4)
            VStack(spacing: 5) {
                Button {
                    Task { await model.toggleWishlist(kind: .menuItem, itemID: selection.item.id) }
                } label: {
                    Image(systemName: "heart.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .disabled(model.wishlistUpdatingIDs.contains(selection.item.id))
                .accessibilityLabel("Remove \(selection.item.name) from Wishlist")

                Button {
                    if selection.item.optionGroups.isEmpty {
                        model.addFoodToCart(
                            restaurant: selection.restaurant,
                            item: selection.item,
                            optionIDs: []
                        )
                    } else {
                        selectedRestaurant = selection.restaurant
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
            }
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }
}

struct DastakPaymentSettingsView: View {
    @ObservedObject var model: DastakCustomerModel

    private var paidOrders: [DastakV1OrderSnapshot] {
        model.v1Orders.filter { $0.paidAt != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PAYMENTS")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text("Secure at checkout")
                        .font(MarketplaceTypography.instrumentSerif(size: 40, relativeTo: .largeTitle))
                    Text("Payment opens only after every item in your basket is secured.")
                        .font(MarketplaceTypography.supporting)
                        .foregroundStyle(.secondary)
                }

                paymentSecurityCard
                acceptedMethods
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
    }

    private var paymentSecurityCard: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(MarketplaceColors.dastakAccentDark.color)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text("Razorpay-secured checkout")
                    .font(.headline)
                    .foregroundStyle(MarketplaceColors.textPrimaryDark.color)
                Text("Dastak never stores your UPI PIN or bank credentials. Razorpay processes only the payment method you choose in Dastak.")
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
                paymentMethodRow("UPI apps & UPI ID", symbol: "arrow.up.right.circle")
                Divider().padding(.leading, 62)
                paymentMethodRow("Credit & debit cards", symbol: "creditcard")
                Divider().padding(.leading, 62)
                paymentMethodRow("Net banking", symbol: "building.columns")
                Divider().padding(.leading, 62)
                paymentMethodRow("Supported wallets / Pay Later", symbol: "wallet.pass")
            }
            .padding(.horizontal, MarketplaceSpacing.compact)
            .dastakAccountSurface()
            Text("Availability depends on Razorpay, your bank and your account at payment time.")
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
            Text("AT CHECKOUT")
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
                Text(paidOrders.count.formatted()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if paidOrders.isEmpty {
                DastakEmptyState(
                    symbol: "creditcard",
                    title: "No confirmed payments yet",
                    message: "Paid orders will appear here with their immutable total."
                )
                .frame(minHeight: 220)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(paidOrders.prefix(12).enumerated()), id: \.element.id) { index, order in
                        HStack(spacing: MarketplaceSpacing.compact) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(MarketplaceColors.success.color)
                                .frame(width: 42, height: 42)
                                .background(MarketplaceColors.success.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(order.displayOrderNumber).font(.subheadline.weight(.semibold))
                                if let date = DastakV1OrderPresentation.date(order.paidAt) {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(DastakFormatting.money(order.price.total))
                                .font(.subheadline.bold().monospacedDigit())
                        }
                        .frame(minHeight: 72)
                        if index < min(paidOrders.count, 12) - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .padding(.horizontal, MarketplaceSpacing.compact)
                .dastakAccountSurface()
            }
        }
    }
}
