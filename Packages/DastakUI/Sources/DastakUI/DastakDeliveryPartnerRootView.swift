import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

public struct DastakDeliveryPartnerRootView: View {
    @StateObject private var model: DastakDeliveryPartnerModel
    @StateObject private var locationManager = DastakLocationManager()
    @State private var handoffCode = ""

    public init(functions: any FunctionClient) {
        _model = StateObject(wrappedValue: DastakDeliveryPartnerModel(functions: functions))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    partnerHeader

                    if model.isLoading {
                        DastakLoadingOverlay(title: "Loading delivery queue")
                            .frame(maxWidth: .infinity)
                            .padding(.top, MarketplaceSpacing.xxLarge)
                    } else {
                        availability

                        if let currentJob = model.courierDispatch?.currentJob {
                            courierJob(currentJob)
                        }
                        if let currentJob = model.parcelDispatch?.currentJob {
                            parcelJob(currentJob)
                        }
                        if let offer = model.courierDispatch?.offer {
                            courierOffer(offer)
                        }
                        if let offer = model.parcelDispatch?.offer {
                            parcelOffer(offer)
                        }
                        if hasNoAssignment {
                            DastakEmptyState(
                                symbol: model.isOnline ? "dot.radiowaves.left.and.right" : "power",
                                title: model.isOnline ? "Waiting for assignments" : "You are offline",
                                message: model.isOnline
                                    ? "Ready merchant orders and parcels nearby will appear here."
                                    : "Go online when you are ready to deliver."
                            )
                            .frame(minHeight: 260)
                        }
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Delivery Partner")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(MarketplaceIconButtonStyle())
                    .disabled(model.isRefreshing || model.isBusy)
                    .accessibilityLabel("Refresh delivery queue")
                }
            }
        }
        .marketplacePage()
        .task {
            locationManager.requestLocation()
            await model.bootstrap()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await model.refresh()
            }
        }
        .alert(
            "Dastak",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var partnerHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                DastakWordmark(size: 30)
                Text(model.partner?.deliveryMethod.map(DastakPartnerFormatting.method) ?? "Delivery Partner")
                    .font(MarketplaceTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, MarketplaceSpacing.compact)
    }

    private var availability: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: model.isOnline ? "location.fill" : "location.slash")
                    .font(.title3)
                    .foregroundStyle(
                        model.isOnline
                            ? MarketplaceColors.success.color
                            : Color.secondary
                    )
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isOnline ? "Online" : "Offline")
                        .font(MarketplaceTypography.itemTitle)
                    Text(availabilityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "Online",
                    isOn: Binding(
                        get: { model.isOnline },
                        set: { online in
                            Task {
                                await model.setAvailability(
                                    online: online,
                                    location: locationManager.location
                                )
                            }
                        }
                    )
                )
                .labelsHidden()
                .tint(MarketplaceColors.success.color)
                .disabled(model.isBusy || (model.isOnline && model.hasActiveJob))
            }

            if model.isOnline {
                Label(
                    "Dastak automatically takes you offline after 15 minutes without activity.",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, MarketplaceSpacing.medium)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var availabilityMessage: String {
        if model.isOnline, let availableUntil = model.partner?.availability?.availableUntil {
            return "Available until \(DastakPartnerFormatting.time(availableUntil))"
        }
        return model.isOnline ? "Receiving nearby work" : "Not receiving assignments"
    }

    private var hasNoAssignment: Bool {
        model.courierDispatch?.offer == nil
            && model.courierDispatch?.currentJob == nil
            && model.parcelDispatch?.offer == nil
            && model.parcelDispatch?.currentJob == nil
    }

    private func courierOffer(_ offer: CourierAssignment) -> some View {
        DastakPartnerOfferCard(
            title: offer.store.name,
            subtitle: offer.store.address,
            symbol: "bag",
            payout: offer.courierPayout.paise,
            distanceMeters: offer.distanceMeters,
            respondBy: offer.respondBy,
            itemSummary: offer.items.map { "\($0.quantity) × \($0.name)" }.joined(separator: ", "),
            busy: model.isBusy,
            accept: {
                Task { await model.perform(.accept, assignment: offer) }
            },
            decline: {
                Task { await model.perform(.decline, assignment: offer) }
            }
        )
    }

    private func parcelOffer(_ offer: ParcelAssignment) -> some View {
        DastakPartnerOfferCard(
            title: "Parcel delivery",
            subtitle: offer.parcel.pickup.address,
            symbol: "shippingbox",
            payout: offer.parcel.courierPayout.paise,
            distanceMeters: offer.distanceMeters,
            respondBy: offer.respondBy,
            itemSummary: offer.parcel.declaredContents,
            busy: model.isBusy,
            accept: {
                Task { await model.perform(.accept, assignment: offer) }
            },
            decline: {
                Task { await model.perform(.decline, assignment: offer) }
            }
        )
    }

    private func courierJob(_ assignment: CourierAssignment) -> some View {
        DastakCourierJobView(
            assignment: assignment,
            handoffCode: $handoffCode,
            busy: model.isBusy
        ) { action, code in
            Task {
                await model.perform(action, assignment: assignment, verificationCode: code)
                handoffCode = ""
            }
        }
    }

    private func parcelJob(_ assignment: ParcelAssignment) -> some View {
        DastakParcelJobView(
            assignment: assignment,
            handoffCode: $handoffCode,
            busy: model.isBusy
        ) { action, code in
            Task {
                await model.perform(action, assignment: assignment, verificationCode: code)
                handoffCode = ""
            }
        }
    }
}

