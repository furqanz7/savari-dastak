import MarketplaceDesignSystem
import MarketplaceFoundation
import SwiftUI

struct DastakCartView: View {
    @ObservedObject var model: DastakCustomerModel
    let currentLocation: DastakDeliveryLocation?
    let requestCurrentLocation: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingPaymentMethods = false
    @State private var showingDeliveryAddressEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if model.cart.entries.isEmpty {
                    DastakEmptyState(
                        symbol: "bag",
                        title: "Your basket is empty",
                        message: "Add products from one nearby store to continue."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: MarketplaceSpacing.large) {
                            items
                            totals
                            deliveryAddress
                            if let errorMessage = model.cartErrorMessage {
                                DastakActionNotice(message: errorMessage) {
                                    model.cartErrorMessage = nil
                                }
                            }
                        }
                        .padding(MarketplaceSpacing.medium)
                        .padding(.bottom, 100)
                    }
                    .safeAreaInset(edge: .bottom) {
                        checkoutButton
                    }
                }
            }
            .navigationTitle("Basket")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !model.cart.entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) {
                            model.clearCart()
                        }
                    }
                }
            }
            .task {
                if !model.cart.entries.isEmpty {
                    await model.prepareQuote()
                }
            }
            .onChange(of: model.deliveryAddress) { _, _ in
                guard !model.cart.entries.isEmpty else { return }
                Task { await model.prepareQuote() }
            }
        }
        .sheet(isPresented: $showingDeliveryAddressEditor) {
            DastakDeliveryAddressEditor(
                requiresCompletion: true,
                initialLocation: model.deliveryAddress ?? model.selectedLocation,
                currentLocation: currentLocation,
                requestCurrentLocation: requestCurrentLocation,
                save: { location in
                    await model.setLocation(location)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var items: some View {
        VStack(spacing: 0) {
            ForEach(model.cart.entries) { entry in
                HStack(spacing: MarketplaceSpacing.compact) {
                    DastakProductArtwork(kind: entry.product.catalogueKind)
                        .frame(width: 68)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.product.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(DastakFormatting.money(entry.subtotal))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    DastakQuantityControl(
                        quantity: entry.quantity,
                        decrement: {
                            model.cart.decrement(entry.product.productID)
                            Task { await model.prepareQuote() }
                        },
                        increment: {
                            _ = model.cart.add(entry.product)
                            Task { await model.prepareQuote() }
                        }
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
            totalRow("Items", value: model.quote?.itemSubtotal ?? model.cart.subtotal)
            if let deliveryFee = model.quote?.deliveryFee {
                totalRow("Delivery", value: deliveryFee)
            }
            Divider()
            totalRow(
                "Total",
                value: model.quote?.total ?? model.cart.subtotal,
                emphasized: true
            )
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var deliveryAddress: some View {
        Button {
            showingDeliveryAddressEditor = true
        } label: {
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
                            : "Add your house, flat or landmark before payment."
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

    private var checkoutButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if model.hasCompleteDeliveryAddress {
                    showingPaymentMethods = true
                } else {
                    showingDeliveryAddressEditor = true
                }
            } label: {
                if model.isCheckingOut {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack {
                        Text(model.hasCompleteDeliveryAddress ? "Continue to payment" : "Add delivery address")
                        Spacer()
                        if model.hasCompleteDeliveryAddress {
                            Text(DastakFormatting.money(model.quote?.total ?? model.cart.subtotal))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(model.isCheckingOut || (model.hasCompleteDeliveryAddress && model.quote == nil))
            .padding(MarketplaceSpacing.medium)
        }
        .background(.bar)
        .sheet(isPresented: $showingPaymentMethods) {
            DastakPaymentMethodView(model: model) {
                showingPaymentMethods = false
                Task {
                    if model.quote == nil { await model.prepareQuote() }
                    if await model.createOrderAndCheckout() != nil { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func totalRow(_ title: String, value: Money, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(emphasized ? .headline : .body)
            Spacer()
            Text(DastakFormatting.money(value))
                .font(emphasized ? .headline.monospacedDigit() : .body.monospacedDigit())
        }
    }
}
