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
                                NavigationLink(value: DastakCustomerDestination.parcel(customerParcel.parcel.parcelID)) {
                                    DastakParcelHistoryRow(customerParcel: customerParcel)
                                }
                            }
                        }
                    }

                    Section("Store orders") {
                        ForEach(model.orders, id: \.orderID) { order in
                            NavigationLink(value: DastakCustomerDestination.merchantOrder(order.orderID)) {
                                DastakOrderRow(order: order)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Orders")
        .navigationDestination(for: DastakCustomerDestination.self) { destination in
            DastakCustomerDeliveryDestinationView(model: model, destination: destination)
        }
        .safeAreaInset(edge: .bottom, spacing: MarketplaceSpacing.small) {
            if let message = model.ordersActionMessage {
                DastakActionNotice(message: message) {
                    model.ordersActionMessage = nil
                }
                .padding(.horizontal, MarketplaceSpacing.medium)
            }
        }
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

private struct DastakCustomerDeliveryDestinationView: View {
    @ObservedObject var model: DastakCustomerModel
    let destination: DastakCustomerDestination

    @ViewBuilder
    var body: some View {
        switch destination {
        case let .merchantOrder(orderID):
            if let order = model.orders.first(where: { $0.orderID == orderID }) {
                DastakOrderDetailView(
                    order: order,
                    store: model.catalogue?.stores.first { $0.storeID == order.storeID },
                    cancel: { reason in await model.cancel(order, reason: reason) },
                    pay: { await model.retryPayment(for: order) }
                )
            } else {
                missing(title: "Order unavailable")
            }
        case let .parcel(parcelID):
            if let parcel = model.parcels.first(where: { $0.parcel.parcelID == parcelID }) {
                DastakParcelDetailView(
                    customerParcel: parcel,
                    pay: { await model.retryPayment(for: parcel) },
                    cancel: { reason in await model.cancel(parcel, reason: reason) }
                )
            } else {
                missing(title: "Delivery unavailable")
            }
        }
    }

    private func missing(title: String) -> some View {
        DastakEmptyState(
            symbol: "arrow.clockwise",
            title: title,
            message: "Refresh to load the latest details.",
            actionTitle: "Refresh",
            action: { Task { await model.refreshOrdersAndParcels() } }
        )
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
    let cancel: (String) async -> Void

    @State private var mapPosition: MapCameraPosition
    @State private var isCancelling = false
    @State private var showingCancellationReasons = false

    private var parcel: ParcelDelivery { customerParcel.parcel }

    init(
        customerParcel: CustomerParcelDelivery,
        pay: @escaping () async -> Void,
        cancel: @escaping (String) async -> Void
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
                if let courier = parcel.courier {
                    DastakCourierCard(courier: courier, destinationName: "recipient")
                        .padding(.horizontal, MarketplaceSpacing.medium)
                }
                route
                timeline
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
                        showingCancellationReasons = true
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
        .confirmationDialog(
            "Why are you cancelling?",
            isPresented: $showingCancellationReasons,
            titleVisibility: .visible
        ) {
            cancellationButton("Plans changed")
            cancellationButton("Pickup details changed")
            cancellationButton("Delivery is delayed")
        } message: {
            Text("Before pickup, an eligible captured payment is refunded to its original method.")
        }
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
            if let courierLocation = parcel.courier?.location {
                Annotation(
                    "Delivery partner",
                    coordinate: CLLocationCoordinate2D(
                        latitude: courierLocation.latitude,
                        longitude: courierLocation.longitude
                    )
                ) {
                    Image(systemName: "location.fill")
                        .padding(10)
                        .foregroundStyle(.black)
                        .background(MarketplaceColors.dastakAccent.color, in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 260)
        .accessibilityLabel("Parcel route map")
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text(presentation.title)
                .font(MarketplaceTypography.sectionTitle)
            Text(presentation.message)
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
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                Text("Receipt")
                    .font(.headline)
                Spacer()
                Text("#\(parcel.parcelID.uuidString.prefix(8).uppercased())")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Divider()
            line("Delivery", parcel.deliveryFee)
            Divider()
            HStack {
                Text("Payment")
                Spacer()
                DastakStatusPill(
                    text: DastakCustomerLifecycle.paymentTitle(parcel.paymentStatus),
                    emphasis: parcel.paymentStatus == .paid
                )
            }
            if parcel.paymentStatus == .refundPending || parcel.paymentStatus == .refunded {
                Text(parcel.paymentStatus == .refunded
                     ? "The refund was returned to the original payment method."
                     : "The refund is being processed to the original payment method.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var canPay: Bool {
        presentation.primaryAction == .pay
    }

    private var canCancel: Bool {
        guard customerParcel.audience == .sender else { return false }
        return switch parcel.status {
        case .paymentPending, .paid, .assigned, .enRouteToPickup: true
        case .pickedUp, .inTransit, .delivered, .cancelled: false
        }
    }

    private var presentation: DastakCustomerLifecyclePresentation {
        DastakCustomerLifecycle.parcel(
            status: parcel.status,
            paymentStatus: parcel.paymentStatus,
            audience: customerParcel.audience
        )
    }

    private var timeline: some View {
        DastakTimelineCard(steps: [
            ("Delivery created", parcel.timeline?.createdAt ?? parcel.createdAt),
            ("Payment confirmed", parcel.timeline?.paymentCapturedAt),
            ("Partner assigned", parcel.timeline?.assignedAt),
            ("Heading to pickup", parcel.timeline?.enRouteToPickupAt),
            ("Parcel collected", parcel.timeline?.pickedUpAt),
            ("On the way", parcel.timeline?.inTransitAt),
            ("Delivered", parcel.timeline?.deliveredAt),
            ("Cancelled", parcel.timeline?.cancelledAt),
        ])
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private func cancellationButton(_ reason: String) -> some View {
        Button(reason, role: .destructive) {
            isCancelling = true
            Task {
                await cancel(reason)
                isCancelling = false
            }
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
    let cancel: (String) async -> Void
    let pay: () async -> Void

    @State private var mapPosition: MapCameraPosition
    @State private var isCancelling = false
    @State private var showingCancellationReasons = false

    init(
        order: MerchantOrderSnapshot,
        store: CatalogueStore?,
        cancel: @escaping (String) async -> Void,
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
                if let courier = order.courier {
                    DastakCourierCard(courier: courier, destinationName: "delivery address")
                        .padding(.horizontal, MarketplaceSpacing.medium)
                }
                deliveryAddress
                items
                timeline
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
        .confirmationDialog(
            "Why are you cancelling?",
            isPresented: $showingCancellationReasons,
            titleVisibility: .visible
        ) {
            cancellationButton("Plans changed")
            cancellationButton("Ordered by mistake")
            cancellationButton("Delivery is delayed")
        } message: {
            Text(cancellationMessage)
        }
    }

    private var map: some View {
        Map(position: $mapPosition) {
            if let pickup = order.store?.pickup {
                Marker(
                    order.store?.name ?? "Store",
                    coordinate: CLLocationCoordinate2D(
                        latitude: pickup.latitude,
                        longitude: pickup.longitude
                    )
                )
                .tint(.orange)
            } else if let store {
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
            if let courierLocation = order.courier?.location {
                Annotation(
                    "Delivery partner",
                    coordinate: CLLocationCoordinate2D(
                        latitude: courierLocation.latitude,
                        longitude: courierLocation.longitude
                    )
                ) {
                    Image(systemName: "location.fill")
                        .padding(10)
                        .foregroundStyle(.black)
                        .background(MarketplaceColors.dastakAccent.color, in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 260)
        .accessibilityLabel("Order route map")
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text(presentation.title)
                .font(MarketplaceTypography.sectionTitle)
            Text(presentation.message)
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

    private var deliveryAddress: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Label("Deliver to", systemImage: "house.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(order.deliveryAddress?.label ?? "Delivery address")
                .font(.headline)
            if let displayAddress = order.deliveryAddress?.displayAddress {
                Text(displayAddress)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var timeline: some View {
        DastakTimelineCard(steps: [
            ("Order placed", order.timeline?.createdAt ?? order.createdAt),
            ("Store accepted", order.timeline?.acceptedAt),
            ("Ready", order.timeline?.readyAt),
            ("Partner assigned", order.timeline?.assignedAt),
            ("Heading to store", order.timeline?.enRouteToPickupAt),
            ("At the store", order.timeline?.atStoreAt),
            ("Collected", order.timeline?.pickedUpAt),
            ("On the way", order.timeline?.inTransitAt),
            ("Delivered", order.timeline?.deliveredAt),
            ("Cancelled", order.timeline?.cancelledAt),
        ])
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var payment: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                Text("Receipt")
                    .font(.headline)
                Spacer()
                Text("#\(order.orderID.uuidString.prefix(8).uppercased())")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let storeName = order.store?.name ?? store?.name {
                Text(storeName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider()
            line("Items", order.itemSubtotal)
            line("Delivery", order.deliveryFee)
            Divider()
            line("Total", order.total, bold: true)
            HStack {
                Text("Payment")
                Spacer()
                DastakStatusPill(
                    text: DastakCustomerLifecycle.paymentTitle(order.paymentState),
                    emphasis: order.paymentState == .paid
                )
            }
            if let decision = order.refundDecision {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(decision.decisionStatus == .reviewRequired
                         ? "Cancellation under review"
                         : DastakCustomerLifecycle.paymentTitle(order.paymentState))
                        .font(.subheadline.bold())
                    Text(decision.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let itemRefund = decision.itemRefund,
                       let deliveryRefund = decision.deliveryFeeRefund {
                        Text("Refund: \(DastakFormatting.money(Money(paise: itemRefund.paise + deliveryRefund.paise)))")
                            .font(.footnote.bold().monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .padding(.horizontal, MarketplaceSpacing.medium)
    }

    private var cancelButton: some View {
        Button(role: .destructive) {
            showingCancellationReasons = true
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
        case .paymentPending, .paid, .merchantAccepted, .ready, .assigned,
             .enRouteToPickup, .atStore, .pickedUp, .inTransit:
            true
        case .delivered, .cancelled, .returningToMerchant:
            false
        }
    }

    private var presentation: DastakCustomerLifecyclePresentation {
        DastakCustomerLifecycle.merchantOrder(
            status: order.status,
            paymentState: order.paymentState
        )
    }

    private var cancellationMessage: String {
        presentation.primaryAction == .requestCancellation
            ? "The order is already being fulfilled. Dastak will review the refundable amount."
            : "An eligible captured payment is refunded to its original method."
    }

    private func cancellationButton(_ reason: String) -> some View {
        Button(reason, role: .destructive) {
            isCancelling = true
            Task {
                await cancel(reason)
                isCancelling = false
            }
        }
    }
}

private struct DastakCourierCard: View {
    let courier: CustomerCourierSnapshot
    let destinationName: String

    var body: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: methodSymbol)
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .background(MarketplaceColors.dastakAccent.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(courier.displayName)
                    .font(.headline)
                Text(courier.location == nil
                     ? "Delivery partner assigned"
                     : "Live location updated on the map")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if let phoneURL {
                Link(destination: phoneURL) {
                    Image(systemName: "phone.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call delivery partner")
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Partner is travelling toward the \(destinationName)")
    }

    private var methodSymbol: String {
        switch courier.deliveryMethod {
        case .walking: "figure.walk"
        case .bicycle: "bicycle"
        case .bike: "motorcycle"
        case .auto, .car: "car.fill"
        }
    }

    private var phoneURL: URL? {
        let number = courier.phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard !number.isEmpty else { return nil }
        return URL(string: "tel:\(number)")
    }
}

private struct DastakTimelineCard: View {
    let steps: [(String, String?)]

    private var visibleSteps: [(String, String)] {
        steps.compactMap { title, timestamp in
            guard let timestamp else { return nil }
            return (title, timestamp)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Timeline")
                .font(.headline)
            ForEach(Array(visibleSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                    Image(systemName: index == visibleSteps.indices.last
                          ? "checkmark.circle.fill"
                          : "circle.fill")
                        .font(index == visibleSteps.indices.last ? .body : .system(size: 7))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.0)
                            .font(.subheadline.bold())
                        Text(DastakLifecycleDateFormatter.string(step.1))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }
}

private enum DastakLifecycleDateFormatter {
    static func string(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
