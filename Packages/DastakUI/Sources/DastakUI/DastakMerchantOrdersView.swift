import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

enum DastakMerchantQueue: String, CaseIterable {
    case all = "All"
    case incoming = "New"
    case preparing = "Preparing"
    case ready = "Ready"
    case history = "History"

    static func isHistory(_ order: DastakV1MerchantFulfilment) -> Bool {
        order.status == "RELEASED" || [
            "DELIVERED", "CANCELLED", "CANCELLED_PREPAYMENT", "PAYMENT_EXPIRED",
            "UNAVAILABLE", "DELIVERY_FAILED", "RETURNED", "REFUNDED", "DASTAK_FULFILMENT_FAILURE"
        ].contains(order.orderStatus)
    }

    func includes(_ order: DastakV1MerchantFulfilment) -> Bool {
        if self == .history { return Self.isHistory(order) }
        guard !Self.isHistory(order) else { return false }
        switch self {
        case .all: return ["PREPARING", "READY", "PICKED_UP"].contains(order.status)
        case .preparing: return order.status == "PREPARING"
        case .ready: return order.status == "READY"
        default: return false
        }
    }
}

struct DastakMerchantOrdersView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var rejection: DastakOrderRejection?
    @State private var queue: DastakMerchantQueue = .all
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { MarketplaceColors.accent(for: colorScheme) }
    private var newOpportunities: [DastakV1MerchantOpportunity] {
        model.opportunities.filter { $0.status == "OFFERED" }
    }
    private var heldOpportunities: [DastakV1MerchantOpportunity] {
        model.opportunities.filter { $0.reservationState == "ITEMS_HELD_WHILE_ORDER_COMPLETES" }
    }
    private var foodRequests: [DastakV1RestaurantRequest] {
        model.restaurantRequests.filter { $0.status == "OFFERED" }
    }
    private var incomingCount: Int { newOpportunities.count + foodRequests.count }
    private var visibleFulfilments: [DastakV1MerchantFulfilment] {
        model.v1Fulfilments.filter { queue.includes($0) }
    }
    private var showsIncoming: Bool { queue == .all || queue == .incoming }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    if model.isLoading {
                        DastakLoadingOverlay(title: "Connecting your order desk")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        connectionStatus
                        summary
                        filters
                        if let notice = model.notice {
                            HStack(alignment: .top) {
                                Label(notice, systemImage: "checkmark.circle.fill")
                                    .font(.subheadline).foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                Button { model.notice = nil } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel("Dismiss confirmation")
                            }
                            .padding(14).marketplaceFlatSurface()
                        }
                        if showsIncoming { incomingSection }
                        if !visibleFulfilments.isEmpty {
                            sectionTitle(queue == .history ? "Order history" : "Your orders", count: visibleFulfilments.count)
                            ForEach(visibleFulfilments) { fulfilment in
                                DastakV1MerchantFulfilmentCard(
                                    fulfilment: fulfilment, busy: model.isBusy,
                                    declarePackages: { count in Task { await model.declareV1Packages(fulfilment, count: count) } },
                                    captureEvidence: { data, contentType, fileExtension in
                                        Task { await model.addV1ReadyEvidence(fulfilment, data: data, contentType: contentType, fileExtension: fileExtension) }
                                    },
                                    markReady: { Task { await model.markV1Ready(fulfilment) } },
                                    reportError: { model.errorMessage = $0 }
                                )
                            }
                        }
                        if queue == .all || queue == .history { legacyOrders }
                        if isEmpty {
                            DastakEmptyState(
                                symbol: queue == .history ? "clock.arrow.circlepath" : "tray",
                                title: queue == .history ? "No completed orders yet" : "You're all caught up",
                                message: model.orderRefreshFailures.isEmpty
                                    ? "New requests appear here automatically. Keep this workspace open while accepting orders."
                                    : "Some orders could not be refreshed. Retry before assuming the queue is empty."
                            ).frame(maxWidth: .infinity, minHeight: 210)
                        }
                        if queue == .history, let earnings = model.earnings {
                            DastakEarningsCard(earnings: earnings, title: "Earnings")
                        }
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                .padding(.horizontal, 18).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refreshAll() }
            .navigationTitle("Orders")
            .dastakInlineNavigationTitle()
        }
        .sheet(item: $rejection) { rejection in
            DastakRejectOrderSheet(order: rejection.order) { reason in
                Task { await model.perform(.reject, order: rejection.order, reason: reason) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ORDER DESK").font(.caption.weight(.bold)).tracking(2).foregroundStyle(accent)
            Text(model.canonicalCatalogue?.branch.branchName ?? model.store?.name
                 ?? model.restaurantRequests.first?.branch.displayName
                 ?? model.v1Fulfilments.first?.branch.displayName ?? "Your store")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
        }.padding(.top, 12)
    }

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.orderRefreshFailures.isEmpty {
                Label("Could not refresh: " + model.orderRefreshFailures.joined(separator: ", ") + ". Showing the last available information.",
                      systemImage: "wifi.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange)
                Button("Retry order connection") { Task { await model.refreshOrders() } }
                    .font(.subheadline.weight(.semibold))
            } else if let refreshed = model.lastOrderRefresh {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Updates automatically").font(.caption)
                    Spacer()
                    Text("Pull to refresh").font(.caption)
                }.foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Orders update automatically. Last updated \(refreshed, style: .relative). Pull down to refresh."))
            }
            DastakMerchantAlertStatus(notifications: model.notifications)
            if let branch = model.canonicalCatalogue?.branch,
               !branch.operationalState.isOpen || !branch.operationalState.acceptingOrders {
                Label("Your store is paused. Open Store to turn on order acceptance.", systemImage: "pause.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            metric(incomingCount, "New requests", "bell.badge", .incoming)
            Divider().frame(height: 36)
            metric(model.v1Fulfilments.filter { DastakMerchantQueue.preparing.includes($0) }.count, "Preparing", "timer", .preparing)
            Divider().frame(height: 36)
            metric(model.v1Fulfilments.filter { DastakMerchantQueue.ready.includes($0) }.count, "Ready", "shippingbox", .ready)
        }.padding(.vertical, 18).marketplaceFlatSurface()
    }

    private func metric(_ count: Int, _ title: String, _ symbol: String, _ target: DastakMerchantQueue) -> some View {
        Button { queue = target } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.subheadline).foregroundStyle(accent)
                Text(count.formatted()).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(count) \(title)")
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DastakMerchantQueue.allCases, id: \.self) { item in
                    Button { queue = item } label: {
                        Text(item.rawValue).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 17).padding(.vertical, 10)
                            .background(queue == item ? accent.opacity(0.18) : Color.secondary.opacity(0.07), in: Capsule())
                            .overlay(Capsule().strokeBorder(queue == item ? accent : .clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(queue == item ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private var incomingSection: some View {
        if incomingCount > 0 {
            sectionTitle("Needs your response", count: incomingCount)
            ForEach(newOpportunities) { opportunity in
                DastakMerchantIncomingCard(
                    number: opportunity.displayOrderNumber, branch: opportunity.branch.displayName,
                    lines: opportunity.lines, expiresAt: opportunity.expiresAt,
                    prepOptions: opportunity.prepTimeOptionsMinutes,
                    isFood: false, subset: opportunity.requestScope == "REQUESTED_SUBSET",
                    busy: model.isBusy, canRespond: !model.orderRefreshFailures.contains("Incoming orders")
                ) { accept, minutes, _ in
                    Task { await model.respondToOpportunity(opportunity, accept: accept, prepMinutes: minutes) }
                }.id("\(opportunity.id):\(opportunity.version)")
            }
            ForEach(foodRequests) { request in
                DastakMerchantIncomingCard(
                    number: request.displayOrderNumber, branch: request.branch.displayName,
                    lines: request.lines, expiresAt: nil, prepOptions: [10, 15, 20, 30, 45, 60, 90, 120, 180, 240],
                    isFood: true, subset: false, busy: model.isBusy,
                    canRespond: !model.orderRefreshFailures.contains("Food requests")
                ) { accept, minutes, reason in
                    Task { await model.respondToRestaurant(request, accept: accept, prepMinutes: minutes, reason: reason) }
                }.id("\(request.id):\(request.version)")
            }
        }
        ForEach(heldOpportunities) { opportunity in
            VStack(alignment: .leading, spacing: 8) {
                Label(opportunity.displayOrderNumber, systemImage: "hourglass")
                    .font(.headline)
                Text("Items held · Waiting for the remaining basket")
                    .font(.subheadline.weight(.semibold))
                Text("Keep these items available. Begin preparation once this order moves to Preparing.")
                    .font(.footnote).foregroundStyle(.secondary)
                DastakMerchantLineList(lines: opportunity.lines)
            }.padding(18).marketplaceFlatSurface()
        }
    }

    @ViewBuilder private var legacyOrders: some View {
        let orders = queue == .history ? model.recentOrders : model.activeOrders
        if !orders.isEmpty {
            sectionTitle("Earlier orders", count: orders.count)
            ForEach(orders, id: \.orderID) { order in
                DastakMerchantOrderCard(order: order, busy: model.isBusy) { action in
                    if action == .reject { rejection = DastakOrderRejection(order: order) }
                    else { Task { await model.perform(action, order: order) } }
                }
            }
        }
    }

    private var isEmpty: Bool {
        visibleFulfilments.isEmpty &&
        (!showsIncoming || (incomingCount == 0 && heldOpportunities.isEmpty)) &&
        (queue != .all || model.activeOrders.isEmpty) &&
        (queue != .history || model.recentOrders.isEmpty)
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(count.formatted()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

private struct DastakMerchantAlertStatus: View {
    @ObservedObject var notifications: DastakMerchantNotifications
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if notifications.needsAttention {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: notifications.needsSettings ? "bell.slash" : "bell.badge")
                    .font(.title3).foregroundStyle(MarketplaceColors.accent(for: colorScheme))
                VStack(alignment: .leading, spacing: 3) {
                    Text(notifications.title).font(.subheadline.weight(.semibold))
                    Text(notifications.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if notifications.isConnecting {
                    ProgressView().accessibilityLabel("Connecting order alerts")
                } else {
                    Button(notifications.actionTitle) { Task { await notifications.enable() } }
                        .font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
                }
            }.padding(14).marketplaceFlatSurface()
        }
    }
}

private struct DastakV1MerchantFulfilmentCard: View {
    let fulfilment: DastakV1MerchantFulfilment
    let busy: Bool
    let declarePackages: (Int) -> Void
    let captureEvidence: (Data, String, String) -> Void
    let markReady: () -> Void
    let reportError: (String) -> Void
    @State private var packageCount = 1
    @State private var evidenceItem: PhotosPickerItem?
    @State private var confirmReady = false
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { MarketplaceColors.accent(for: colorScheme) }
    private var isHistory: Bool { DastakMerchantQueue.isHistory(fulfilment) }

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: "bag.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(
                        cornerRadius: MarketplaceMetrics.compactCornerRadius,
                        style: .continuous
                    ))
                VStack(alignment: .leading, spacing: 3) {
                    Text(fulfilment.displayOrderNumber)
                        .font(.headline)
                    Text(fulfilment.branch.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DastakStatusPill(text: statusLabel, emphasis: !isHistory && fulfilment.status != "PICKED_UP")
            }

            if !isHistory && fulfilment.status == "PREPARING" {
                Label("Confirmed · You can start preparing", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }

            DastakMerchantLineList(lines: fulfilment.lines)
            .padding(.vertical, MarketplaceSpacing.compact)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }

            if let tracking = fulfilment.tracking {
                DastakDeliveryTrackingView(tracking: tracking)
            }

            if isHistory {
                Label("No preparation action needed", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if fulfilment.status == "PREPARING" {
                prepProgress
                preparationActions
            } else if fulfilment.status == "READY" {
                Label(
                    "Ready for the assigned delivery partner",
                    systemImage: "shippingbox.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MarketplaceColors.success.color)
            } else if fulfilment.status == "PICKED_UP" {
                Label(
                    "Packages handed to the delivery partner",
                    systemImage: "figure.walk.motion"
                )
                .font(.subheadline.weight(.semibold))
            }
            if !isHistory, let delivery = fulfilment.delivery {
                HStack(spacing: 12) {
                    Image(systemName: delivery.riderAssigned ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.clock")
                        .font(.title2).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(delivery.rider?.displayName ?? "Finding your delivery partner").font(.subheadline.weight(.semibold))
                        Text(delivery.stopStatus == "ARRIVED" ? "At your store · Ready for pickup" :
                            (delivery.riderAssigned ? "Assigned to collect this order" : "We'll update this card when a partner is assigned."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                if fulfilment.status == "READY", let code = delivery.pickupCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PICKUP CODE").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                        Text(code).font(.system(.largeTitle, design: .monospaced, weight: .bold)).tracking(5)
                        Text("Share only with the assigned partner after checking every package.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !isHistory {
                Text("Payment is collected at the customer's doorstep. No payment action is needed here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .onAppear { packageCount = max(fulfilment.packageCount ?? 1, 1) }
        .onChange(of: fulfilment.packageCount) { _, count in
            packageCount = max(count ?? 1, 1)
        }
        .accessibilityElement(children: .contain)
        .confirmationDialog("Mark this order ready for pickup?", isPresented: $confirmReady, titleVisibility: .visible) {
            Button("Yes, all packages are ready") { markReady() }
            Button("Keep preparing", role: .cancel) {}
        } message: {
            Text("Check all items, the package count, and the Ready photo. This step cannot be undone.")
        }
    }

    private var prepProgress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let late = DastakMerchantOrderClock.isExpired(fulfilment.estimatedReadyAt, now: context.date)
          HStack {
            Label(
                late ? "Preparation needs attention" : "Preparation time",
                systemImage: late ? "clock.badge.exclamationmark" : "clock"
            )
            .foregroundStyle(
                late
                    ? MarketplaceColors.warning.color
                    : MarketplaceColors.dastakAccent.color
            )
            Spacer()
            Text(late ? "Due now" : fulfilment.estimatedReadyAt.map { DastakMerchantOrderClock.remaining($0, now: context.date) } ?? prepTimeLabel)
                .font(.subheadline.bold().monospacedDigit())
        }
        .font(.subheadline.weight(.semibold))
        }
    }

    private var preparationActions: some View {
        VStack(spacing: MarketplaceSpacing.compact) {
            if fulfilment.canDeclarePackages {
                Stepper(value: $packageCount, in: 1 ... 20) {
                    Text("\(packageCount) sealed package\(packageCount == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                }
                Button(fulfilment.packageCount == nil ? "Confirm packages" : "Update packages") {
                    declarePackages(packageCount)
                }
                .buttonStyle(MarketplaceSecondaryButtonStyle())
                .disabled(busy)
            }

            if fulfilment.canAddEvidence {
                PhotosPicker(selection: $evidenceItem, matching: .images) {
                    Label(
                        fulfilment.evidence.isEmpty ? "Add Ready photo" : "Replace Ready photo",
                        systemImage: "camera.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MarketplaceSecondaryButtonStyle())
                .disabled(busy)
                .onChange(of: evidenceItem) { _, item in
                    guard let item else { return }
                    Task { await loadEvidence(item) }
                }
            }

            if !fulfilment.evidence.isEmpty {
                Label("Ready photo secured", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.success.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if fulfilment.canMarkReady {
                Button("Mark order Ready") { confirmReady = true }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy)
            } else {
                Label(
                    "Confirm package count and add a Ready photo to continue.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func loadEvidence(_ item: PhotosPickerItem) async {
        defer { evidenceItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  !data.isEmpty, data.count <= 10 * 1_024 * 1_024
            else {
                reportError("Choose a clear Ready photo up to 10 MB.")
                return
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let identifier = CGImageSourceGetType(source),
                  let type = UTType(identifier as String),
                  [UTType.png, .heic, .jpeg].contains(type)
            else {
                reportError("Choose a JPEG, PNG or HEIC photo.")
                return
            }
            let fileExtension = type == .png ? "png" : type == .heic ? "heic" : "jpg"
            captureEvidence(data, type.preferredMIMEType ?? "image/jpeg", fileExtension)
        } catch {
            reportError("The Ready photo could not be opened. Choose another photo.")
        }
    }

    private var statusLabel: String {
        if fulfilment.status == "RELEASED" { return "Released" }
        if isHistory {
            return fulfilment.orderStatus.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return switch fulfilment.status {
        case "PREPARING": "Preparing"
        case "READY": "Ready"
        case "PICKED_UP": "Picked up"
        default: fulfilment.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var prepTimeLabel: String {
        if fulfilment.runningLate { return "Due now" }
        let minutes = max(Int(ceil(Double(fulfilment.secondsRemaining) / 60)), 0)
        return minutes == 1 ? "1 min left" : "\(minutes) min left"
    }
}

private struct DastakOrderRejection: Identifiable {
    let order: MerchantOrderSnapshot
    var id: UUID { order.orderID }
}

private struct DastakMerchantOrderCard: View {
    let order: MerchantOrderSnapshot
    let busy: Bool
    let perform: (DastakMerchantOrderAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: "bag")
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
                    Text("Order \(order.orderID.uuidString.prefix(8).uppercased())")
                        .font(.headline)
                    Text(order.createdDate, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                DastakStatusPill(
                    text: DastakFormatting.orderStatus(order.status),
                    emphasis: !order.isCompleted
                )
            }

            if order.controlledCategory != nil {
                Label("Controlled order", systemImage: "checkmark.shield")
                    .font(.caption.bold())
                    .foregroundStyle(MarketplaceColors.warning.color)
            }

            VStack(spacing: MarketplaceSpacing.small) {
                ForEach(order.lines, id: \.productID) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(line.quantity) x")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name)
                                .font(.subheadline)
                            Text(line.unitLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(DastakFormatting.money(line.lineSubtotal))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
            .padding(.vertical, MarketplaceSpacing.compact)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }

            Grid(alignment: .leading, horizontalSpacing: MarketplaceSpacing.large) {
                GridRow {
                    Text("Items").foregroundStyle(.secondary)
                    Text(DastakFormatting.money(order.itemSubtotal))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                GridRow {
                    Text("Delivery · \(order.distanceLabel)")
                        .foregroundStyle(.secondary)
                    Text(DastakFormatting.money(order.deliveryFee))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider().gridCellColumns(2)
                GridRow {
                    Text("Total paid").bold()
                    Text(DastakFormatting.money(order.total))
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.subheadline)

            if order.handoffCode?.purpose == .pickup, let code = order.handoffCode?.code {
                HStack {
                    Label("Pickup code", systemImage: "number.square")
                    Spacer()
                    Text(code)
                        .font(.title3.bold().monospacedDigit())
                }
                .padding(MarketplaceSpacing.compact)
                .foregroundStyle(MarketplaceColors.success.color)
                .background(MarketplaceColors.success.color.opacity(0.1))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MarketplaceMetrics.compactCornerRadius,
                        style: .continuous
                    )
                )
            }

            if order.status == .returningToMerchant {
                Label(
                    "Confirm only after the delivery partner returns the items.",
                    systemImage: "arrow.uturn.backward"
                )
                .font(.subheadline)
                .foregroundStyle(MarketplaceColors.warning.color)
            }

            actions
                .disabled(busy)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    @ViewBuilder
    private var actions: some View {
        switch order.status {
        case .paid:
            HStack(spacing: MarketplaceSpacing.compact) {
                Button("Reject", role: .destructive) { perform(.reject) }
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                Button("Accept") { perform(.accept) }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
            }
        case .merchantAccepted:
            HStack(spacing: MarketplaceSpacing.compact) {
                Button("Reject", role: .destructive) { perform(.reject) }
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                Button("Mark ready") { perform(.ready) }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
            }
        case .ready:
            Button("Reject order", role: .destructive) { perform(.reject) }
                .buttonStyle(MarketplaceSecondaryButtonStyle())
        case .returningToMerchant:
            Button("Confirm items returned") { perform(.confirmReturn) }
                .buttonStyle(MarketplacePrimaryButtonStyle())
        case .cancelled where order.paymentState == .refundPending:
            Button("Process refund") { perform(.refund) }
                .buttonStyle(MarketplacePrimaryButtonStyle())
        default:
            EmptyView()
        }
    }
}

private struct DastakRejectOrderSheet: View {
    let order: MerchantOrderSnapshot
    let submit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Reason for rejection",
                        text: $reason,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                } footer: {
                    Text("For example, an item is unavailable.")
                }
            }
            .navigationTitle("Reject order")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep order") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reject", role: .destructive) {
                        submit(reason.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension MerchantOrderSnapshot {
    var createdDate: Date {
        ISO8601DateFormatter().date(from: createdAt) ?? .now
    }

    var distanceLabel: String {
        deliveryDistanceMeters < 1_000
            ? "\(deliveryDistanceMeters) m"
            : String(format: "%.1f km", Double(deliveryDistanceMeters) / 1_000)
    }

    var isCompleted: Bool {
        status == .cancelled || status == .delivered
    }
}
