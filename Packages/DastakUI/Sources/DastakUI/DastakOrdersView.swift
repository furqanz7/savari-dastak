import MapKit
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakOrdersView: View {
    @ObservedObject var model: DastakCustomerModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isLoadingOrders, model.isLoadingParcels, model.orders.isEmpty, model.parcels.isEmpty {
                ProgressView("Refreshing orders")
            } else if model.orders.isEmpty, model.parcels.isEmpty {
                if let failure = model.ordersAndParcelsRefreshFailure {
                    DastakEmptyState(
                        symbol: failure.symbol,
                        title: failure.title,
                        message: failure.message,
                        actionTitle: failure.actionTitle,
                        action: { Task { await model.refreshOrdersAndParcels() } }
                    )
                } else {
                    DastakEmptyState(
                        symbol: "clock",
                        title: "No orders yet",
                        message: "Your store orders and parcel deliveries will appear here."
                    )
                }
            } else {
                List {
                    if let failure = model.ordersAndParcelsRefreshFailure {
                        Section {
                            DastakRefreshNotice(
                                failure: failure,
                                action: { Task { await model.refreshOrdersAndParcels() } }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }

                    if !model.parcels.isEmpty {
                        Section("Parcel deliveries") {
                            ForEach(model.parcels, id: \.parcel.parcelID) { customerParcel in
                                NavigationLink {
                                    DastakParcelDetailView(
                                        customerParcel: customerParcel,
                                        pay: { await model.retryPayment(for: customerParcel) },
                                        cancel: { await model.cancel(customerParcel) }
                                    )
                                } label: {
                                    DastakParcelHistoryRow(customerParcel: customerParcel)
                                }
                            }
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
                                    cancel: { await model.cancel(order) },
                                    pay: { await model.retryPayment(for: order) }
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
        .refreshable {
            await model.refreshOrdersAndParcels()
        }
        .task {
            await model.refreshOrdersAndParcels()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, scenePhase == .active else { continue }
                await model.refreshOrdersAndParcels()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.refreshOrdersAndParcels()
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
    let customerParcel: CustomerParcelDelivery

    private var parcel: ParcelDelivery { customerParcel.parcel }

    var body: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(parcel.dropoff.address)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(customerParcel.audience == .sender ? "Sent" : "Incoming") · \(DastakFormatting.parcelStatus(parcel.status))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DastakFormatting.money(parcel.deliveryFee))
                .font(.subheadline.bold().monospacedDigit())
        }
    }
}

private struct DastakParcelDetailView: View {
    let customerParcel: CustomerParcelDelivery
    let pay: () async -> Void
    let cancel: () async -> Void

    @State private var mapPosition: MapCameraPosition
    @State private var isCancelling = false

    private var parcel: ParcelDelivery { customerParcel.parcel }

    init(
        customerParcel: CustomerParcelDelivery,
        pay: @escaping () async -> Void,
        cancel: @escaping () async -> Void
    ) {
        self.customerParcel = customerParcel
        self.pay = pay
        self.cancel = cancel
        let center = CLLocationCoordinate2D(
            latitude: (customerParcel.parcel.pickup.latitude + customerParcel.parcel.dropoff.latitude) / 2,
            longitude: (customerParcel.parcel.pickup.longitude + customerParcel.parcel.dropoff.longitude) / 2
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
                route
                payment
                if canPay {
                    Button {
                        Task { await pay() }
                    } label: {
                        Label("Pay securely", systemImage: "lock.fill")
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .padding(.horizontal, MarketplaceSpacing.medium)
                }
                if canCancel {
                    Button(role: .destructive) {
                        isCancelling = true
                        Task {
                            await cancel()
                            isCancelling = false
                        }
                    } label: {
                        isCancelling ? AnyView(ProgressView()) : AnyView(Text("Cancel delivery"))
                    }
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                    .disabled(isCancelling)
                    .padding(.horizontal, MarketplaceSpacing.medium)
                }
            }
            .padding(.bottom, MarketplaceSpacing.xLarge)
        }
        .navigationTitle("Parcel")
        .dastakInlineNavigationTitle()
    }

    private var map: some View {
        Map(position: $mapPosition) {
            Marker(
                "Pickup",
                systemImage: "shippingbox.fill",
                coordinate: CLLocationCoordinate2D(latitude: parcel.pickup.latitude, longitude: parcel.pickup.longitude)
            )
            .tint(MarketplaceColors.dastakAccent.color)
            Marker(
                "Drop-off",
                systemImage: "mappin.circle.fill",
                coordinate: CLLocationCoordinate2D(latitude: parcel.dropoff.latitude, longitude: parcel.dropoff.longitude)
            )
            .tint(.red)
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 260)
        .accessibilityLabel("Parcel route map")
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text(DastakFormatting.parcelStatus(parcel.status))
                .font(MarketplaceTypography.sectionTitle)
            Text(statusMessage)
                .foregroundStyle(.secondary)
            if let handoffCode = parcel.handoffCode {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(handoffCode.purpose == .pickup ? "Pickup code" : "Delivery code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(handoffCode.code)
                            .font(.title.bold().monospaced())
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

    private var route: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            Label("Pickup", systemImage: "shippingbox.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(parcel.pickup.address)
            Divider()
            Label("Drop-off", systemImage: "mappin.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(parcel.dropoff.address)
            Divider()
            Text(parcel.declaredContents)
                .font(.headline)
            Text(customerParcel.audience == .sender ? "Recipient: \(parcel.recipient.name)" : "You are receiving this parcel")
                .foregroundStyle(.secondary)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var payment: some View {
        VStack(spacing: MarketplaceSpacing.compact) {
            line("Delivery", parcel.deliveryFee)
            Divider()
            HStack {
                Text("Payment")
                Spacer()
                DastakStatusPill(
                    text: parcel.paymentStatus == .paid ? "Paid" : "Pending",
                    emphasis: parcel.paymentStatus == .paid
                )
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var canPay: Bool {
        customerParcel.audience == .sender && parcel.paymentStatus == .pending
    }

    private var canCancel: Bool {
        guard customerParcel.audience == .sender else { return false }
        return switch parcel.status {
        case .paymentPending, .paid, .assigned, .enRouteToPickup:
            true
        case .pickedUp, .inTransit, .delivered, .cancelled:
            false
        }
    }

    private var statusMessage: String {
        switch parcel.status {
        case .paymentPending: "Complete payment to request pickup."
        case .paid: "Finding a delivery partner."
        case .assigned: "A delivery partner has been assigned."
        case .enRouteToPickup: "Your delivery partner is heading to pickup."
        case .pickedUp, .inTransit: "Your parcel is on the way."
        case .delivered: "Your parcel was delivered."
        case .cancelled: "This parcel delivery was cancelled."
        }
    }

    private func line(_ title: String, _ value: Money) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(DastakFormatting.money(value)).monospacedDigit()
        }
    }
}

private struct DastakOrderDetailView: View {
    let order: MerchantOrderSnapshot
    let store: CatalogueStore?
    let cancel: () async -> Void
    let pay: () async -> Void

    @State private var mapPosition: MapCameraPosition
    @State private var isCancelling = false

    init(
        order: MerchantOrderSnapshot,
        store: CatalogueStore?,
        cancel: @escaping () async -> Void,
        pay: @escaping () async -> Void
    ) {
        self.order = order
        self.store = store
        self.cancel = cancel
        self.pay = pay
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
                if order.paymentState == .paymentPending {
                    payButton
                }
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

    private var payButton: some View {
        Button {
            Task { await pay() }
        } label: {
            Label("Pay securely", systemImage: "lock.fill")
        }
        .buttonStyle(MarketplacePrimaryButtonStyle())
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
