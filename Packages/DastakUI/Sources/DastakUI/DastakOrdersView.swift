import MapKit
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakOrdersView: View {
    @ObservedObject var model: DastakCustomerModel

    var body: some View {
        Group {
            if model.isLoadingOrders, model.orders.isEmpty {
                ProgressView("Refreshing orders")
            } else if model.orders.isEmpty, model.createdParcel == nil {
                DastakEmptyState(
                    symbol: "clock",
                    title: "No orders yet",
                    message: "Your store orders and parcel deliveries will appear here."
                )
            } else {
                List {
                    if let parcel = model.createdParcel {
                        Section("Parcel") {
                            DastakParcelHistoryRow(parcel: parcel)
                        }
                    }

                    Section("Store orders") {
                        ForEach(model.orders, id: \.orderID) { order in
                            NavigationLink {
                                DastakOrderDetailView(
                                    order: order,
                                    store: model.catalogue?.stores.first {
                                        $0.storeID == order.storeID
                                    },
                                    cancel: { await model.cancel(order) }
                                )
                            } label: {
                                DastakOrderRow(order: order)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Orders")
        .refreshable { await model.refreshOrders() }
        .task {
            await model.refreshOrders()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await model.refreshOrders()
            }
        }
    }
}

private struct DastakOrderRow: View {
    let order: MerchantOrderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            HStack {
                Text(order.lines.first?.name ?? "Store order")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(DastakFormatting.money(order.total))
                    .font(.subheadline.bold().monospacedDigit())
            }
            HStack {
                DastakStatusPill(
                    text: DastakFormatting.orderStatus(order.status),
                    emphasis: isActive(order.status)
                )
                Spacer()
                Text(order.orderID.uuidString.prefix(8).uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, MarketplaceSpacing.xSmall)
    }

    private func isActive(_ status: MerchantOrderStatus) -> Bool {
        status != .delivered && status != .cancelled
    }
}

private struct DastakParcelHistoryRow: View {
    let parcel: ParcelDelivery

    var body: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(parcel.dropoff.address)
                    .font(.headline)
                    .lineLimit(1)
                Text(DastakFormatting.parcelStatus(parcel.status))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DastakFormatting.money(parcel.deliveryFee))
                .font(.subheadline.bold().monospacedDigit())
        }
    }
}

private struct DastakOrderDetailView: View {
    let order: MerchantOrderSnapshot
    let store: CatalogueStore?
    let cancel: () async -> Void

    @State private var mapPosition: MapCameraPosition
    @State private var isCancelling = false

    init(
        order: MerchantOrderSnapshot,
        store: CatalogueStore?,
        cancel: @escaping () async -> Void
    ) {
        self.order = order
        self.store = store
        self.cancel = cancel
        let center = CLLocationCoordinate2D(
            latitude: order.dropoff.latitude,
            longitude: order.dropoff.longitude
        )
        _mapPosition = State(
            initialValue: .region(
                MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: 5_000,
                    longitudinalMeters: 5_000
                )
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                map
                status
                items
                payment
                if canCancel {
                    cancelButton
                }
            }
            .padding(.bottom, MarketplaceSpacing.xLarge)
        }
        .navigationTitle("Order")
        .dastakInlineNavigationTitle()
    }

    private var map: some View {
        Map(position: $mapPosition) {
            if let store {
                Marker(
                    store.name,
                    coordinate: CLLocationCoordinate2D(
                        latitude: store.location.latitude,
                        longitude: store.location.longitude
                    )
                )
                .tint(.orange)
            }
            Marker(
                "Delivery",
                systemImage: "house.fill",
                coordinate: CLLocationCoordinate2D(
                    latitude: order.dropoff.latitude,
                    longitude: order.dropoff.longitude
                )
            )
            .tint(MarketplaceColors.dastakAccent.color)
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 260)
        .accessibilityLabel("Order route map")
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text(DastakFormatting.orderStatus(order.status))
                .font(MarketplaceTypography.sectionTitle)
            Text(statusMessage)
                .foregroundStyle(.secondary)
            if let code = order.handoffCode {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(code.purpose == .pickup ? "Pickup code" : "Delivery code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(code.code)
                            .font(.title.bold().monospaced())
                            .accessibilityLabel("Handoff code \(code.code)")
                    }
                    Spacer()
                    Image(systemName: "number.square.fill")
                        .font(.title)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                .padding(MarketplaceSpacing.medium)
                .marketplaceFlatSurface()
            }
        }
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var items: some View {
        VStack(spacing: 0) {
            ForEach(order.lines, id: \.productID) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(line.quantity) x \(line.name)")
                    Spacer()
                    Text(DastakFormatting.money(line.lineSubtotal))
                        .monospacedDigit()
                }
                .padding(.vertical, MarketplaceSpacing.compact)
                if line.productID != order.lines.last?.productID {
                    Divider()
                }
            }
        }
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var payment: some View {
        VStack(spacing: MarketplaceSpacing.compact) {
            line("Items", order.itemSubtotal)
            line("Delivery", order.deliveryFee)
            Divider()
            line("Total", order.total, bold: true)
            HStack {
                Text("Payment")
                Spacer()
                DastakStatusPill(
                    text: order.paymentState == .paid ? "Paid" : "Pending",
                    emphasis: order.paymentState == .paid
                )
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var cancelButton: some View {
        Button(role: .destructive) {
            isCancelling = true
            Task {
                await cancel()
                isCancelling = false
            }
        } label: {
            if isCancelling {
                ProgressView()
            } else {
                Text("Cancel order")
            }
        }
        .buttonStyle(MarketplaceSecondaryButtonStyle())
        .disabled(isCancelling)
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private func line(_ title: String, _ value: Money, bold: Bool = false) -> some View {
        HStack {
            Text(title).fontWeight(bold ? .semibold : .regular)
            Spacer()
            Text(DastakFormatting.money(value))
                .fontWeight(bold ? .semibold : .regular)
                .monospacedDigit()
        }
    }

    private var canCancel: Bool {
        switch order.status {
        case .delivered, .cancelled, .pickedUp, .inTransit, .returningToMerchant:
            false
        default:
            true
        }
    }

    private var statusMessage: String {
        switch order.status {
        case .paymentPending: "Complete payment to send this order to the store."
        case .paid: "The store is reviewing your order."
        case .merchantAccepted: "The store is preparing your items."
        case .ready: "Your order is ready for collection."
        case .assigned: "A delivery partner has been assigned."
        case .enRouteToPickup: "Your delivery partner is heading to the store."
        case .atStore: "Your delivery partner has reached the store."
        case .pickedUp, .inTransit: "Your order is on the way."
        case .delivered: "Your order was delivered."
        case .cancelled: "This order was cancelled."
        case .returningToMerchant: "The order is being returned to the store."
        }
    }
}
