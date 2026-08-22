import MapKit
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakOrdersView: View {
    @ObservedObject var model: DastakCustomerModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var scope: DastakOrderHistoryScope = .active
    @State private var showingV1Order = false

    var body: some View {
        Group {
            if model.isLoadingOrders, model.isLoadingParcels, model.orders.isEmpty,
               model.v1Orders.isEmpty, model.parcels.isEmpty {
                ProgressView("Refreshing orders")
            } else if model.orders.isEmpty, model.v1Orders.isEmpty, model.parcels.isEmpty {
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
                    Section {
                        Picker("Order history", selection: $scope) {
                            ForEach(DastakOrderHistoryScope.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(
                            top: MarketplaceSpacing.small,
                            leading: MarketplaceSpacing.medium,
                            bottom: MarketplaceSpacing.small,
                            trailing: MarketplaceSpacing.medium
                        ))
                        .listRowBackground(Color.clear)
                    }

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

                    if !filteredV1Orders.isEmpty {
                        Section("Dastak orders") {
                            ForEach(filteredV1Orders) { order in
                                Button {
                                    model.focusV1Order(order)
                                    showingV1Order = true
                                } label: {
                                    DastakV1OrderHistoryRow(order: order)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }

                    if !filteredParcels.isEmpty {
                        Section("Parcel deliveries") {
                            ForEach(filteredParcels, id: \.parcel.parcelID) { customerParcel in
                                NavigationLink(value: DastakCustomerDestination.parcel(customerParcel.parcel.parcelID)) {
                                    DastakParcelHistoryRow(customerParcel: customerParcel)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }

                    if !filteredOrders.isEmpty {
                        Section("Store orders") {
                        ForEach(filteredOrders, id: \.orderID) { order in
                            NavigationLink(value: DastakCustomerDestination.merchantOrder(order.orderID)) {
                                DastakOrderRow(order: order)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        }
                    }

                    if filteredV1Orders.isEmpty, filteredOrders.isEmpty, filteredParcels.isEmpty {
                        Section {
                            DastakEmptyState(
                                symbol: scope == .active ? "checkmark.circle" : "clock.arrow.circlepath",
                                title: scope == .active ? "Nothing active" : "No past orders",
                                message: scope == .active
                                    ? "New and ongoing orders will stay here until they are complete."
                                    : "Completed and cancelled orders will appear here."
                            )
                            .listRowBackground(Color.clear)
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
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.refreshOrdersAndParcels()
            }
        }
        .sheet(isPresented: $showingV1Order) {
            DastakV1MatchingView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var filteredV1Orders: [DastakV1OrderSnapshot] {
        model.v1Orders.filter { scope.includes(isActive: isActive($0.status)) }
    }

    private var filteredOrders: [MerchantOrderSnapshot] {
        model.orders.filter { scope.includes(isActive: isActive($0.status)) }
    }

    private var filteredParcels: [CustomerParcelDelivery] {
        model.parcels.filter { scope.includes(isActive: isActive($0.parcel.status)) }
    }

    private func isActive(_ status: MerchantOrderStatus) -> Bool {
        status != .delivered && status != .cancelled
    }

    private func isActive(_ status: ParcelDeliveryStatus) -> Bool {
        status != .delivered && status != .cancelled
    }

    private func isActive(_ status: DastakV1OrderStatus) -> Bool {
        ![.delivered, .unavailable, .paymentExpired, .cancelledPrepayment].contains(status)
    }
}

private struct DastakV1OrderHistoryRow: View {
    let order: DastakV1OrderSnapshot

    var body: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 42, height: 42)
                .background(
                    MarketplaceColors.dastakAccentSoft.color,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text("\(order.displayOrderNumber) · \(order.lines.count) products")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DastakFormatting.money(order.price.total))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, MarketplaceSpacing.small)
        .contentShape(Rectangle())
    }

    private var title: String {
        switch order.status {
        case .created, .matching: "Finding every item"
        case .fullySecured, .awaitingPayment: "Basket secured"
        case .paid, .preparing: "Preparing"
        case .pickupInProgress: "Pickup in progress"
        case .outForDelivery: "On the way"
        case .delivered: "Delivered"
        case .unavailable: "Basket unavailable"
        case .paymentExpired: "Payment expired"
        case .cancelledPrepayment: "Cancelled"
        case .fulfilmentFailure: "Needs attention"
        }
    }
}

private enum DastakOrderHistoryScope: String, CaseIterable, Identifiable {
    case active
    case past
    case all

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func includes(isActive: Bool) -> Bool {
        switch self {
        case .active: isActive
        case .past: !isActive
        case .all: true
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
            if let order = model.order(withID: orderID) {
                DastakOrderDetailView(
                    order: order,
                    store: model.catalogue?.stores.first { $0.storeID == order.storeID },
                    cancel: { reason in await model.cancel(order, reason: reason) },
                    pay: { await model.retryPayment(for: order) },
                    support: { category, message in
                        try await model.requestSupport(for: order, category: category, message: message)
                    }
                )
                .task { await model.refreshOrderDetail(orderID: orderID) }
            } else {
                missing(
                    title: "Loading order",
                    failure: model.orderDetailFailures[orderID],
                    loading: model.loadingOrderDetailIDs.contains(orderID),
                    action: { await model.refreshOrderDetail(orderID: orderID) }
                )
                .task { await model.refreshOrderDetail(orderID: orderID) }
            }
        case let .parcel(parcelID):
            if let parcel = model.customerParcel(withID: parcelID) {
                DastakParcelDetailView(
                    customerParcel: parcel,
                    pay: { await model.retryPayment(for: parcel) },
                    cancel: { reason in await model.cancel(parcel, reason: reason) },
                    support: { category, message in
                        try await model.requestSupport(for: parcel, category: category, message: message)
                    }
                )
                .task { await model.refreshParcelDetail(parcelID: parcelID) }
            } else {
                missing(
                    title: "Loading delivery",
                    failure: model.parcelDetailFailures[parcelID],
                    loading: model.loadingParcelDetailIDs.contains(parcelID),
                    action: {
                        await model.refreshParcels()
                        await model.refreshParcelDetail(parcelID: parcelID)
                    }
                )
                .task {
                    await model.refreshParcels()
                    await model.refreshParcelDetail(parcelID: parcelID)
                }
            }
        }
    }

    private func missing(
        title: String,
        failure: DastakCustomerRefreshFailure?,
        loading: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Group {
            if loading, failure == nil {
                ProgressView(title)
            } else {
                DastakEmptyState(
                    symbol: failure?.symbol ?? "arrow.clockwise",
                    title: failure?.title ?? title,
                    message: failure?.message ?? "Refresh to load the latest details.",
                    actionTitle: failure?.actionTitle ?? "Refresh",
                    action: { Task { await action() } }
                )
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
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
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
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }
}

private struct DastakParcelDetailView: View {
    let customerParcel: CustomerParcelDelivery
    let pay: () async -> Void
    let cancel: (String) async -> Void
    let support: (CustomerOrderSupportCategory, String) async throws -> CustomerOrderSupportCase

    @State private var mapPosition: MapCameraPosition
    @State private var isCancelling = false
    @State private var showingCancellationReasons = false
    @State private var showingSupport = false

    private var parcel: ParcelDelivery { customerParcel.parcel }

    init(
        customerParcel: CustomerParcelDelivery,
        pay: @escaping () async -> Void,
        cancel: @escaping (String) async -> Void,
        support: @escaping (CustomerOrderSupportCategory, String) async throws -> CustomerOrderSupportCase
    ) {
        self.customerParcel = customerParcel
        self.pay = pay
        self.cancel = cancel
        self.support = support
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
                DastakOrderSupportCard(
                    cases: parcel.supportCases ?? [],
                    action: { showingSupport = true }
                )
                .padding(.horizontal, MarketplaceSpacing.medium)
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
        .sheet(isPresented: $showingSupport) {
            DastakOrderSupportSheet(
                orderReference: parcel.parcelID.uuidString,
                submit: support
            )
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
        parcel.customerActions?.canPay ?? (presentation.primaryAction == .pay)
    }

    private var canCancel: Bool {
        guard customerParcel.audience == .sender else { return false }
        if let actions = parcel.customerActions {
            return actions.cancellationMode == .cancel
        }
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
    let support: (CustomerOrderSupportCategory, String) async throws -> CustomerOrderSupportCase

    @State private var mapPosition: MapCameraPosition
    @State private var isCancelling = false
    @State private var showingCancellationReasons = false
    @State private var showingSupport = false

    init(
        order: MerchantOrderSnapshot,
        store: CatalogueStore?,
        cancel: @escaping (String) async -> Void,
        pay: @escaping () async -> Void,
        support: @escaping (CustomerOrderSupportCategory, String) async throws -> CustomerOrderSupportCase
    ) {
        self.order = order
        self.store = store
        self.cancel = cancel
        self.pay = pay
        self.support = support
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
                DastakOrderSupportCard(
                    cases: order.supportCases ?? [],
                    action: { showingSupport = true }
                )
                .padding(.horizontal, MarketplaceSpacing.medium)
                if canPay {
                    payButton
                }
                if canCancel {
                    cancelButton
                }
                if order.customerActions?.cancellationMode == .pendingReview {
                    Label(
                        "Your cancellation is under review. We will update the refund here.",
                        systemImage: "clock.badge.checkmark"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(MarketplaceSpacing.medium)
                    .marketplaceFlatSurface()
                    .padding(.horizontal, MarketplaceSpacing.medium)
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
        .sheet(isPresented: $showingSupport) {
            DastakOrderSupportSheet(
                orderReference: order.orderID.uuidString,
                submit: support
            )
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
        if let mode = order.customerActions?.cancellationMode {
            return mode == .cancel || mode == .requestReview
        }
        switch order.status {
        case .paymentPending, .paid, .merchantAccepted, .ready, .assigned,
             .enRouteToPickup, .atStore, .pickedUp, .inTransit:
            return true
        case .delivered, .cancelled, .returningToMerchant:
            return false
        }
    }

    private var canPay: Bool {
        order.customerActions?.canPay ?? (order.paymentState == .paymentPending)
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

private struct DastakOrderSupportCard: View {
    let cases: [CustomerOrderSupportCase]
    let action: () -> Void

    private var latestCase: CustomerOrderSupportCase? {
        cases.first
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: latestCase == nil ? "questionmark.bubble" : "checkmark.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(latestCase == nil ? "Help with this order" : "Support · \(latestCase?.reference ?? "")")
                        .font(.headline)
                    Text(latestCase.map { $0.status.customerTitle }
                         ?? "Payments, refunds, items, cancellations or delivery")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .accessibilityHint("Opens order support")
    }
}

private struct DastakOrderSupportSheet: View {
    let orderReference: String
    let submit: (CustomerOrderSupportCategory, String) async throws -> CustomerOrderSupportCase

    @Environment(\.dismiss) private var dismiss
    @State private var category: CustomerOrderSupportCategory = .deliveryStatus
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var createdCase: CustomerOrderSupportCase?
    @State private var errorMessage: String?

    private var normalizedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    if let createdCase {
                        success(createdCase)
                    } else {
                        Text("Tell us what happened")
                            .font(MarketplaceTypography.sectionTitle)
                        Text("Your message is attached to order #\(orderReference.prefix(8).uppercased()).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                            Text("Topic")
                                .font(.headline)
                            Picker("Support topic", selection: $category) {
                                ForEach(CustomerOrderSupportCategory.allCases, id: \.self) { value in
                                    Text(value.customerTitle).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(MarketplaceColors.dastakAccent.color)
                        }

                        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                            Text("Details")
                                .font(.headline)
                            TextEditor(text: $message)
                                .frame(minHeight: 150)
                                .padding(MarketplaceSpacing.small)
                                .scrollContentBackground(.hidden)
                                .background(.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.primary.opacity(0.12), lineWidth: 1)
                                }
                                .accessibilityLabel("Describe the issue")
                            Text("Include what you expected and what happened. Do not share card or UPI credentials.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(MarketplaceSpacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Order support")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if createdCase == nil {
                    Button {
                        Task { await submitRequest() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Send request")
                        }
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(normalizedMessage.count < 10 || isSubmitting)
                    .padding(MarketplaceSpacing.medium)
                    .background(.bar)
                }
            }
        }
    }

    private func success(_ supportCase: CustomerOrderSupportCase) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(MarketplaceColors.success.color)
            Text("Request received")
                .font(MarketplaceTypography.sectionTitle)
            Text(supportCase.reference)
                .font(.headline.monospaced())
            Text("You can close this page. The current status will remain visible inside this order.")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(MarketplacePrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submitRequest() async {
        guard normalizedMessage.count >= 10, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            createdCase = try await submit(category, normalizedMessage)
        } catch {
            errorMessage = "Your request could not be sent. Please try again."
        }
    }
}

private extension CustomerOrderSupportCategory {
    var customerTitle: String {
        switch self {
        case .deliveryStatus: "Delivery status"
        case .merchantOrItems: "Store or items"
        case .payment: "Payment"
        case .refund: "Refund"
        case .cancellation: "Cancellation"
        case .safety: "Safety concern"
        case .other: "Something else"
        }
    }
}

private extension CustomerOrderSupportStatus {
    var customerTitle: String {
        switch self {
        case .open: "Request received"
        case .inReview: "Under review"
        case .resolved: "Resolved"
        case .closed: "Closed"
        }
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
