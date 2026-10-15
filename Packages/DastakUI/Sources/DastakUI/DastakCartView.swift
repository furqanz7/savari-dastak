import MarketplaceDesignSystem
import MarketplaceFoundation
import SwiftUI

struct DastakCartView: View {
    @ObservedObject var model: DastakCustomerModel
    let currentLocation: DastakDeliveryLocation?
    let requestCurrentLocation: () -> Void
    let orderSubmitted: () -> Void
    var currentLocationError: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.marketplaceHapticScope) private var haptics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingDeliveryAddressEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if model.cart.isEmpty {
                    DastakEmptyState(
                        symbol: "bag",
                        title: "Your \(model.cartService.title) basket is empty",
                        message: model.checkoutRecoveryIssue ?? model.cartErrorMessage ?? "Add items to this basket to continue. Your other basket stays saved separately."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: MarketplaceSpacing.large) {
                            if let pending = model.pendingCheckout {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("A checkout needs recovery").font(.headline)
                                    Text("Recover this original checkout before changing this basket. This does not confirm or pay for the order.")
                                    Text("For \(pending.submission.recipient.name)")
                                    Text(DastakV1OrderPresentation.addressLine(pending.submission.deliveryAddress))
                                }
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(MarketplaceSpacing.medium)
                                .marketplaceFlatSurface()
                            }
                            items.disabled(!model.canEditCurrentCart)
                            totals
                            deliveryAddress
                            securityPromise
                            if let errorMessage = model.cartErrorMessage ?? model.v1OrderErrorMessage {
                                DastakActionNotice(message: errorMessage) {
                                    model.cartErrorMessage = nil
                                    model.v1OrderErrorMessage = nil
                                }
                            }
                        }
                        .padding(MarketplaceSpacing.medium)
                        .padding(.bottom, 108)
                    }
                    .safeAreaInset(edge: .bottom) { submitButton }
                }
            }
            .navigationTitle(dynamicTypeSize >= .xxxLarge ? "Basket" : "Your \(model.cartService.title) basket")
            .dastakInlineNavigationTitle()
            .task(id: model.checkoutRefreshKey) {
                repeat {
                    await model.refreshCheckoutEstimate()
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                } while !Task.isCancelled
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    Picker("Basket", selection: Binding(get: { model.cartService }, set: { service in
                        if model.cartService != service { haptics?.play(.selection) }
                        model.cartService = service
                    })) {
                        ForEach(DastakBasketService.allCases) { service in
                            Text("\(service.title) (\(model.baskets[service].itemCount))")
                                .tag(service)
                        }
                    }
                    .pickerStyle(.segmented)
                    if let issue = model.checkoutRecoveryIssue {
                        Text(issue).font(.footnote)
                        MarketplaceFeedbackButton("Retry loading saved checkout") {
                            Task { await model.restoreCartStorage(force: true) }
                        }
                        .disabled(model.isSubmittingV1Order)
                    }
                }
                .padding(MarketplaceSpacing.medium)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    MarketplaceFeedbackButton("Close") { dismiss() }
                }
                if !model.cart.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        MarketplaceFeedbackButton("Clear", role: .destructive) { model.clearCart() }
                            .disabled(!model.canEditCurrentCart)
                    }
                }
            }
        }
        .marketplacePage()
        .sheet(isPresented: $showingDeliveryAddressEditor) {
            DastakAddressBookView(
                model: model,
                requiresCompletion: true,
                currentLocation: currentLocation,
                requestCurrentLocation: requestCurrentLocation,
                currentLocationError: currentLocationError
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var securityPromise: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Matched before confirmation")
                    .font(.subheadline.weight(.semibold))
                Text("Dastak secures your complete basket first. You are not charged at submission.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }

    private var items: some View {
        let layout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: MarketplaceSpacing.compact))
            : AnyLayout(HStackLayout(spacing: MarketplaceSpacing.compact))
        return VStack(spacing: 0) {
            if let restaurantName = model.cart.foodEntries.first?.restaurantName {
                cartGroupTitle(restaurantName)
            }
            ForEach(model.cart.foodEntries) { entry in
                layout {
                    DastakProductArtwork(imageKey: entry.item.imageKey, fallbackSymbol: "fork.knife")
                        .frame(width: 68)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.item.name).font(.headline).lineLimit(dynamicTypeSize >= .xxxLarge ? nil : 2)
                        Text(entry.optionNames.isEmpty ? "Restaurant item" : entry.optionNames.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(dynamicTypeSize >= .xxxLarge ? nil : 2)
                        Text(DastakFormatting.money(entry.subtotal)).font(.subheadline.monospacedDigit())
                    }
                    if dynamicTypeSize < .xxxLarge { Spacer(minLength: 4) }
                    DastakQuantityControl(
                        quantity: entry.quantity,
                        decrement: { model.decrementFoodCartItem(entry.id) },
                        increment: { model.incrementFoodCartItem(entry.id) },
                        itemName: ([entry.item.name] + entry.optionNames).joined(separator: ", ")
                    )
                }
                .padding(MarketplaceSpacing.compact)
                Divider().padding(.leading, 92)
            }
            ForEach(model.cart.entries) { entry in
                layout {
                    DastakProductArtwork(imageKey: entry.product.imageKey, fallbackSymbol: "basket")
                        .frame(width: 68)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.product.name)
                            .font(.headline)
                            .lineLimit(dynamicTypeSize >= .xxxLarge ? nil : 2)
                        Text(entry.product.packSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(DastakFormatting.money(entry.subtotal))
                            .font(.subheadline.monospacedDigit())
                    }

                    if dynamicTypeSize < .xxxLarge { Spacer(minLength: 4) }

                    DastakQuantityControl(
                        quantity: entry.quantity,
                        decrement: { model.decrementCartItem(entry.id) },
                        increment: { model.addToCart(entry.product) },
                        itemName: "\(entry.product.name), \(entry.product.packSize)"
                    )
                }
                .padding(MarketplaceSpacing.compact)

                if entry.id != model.cart.entries.last?.id {
                    Divider().padding(.leading, 92)
                }
            }
        }
        .marketplaceFlatSurface()
    }

    private var totals: some View {
        VStack(spacing: MarketplaceSpacing.compact) {
            if model.currentCheckoutEstimate == nil {
                totalRow("Basket subtotal", value: model.cart.subtotal, emphasized: true)
                Divider()
            }
            if let estimate = model.currentCheckoutEstimate {
                totalRow("Items", value: Money(paise: estimate.subtotalPaise))
                totalRow("Delivery", value: Money(paise: estimate.deliveryFeePaise))
                totalRow("Platform fee", value: Money(paise: estimate.platformFeePaise))
                totalRow("Estimated total", value: Money(paise: estimate.totalPaise), emphasized: true)
                Text("Tax is included").font(.footnote).foregroundStyle(.secondary)
                Text("Final total is confirmed after your basket is secured.").font(.footnote).foregroundStyle(.secondary)
            } else if model.pendingCheckout == nil && model.requiresAreaChecks {
                if model.isLoadingCheckoutEstimate { ProgressView("Checking checkout fees…") }
                Text(model.checkoutAvailabilityIssue ?? "Check checkout fees before placing your order.")
                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                MarketplaceFeedbackButton("Refresh availability and fees") {
                    Task {
                        await model.refreshAreaAvailability(force: true)
                        await model.refreshCheckoutEstimate()
                    }
                }.disabled(model.isLoadingCheckoutEstimate)
            } else {
                Text("Food and Grocery are ordered separately.").font(.footnote).foregroundStyle(.secondary)
            }
            if model.currentCheckoutEstimate != nil, let issue = model.checkoutAvailabilityIssue {
                Text(issue).font(.footnote)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private func cartGroupTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(MarketplaceColors.dastakAccent.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.compact)
            .padding(.top, MarketplaceSpacing.compact)
    }

    private var deliveryAddress: some View {
        MarketplaceFeedbackButton { showingDeliveryAddressEditor = true } label: {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: "location.fill")
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.hasCompleteDeliveryAddress ? "Deliver to" : "Add delivery address")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(
                        model.hasCompleteDeliveryAddress
                            ? model.deliveryAddress?.displayAddress ?? ""
                            : "Add doorstep details before placing your order."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(MarketplaceSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marketplaceFlatSurface()
    }

    private var submitButton: some View {
        VStack(spacing: 0) {
            Divider()
            MarketplaceFeedbackButton {
                guard model.pendingCheckout != nil || model.hasCompleteDeliveryAddress else {
                    showingDeliveryAddressEditor = true
                    return
                }
                Task {
                    if await model.submitV1Order() {
                        dismiss()
                        try? await Task.sleep(for: .milliseconds(350))
                        orderSubmitted()
                    }
                }
            } label: {
                if model.isSubmittingV1Order {
                    ProgressView().tint(.white)
                } else {
                    HStack {
                        Text(model.pendingCheckout != nil ? "Recover \(model.cartService.title) checkout" : model.hasCompleteDeliveryAddress ? "Place order" : "Add delivery address")
                        Spacer()
                        if model.hasCompleteDeliveryAddress { Image(systemName: "arrow.right") }
                    }
                }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(model.isSubmittingV1Order || !model.isCartStorageReady
                || (model.pendingCheckout == nil && model.hasCompleteDeliveryAddress && model.checkoutAvailabilityIssue != nil))
            .padding(MarketplaceSpacing.medium)
        }
        .background(.bar)
    }

    private func totalRow(_ title: String, value: Money, emphasized: Bool = false) -> some View {
        HStack {
            Text(title).font(emphasized ? .headline : .body)
            Spacer()
            Text(DastakFormatting.money(value))
                .font(emphasized ? .headline.monospacedDigit() : .body.monospacedDigit())
        }
    }
}