private struct DastakPartnerOfferCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let payout: Int
    let distanceMeters: Double
    let respondBy: String
    let itemSummary: String
    let busy: Bool
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 40, height: 40)
                    .background(MarketplaceColors.dastakAccentSoft.color)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MarketplaceMetrics.compactCornerRadius,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("New offer")
                        .font(.caption.bold())
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text(title)
                        .font(MarketplaceTypography.itemTitle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
                DastakOfferTimer(respondBy: respondBy)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You earn")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DastakFormatting.money(.init(paise: payout)))
                        .font(.title2.bold().monospacedDigit())
                }
                Spacer()
                Label(
                    DastakPartnerFormatting.distance(distanceMeters),
                    systemImage: "location"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Text(itemSummary)
                .font(.subheadline)
                .lineLimit(3)

            HStack(spacing: MarketplaceSpacing.compact) {
                Button("Decline", role: .destructive, action: decline)
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                Button("Accept", action: accept)
                    .buttonStyle(MarketplacePrimaryButtonStyle())
            }
            .disabled(busy)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }
}

private struct DastakOfferTimer: View {
    let respondBy: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(DastakPartnerFormatting.secondsRemaining(until: respondBy, now: context.date))s")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(MarketplaceColors.warning.color)
                .frame(minWidth: 38, minHeight: 30)
                .background(MarketplaceColors.warning.color.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}

private struct DastakCourierJobView: View {
    let assignment: CourierAssignment
    @Binding var handoffCode: String
    let busy: Bool
    let perform: (DastakCourierAction, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakPartnerJobHeader(
                title: "Active delivery",
                status: DastakPartnerFormatting.orderStatus(assignment.orderStatus),
                payout: assignment.courierPayout.paise
            )

            DastakPartnerStop(
                title: "Pickup",
                name: assignment.store.name,
                address: assignment.store.address,
                symbol: "storefront"
            )
            DastakPartnerStop(
                title: "Drop-off",
                name: "Customer",
                address: "Open the route for the exact destination.",
                symbol: "mappin"
            )

            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                ForEach(assignment.items, id: \.productID) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(item.quantity) ×")
                            .font(.subheadline.bold().monospacedDigit())
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text(item.unitLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, MarketplaceSpacing.small)

            DastakMapRouteButton(
                point: destination,
                label: headingToCustomer ? "Open drop-off route" : "Open pickup route"
            )

            if assignment.orderStatus == .returningToMerchant {
                Label(
                    "Return the items to the merchant. The merchant will close this delivery.",
                    systemImage: "arrow.uturn.backward"
                )
                .font(.subheadline)
                .foregroundStyle(MarketplaceColors.warning.color)
            }

            if let action {
                if action.codeLength > 0 {
                    DastakHandoffCodeField(
                        title: assignment.orderStatus == .atStore
                            ? "Merchant pickup code"
                            : "Customer delivery code",
                        length: action.codeLength,
                        code: $handoffCode
                    )
                }

                Button(action.title) {
                    perform(action.action, action.codeLength > 0 ? handoffCode : nil)
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
                .disabled(busy || (action.codeLength > 0 && handoffCode.count != action.codeLength))
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var headingToCustomer: Bool {
        assignment.orderStatus == .pickedUp || assignment.orderStatus == .inTransit
    }

    private var destination: GeoPoint {
        headingToCustomer ? assignment.dropoff : assignment.store.pickup
    }

    private var action: (action: DastakCourierAction, title: String, codeLength: Int)? {
        switch assignment.orderStatus {
        case .assigned: (.startToStore, "Start to store", 0)
        case .enRouteToPickup: (.arriveAtStore, "Arrived at store", 0)
        case .atStore: (.confirmPickup, "Confirm pickup", 4)
        case .pickedUp: (.startDelivery, "Start delivery", 0)
        case .inTransit: (.completeDelivery, "Complete delivery", 4)
        default: nil
        }
    }
}

private struct DastakParcelJobView: View {
    let assignment: ParcelAssignment
    @Binding var handoffCode: String
    let busy: Bool
    let perform: (DastakParcelPartnerAction, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakPartnerJobHeader(
                title: "Active parcel",
                status: DastakPartnerFormatting.parcelStatus(assignment.parcel.status),
                payout: assignment.parcel.courierPayout.paise
            )

            DastakPartnerStop(
                title: "Pickup",
                name: "Sender",
                address: assignment.parcel.pickup.address,
                symbol: "shippingbox"
            )
            DastakPartnerStop(
                title: "Drop-off",
                name: assignment.parcel.recipient.name,
                address: assignment.parcel.dropoff.address,
                symbol: "mappin"
            )

            LabeledContent("Contents", value: assignment.parcel.declaredContents)

            DastakMapRouteButton(
                point: destination,
                label: headingToRecipient ? "Open drop-off route" : "Open pickup route"
            )

            if let action {
                if action.codeLength > 0 {
                    DastakHandoffCodeField(
                        title: assignment.parcel.status == .enRouteToPickup
                            ? "Sender pickup code"
                            : "Recipient delivery code",
                        length: action.codeLength,
                        code: $handoffCode
                    )
                }

                Button(action.title) {
                    perform(action.action, action.codeLength > 0 ? handoffCode : nil)
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
                .disabled(busy || (action.codeLength > 0 && handoffCode.count != action.codeLength))
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var headingToRecipient: Bool {
        assignment.parcel.status == .pickedUp || assignment.parcel.status == .inTransit
    }

    private var destination: GeoPoint {
        let location = headingToRecipient ? assignment.parcel.dropoff : assignment.parcel.pickup
        return GeoPoint(latitude: location.latitude, longitude: location.longitude)
    }

    private var action: (action: DastakParcelPartnerAction, title: String, codeLength: Int)? {
        switch assignment.parcel.status {
        case .assigned: (.startToPickup, "Start to pickup", 0)
        case .enRouteToPickup: (.confirmPickup, "Confirm pickup", 6)
        case .pickedUp: (.startDelivery, "Start delivery", 0)
        case .inTransit: (.completeDelivery, "Complete delivery", 6)
        default: nil
        }
    }
}

private struct DastakPartnerJobHeader: View {
    let title: String
    let status: String
    let payout: Int

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(status)
                    .font(MarketplaceTypography.sectionTitle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Earnings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DastakFormatting.money(.init(paise: payout)))
                    .font(.headline.monospacedDigit())
            }
        }
    }
}

private struct DastakPartnerStop: View {
    let title: String
    let name: String
    let address: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .frame(width: 32, height: 32)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.subheadline.bold())
                Text(address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DastakMapRouteButton: View {
    let point: GeoPoint
    let label: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            guard let url = URL(
                string: "https://maps.apple.com/?daddr=\(point.latitude),\(point.longitude)&dirflg=d"
            ) else { return }
            openURL(url)
        } label: {
            Label(label, systemImage: "arrow.triangle.turn.up.right.diamond")
        }
        .buttonStyle(MarketplaceSecondaryButtonStyle())
    }
}

private struct DastakHandoffCodeField: View {
    let title: String
    let length: Int
    @Binding var code: String

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text(title)
                .font(.subheadline.bold())
            TextField(String(repeating: "0", count: length), text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(length))
                }
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
        }
    }
}

