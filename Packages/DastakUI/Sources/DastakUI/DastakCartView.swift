import MarketplaceDesignSystem
import MarketplaceFoundation
import SwiftUI

struct DastakCartView: View {
    @ObservedObject var model: DastakCustomerModel
    let currentLocation: DastakDeliveryLocation?
    let requestCurrentLocation: () -> Void
    let orderSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeliveryAddressEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if model.cart.isEmpty {
                    DastakEmptyState(
                        symbol: "bag",
                        title: "Your basket is empty",
                        message: "Add food or products to continue."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: MarketplaceSpacing.large) {
                            securityPromise
                            items
                            totals
                            deliveryAddress
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
            .navigationTitle("Your basket")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !model.cart.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) { model.clearCart() }
                    }
                }
            }
        }
        .sheet(isPresented: $showingDeliveryAddressEditor) {
            DastakAddressBookView(
                model: model,
                requiresCompletion: true,
                currentLocation: currentLocation,
                requestCurrentLocation: requestCurrentLocation
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var securityPromise: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Matched before payment")
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
        VStack(spacing: 0) {
            if let restaurantName = model.cart.foodEntries.first?.restaurantName {
                cartGroupTitle(restaurantName)
            }
            ForEach(model.cart.foodEntries) { entry in
                HStack(spacing: MarketplaceSpacing.compact) {
                    DastakProductArtwork(symbol: "fork.knife").frame(width: 68)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.item.name).font(.headline).lineLimit(2)
                        Text(entry.optionNames.isEmpty ? "Restaurant item" : entry.optionNames.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Text(DastakFormatting.money(entry.subtotal)).font(.subheadline.monospacedDigit())
                    }
                    Spacer(minLength: 4)
                    DastakQuantityControl(
                        quantity: entry.quantity,
                        decrement: { model.decrementFoodCartItem(entry.id) },
                        increment: { model.incrementFoodCartItem(entry.id) }
                    )
                }
                .padding(MarketplaceSpacing.compact)
                Divider().padding(.leading, 92)
            }
            if !model.cart.entries.isEmpty, !model.cart.foodEntries.isEmpty {
                cartGroupTitle("Retail essentials")
            }
            ForEach(model.cart.entries) { entry in
                HStack(spacing: MarketplaceSpacing.compact) {
                    DastakProductArtwork(symbol: "basket")
                        .frame(width: 68)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.product.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(entry.product.packSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(DastakFormatting.money(entry.subtotal))
                            .font(.subheadline.monospacedDigit())
                    }

                    Spacer(minLength: 4)

                    DastakQuantityControl(
                        quantity: entry.quantity,
                        decrement: { model.decrementCartItem(entry.id) },
                        increment: { model.addToCart(entry.product) }
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
            totalRow("Basket subtotal", value: model.cart.subtotal, emphasized: true)
            Divider()
            Text("Delivery, platform fees and final total are shown only after the complete Food + Retail basket is secured.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        Button { showingDeliveryAddressEditor = true } label: {
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
            Button {
                guard model.hasCompleteDeliveryAddress else {
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
                        Text(model.hasCompleteDeliveryAddress ? "Place order" : "Add delivery address")
                        Spacer()
                        if model.hasCompleteDeliveryAddress { Image(systemName: "arrow.right") }
                    }
                }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(model.isSubmittingV1Order)
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