private enum DastakPartnerFormatting {
    static func method(_ method: DeliveryMethod) -> String {
        switch method {
        case .walking: "Walking"
        case .bicycle: "Bicycle"
        case .bike: "Bike"
        case .auto: "Auto"
        case .car: "Car"
        }
    }

    static func orderStatus(_ status: MerchantOrderStatus) -> String {
        switch status {
        case .paymentPending: "Payment pending"
        case .paid: "Paid"
        case .merchantAccepted: "Merchant accepted"
        case .ready: "Ready"
        case .assigned: "Assigned"
        case .enRouteToPickup: "Heading to store"
        case .atStore: "At store"
        case .pickedUp: "Picked up"
        case .inTransit: "On the way"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        case .returningToMerchant: "Return to merchant"
        }
    }

    static func parcelStatus(_ status: ParcelDeliveryStatus) -> String {
        switch status {
        case .paymentPending: "Payment pending"
        case .paid: "Paid"
        case .assigned: "Assigned"
        case .enRouteToPickup: "Heading to sender"
        case .pickedUp: "Picked up"
        case .inTransit: "On the way"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        }
    }

    static func distance(_ meters: Double) -> String {
        meters < 1_000
            ? "\(Int(meters.rounded())) m to pickup"
            : String(format: "%.1f km to pickup", meters / 1_000)
    }

    static func secondsRemaining(until value: String, now: Date) -> Int {
        guard let date = date(value) else { return 0 }
        return max(0, Int(ceil(date.timeIntervalSince(now))))
    }

    static func time(_ value: String) -> String {
        guard let date = date(value) else { return "soon" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
