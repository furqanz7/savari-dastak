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
    case returns = "Returns"
    case settlements = "Settlements"
    case history = "History"

    static func isHistory(_ order: DastakV1MerchantFulfilment) -> Bool {
        DastakMerchantHistoryPage.isHistorical(order)
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
    @State private var detail: DastakMerchantDetailTarget?
    @Binding var queue: DastakMerchantQueue
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { MarketplaceColors.accent(for: colorScheme) }
    private var newOpportunities: [DastakV1MerchantOpportunity] {
        model.scopedOpportunities.filter { $0.status == "OFFERED" }
    }
    private var heldOpportunities: [DastakV1MerchantOpportunity] {
        model.scopedOpportunities.filter { $0.reservationState == "ITEMS_HELD_WHILE_ORDER_COMPLETES" }
    }
    private var foodRequests: [DastakV1RestaurantRequest] {
        model.scopedRestaurantRequests.filter { $0.status == "OFFERED" }
    }
    private var incomingCount: Int { newOpportunities.count + foodRequests.count + model.scopedRecoveryOpportunities.filter { $0.status == "OFFERED" }.count }
    private var visibleFulfilments: [DastakV1MerchantFulfilment] {
        queue == .history ? [] : model.scopedFulfilments.filter { queue.includes($0) }
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
                        if queue == .history {
                            Text("Fulfilment history is paged separately below. Earlier legacy orders remain a recent window of up to 10 records, not lifetime history.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let branch = model.selectedLocationID {
                                DastakMerchantHistorySection(merchant: model, branch: branch).id(branch)
                            } else { Text("Choose a location to load its history.").foregroundStyle(.secondary) }
                        }
                        DastakMerchantRecoveryStatus(model: model)
                        if let notice = model.notice {
                            HStack(alignment: .top) {
                                Label(notice, systemImage: "checkmark.circle.fill")
                                    .font(.subheadline).foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                Button { model.notice = nil } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }
                                    .accessibilityLabel("Dismiss confirmation")
                            }
                            .padding(14).marketplaceFlatSurface()
                        }
                        if showsIncoming { incomingSection }
                        if showsIncoming || queue == .history {
                            DastakMerchantRecoveryLane(model: model, history: queue == .history)
                        }
                        if queue == .returns || queue == .all || queue == .history {
                            DastakMerchantReturnsView(model: model, history: queue == .history,
                                showAll: queue == .returns)
                        }
                        if queue == .settlements { DastakMerchantSettlementsView(model: model) }
                        if !visibleFulfilments.isEmpty {
                            sectionTitle(queue == .history ? "Order history" : "Your orders", count: visibleFulfilments.count)
                            ForEach(visibleFulfilments) { fulfilment in
                                DastakV1MerchantFulfilmentCard(
                                    fulfilment: fulfilment, busy: model.isBusy || !model.fulfilmentsCurrent || model.recoveryBlocks(fulfilment),
                                    declarePackages: { count in Task { await model.declareV1Packages(fulfilment, count: count) } },
                                    captureEvidence: { data, contentType, fileExtension in
                                        Task { await model.addV1ReadyEvidence(fulfilment, data: data, contentType: contentType, fileExtension: fileExtension) }
                                    },
                                    markReady: { Task { await model.markV1Ready(fulfilment) } },
                                    reportError: { model.errorMessage = $0 },
                                    openDetail: { detail = .init(kind: .fulfilment, id: fulfilment.id, branchID: fulfilment.branch.id) }
                                )
                                DastakMerchantProblemView(model: model, fulfilment: fulfilment)
                                    .id("problem:\(fulfilment.id)")
                            }
                        }
                        if queue == .all || queue == .history { legacyOrders }
                        if isEmpty && queue != .history {
                            DastakEmptyState(
                                symbol: queue == .history ? "clock.arrow.circlepath" : "tray",
                                title: model.selectedLocationID == nil ? "Location needed"
                                    : !model.orderRefreshFailures.isEmpty ? "Order connection needs attention"
                                    : queue == .history ? "No completed orders in this window" : "You're all caught up",
                                message: model.selectedLocationID == nil
                                    ? model.locationMessage ?? "Check or choose your store location above to see its order desk."
                                    : model.orderRefreshFailures.isEmpty
                                    ? "New requests appear here automatically. Keep this workspace open while accepting orders."
                                    : "Some orders could not be refreshed. Retry before assuming the queue is empty."
                            ).frame(maxWidth: .infinity, minHeight: 210)
                        }
                        if queue == .history, let earnings = model.earnings {
                            DastakEarningsCard(earnings: earnings, title: "Earlier order totals")
                            Text("These older order totals are separate from the business Royalty ledger in Earnings.").font(.caption).foregroundStyle(.secondary)
                        }
                        if queue == .history, let failure = model.earningsRefreshFailure {
                            Text(failure).font(.footnote).foregroundStyle(.secondary)
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
            .modifier(DastakMerchantKeyboardDismiss())
        }
        .sheet(item: $rejection) { rejection in
            DastakRejectOrderSheet(order: rejection.order) { reason in
                Task { await model.perform(.reject, order: rejection.order, reason: reason) }
            }
        }
        .sheet(item: $detail) { target in DastakMerchantOrderDetailView(model: model.makeOrderDetail(target)) }
        .onChange(of: model.selectedLocationID) { _, _ in detail = nil }
    }

    private var header: some View {
        DastakMerchantHeading(eyebrow: "THE ORDER DESK", title: "Good things, in motion.",
            subtitle: "From the first request to the final handoff. Your next steps, all in one place.", symbol: "storefront")
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
                DastakMerchantAdaptiveRow {
                  HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Updates automatically").font(.caption)
                  }
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
        DastakMerchantDeskOverview(incoming: incomingCount,
            preparing: model.scopedFulfilments.filter { DastakMerchantQueue.preparing.includes($0) }.count,
            ready: model.scopedFulfilments.filter { DastakMerchantQueue.ready.includes($0) }.count, selection: $queue)
    }

    private var filters: some View {
        DastakMerchantQueuePicker(selection: $queue)
    }

    @ViewBuilder private var incomingSection: some View {
        if newOpportunities.count + foodRequests.count > 0 {
            sectionTitle("Needs your response", count: newOpportunities.count + foodRequests.count)
            ForEach(newOpportunities) { opportunity in
                DastakMerchantIncomingCard(
                    number: opportunity.displayOrderNumber, branch: opportunity.branch.displayName,
                    lines: opportunity.lines, productSubtotalPaise: opportunity.productSubtotalPaise,
                    expiresAt: opportunity.expiresAt,
                    prepOptions: opportunity.prepTimeOptionsMinutes,
                    isFood: false, subset: opportunity.requestScope == "REQUESTED_SUBSET",
                    busy: model.isBusy, canRespond: model.incomingCurrent, revision: opportunity.version,
                    openDetail: { detail = .init(kind: .opportunity, id: opportunity.id, branchID: opportunity.branch.id) }
                ) { accept, minutes, _ in
                    Task { await model.respondToOpportunity(opportunity, accept: accept, prepMinutes: minutes) }
                }
            }
            ForEach(foodRequests) { request in
                DastakMerchantIncomingCard(
                    number: request.displayOrderNumber, branch: request.branch.displayName,
                    lines: request.lines, productSubtotalPaise: request.productSubtotalPaise,
                    expiresAt: nil, prepOptions: [10, 15, 20, 30, 45, 60, 90, 120, 180, 240],
                    isFood: true, subset: false, busy: model.isBusy,
                    canRespond: model.foodRequestsCurrent, revision: request.version,
                    openDetail: { detail = .init(kind: .restaurantRequest, id: request.id, branchID: request.branch.id) }
                ) { accept, minutes, reason in
                    Task { await model.respondToRestaurant(request, accept: accept, prepMinutes: minutes, reason: reason) }
                }
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
                if let productSubtotalPaise = opportunity.productSubtotalPaise {
                    HStack {
                        Text("Product value").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(DastakFormatting.money(Money(paise: productSubtotalPaise)))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
            }.padding(18).marketplaceFlatSurface()
            DastakMerchantOrderDetailButton(model: model,
                target: .init(kind: .opportunity, id: opportunity.id, branchID: opportunity.branch.id))
        }
    }

    @ViewBuilder private var legacyOrders: some View {
        let orders = queue == .history ? model.recentOrders : model.activeOrders
        if !orders.isEmpty {
            sectionTitle("Earlier account-wide orders", count: orders.count)
            ForEach(orders, id: \.orderID) { order in
                DastakMerchantOrderCard(order: order, busy: model.isBusy || !model.legacyOrdersCurrent) { action in
                    if action == .reject { rejection = DastakOrderRejection(order: order) }
                    else { Task { await model.perform(action, order: order) } }
                }
            }
        }
    }

    private var isEmpty: Bool {
        queue != .returns && queue != .settlements && visibleFulfilments.isEmpty &&
        (!showsIncoming || (incomingCount == 0 && heldOpportunities.isEmpty)) &&
        (queue != .all || model.activeOrders.isEmpty) &&
        (queue != .history || model.recentOrders.isEmpty)
        && (queue != .history || model.scopedRecoveryOpportunities.allSatisfy { $0.status == "OFFERED" })
        && (queue != .history || model.scopedReturnReceipts.allSatisfy { $0.status != "COMPLETED" })
        && (queue != .all || model.scopedReturnReceipts.allSatisfy { $0.status == "COMPLETED" })
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
            DastakMerchantAdaptiveRow {
              HStack(alignment: .top, spacing: 12) {
                Image(systemName: notifications.needsSettings ? "bell.slash" : "bell.badge")
                    .font(.title3).foregroundStyle(MarketplaceColors.accent(for: colorScheme))
                VStack(alignment: .leading, spacing: 3) {
                    Text(notifications.title).font(.subheadline.weight(.semibold))
                    Text(notifications.detail).font(.caption).foregroundStyle(.secondary)
                }
              }
                if notifications.isConnecting {
                    ProgressView().accessibilityLabel("Connecting order alerts")
                } else {
                    Button(notifications.actionTitle) { Task { await notifications.enable() } }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44).buttonStyle(.bordered)
                }
            }.padding(14).marketplaceFlatSurface()
        }
    }
}

struct DastakV1MerchantFulfilmentCard: View {
    let fulfilment: DastakV1MerchantFulfilment
    let busy: Bool
    let declarePackages: (Int) -> Void
    let captureEvidence: (Data, String, String) -> Void
    let markReady: () -> Void
    let reportError: (String) -> Void
    var openDetail: (() -> Void)? = nil
    @State private var packageText = "1"
    @State private var evidenceItem: PhotosPickerItem?
    @State private var evidenceLoading = false
    @State private var evidenceFailure: String?
    @State private var evidenceGeneration = UUID()
    @State private var confirmReady = false
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { MarketplaceColors.accent(for: colorScheme) }
    private var isHistory: Bool { DastakMerchantQueue.isHistory(fulfilment) }

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakMerchantAdaptiveRow {
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
              }.frame(maxWidth: .infinity, alignment: .leading)
                DastakStatusPill(text: statusLabel, emphasis: !isHistory && fulfilment.status != "PICKED_UP")
            }

            if !isHistory, let code = fulfilment.delivery?.pickupCode {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                    Label("PICKUP CODE", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.bold)).tracking(1)
                        .foregroundStyle(accent)
                    Text(code)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit().tracking(4)
                    Text("Share only with the assigned delivery partner after checking every package.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MarketplaceSpacing.medium)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pickup code \(code). Share only after checking every package.")
            }

            if !isHistory && fulfilment.status == "PREPARING" {
                Label("Confirmed · You can start preparing", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }

            DastakMerchantLineSummary(lines: fulfilment.lines)
            .padding(.vertical, MarketplaceSpacing.compact)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }

            if let productSubtotalPaise = fulfilment.productSubtotalPaise {
                DastakMerchantValueRow(title: "Product value", value: DastakFormatting.money(Money(paise: productSubtotalPaise)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Product value \(DastakFormatting.money(Money(paise: productSubtotalPaise))). Delivery and platform fees are not shown to the merchant.")
            }

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
            }
            if !isHistory {
                Text("Payment is collected at the customer's doorstep. No payment action is needed here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let openDetail { Divider(); DastakMerchantDetailLink(action: openDetail) }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .onAppear { packageText = String(fulfilment.packageCount ?? 1) }
        .onChange(of: fulfilment.packageCount) { _, count in
            packageText = String(count ?? 1)
        }
        .onDisappear { evidenceGeneration = UUID(); evidenceLoading = false; evidenceItem = nil }
        .onChange(of: fulfilment.version) { _, _ in confirmReady = false }
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
        let evidenceTitle = evidenceLoading ? "Opening photo…" : fulfilment.evidence.isEmpty ? "Add Ready photo" : "Replace Ready photo"
        return VStack(spacing: MarketplaceSpacing.compact) {
            if fulfilment.canDeclarePackages {
                VStack(alignment: .leading, spacing: 10) {
                  Text("Sealed packages").font(.subheadline.weight(.semibold))
                  TextField("Package count", text: $packageText)
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .accessibilityLabel("Sealed package count")
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                  Stepper(value: Binding(get: { DastakMerchantValidation.packageCount(packageText) ?? 1 },
                    set: { packageText = String($0) }), in: DastakMerchantValidation.packageRange) {
                    Text("Adjust count").font(.subheadline)
                  }.frame(minHeight: 44)
                }
                Text(DastakMerchantValidation.packageHelp).font(.caption).foregroundStyle(.secondary)
                MarketplaceFeedbackButton(fulfilment.packageCount == nil ? "Confirm packages" : "Update packages") {
                    guard let count = DastakMerchantValidation.packageCount(packageText) else {
                        reportError(DastakMerchantValidation.packageHelp); return
                    }
                    declarePackages(count)
                }
                .buttonStyle(DastakMerchantActionStyle())
                .disabled(busy || DastakMerchantValidation.packageCount(packageText) == nil)
            }

            if fulfilment.canAddEvidence {
                PhotosPicker(selection: $evidenceItem, matching: .images) {
                    Label(
                        evidenceTitle,
                        systemImage: "camera.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DastakMerchantActionStyle())
                .disabled(busy)
                .onChange(of: evidenceItem) { _, item in
                    guard let item else { return }
                    Task { await loadEvidence(item) }
                }
                Text("JPEG, PNG or HEIC up to 10 MB.").font(.caption).foregroundStyle(.secondary)
                if let evidenceFailure { Text(evidenceFailure).font(.caption).foregroundStyle(.orange) }
            }

            if !fulfilment.evidence.isEmpty {
                Label("Ready photo secured", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.success.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if fulfilment.canMarkReady {
                MarketplaceFeedbackButton("Mark order Ready") { confirmReady = true }
                    .buttonStyle(DastakMerchantActionStyle(primary: true))
                    .disabled(busy || (fulfilment.canDeclarePackages && DastakMerchantValidation.packageCount(packageText) != fulfilment.packageCount))
                if fulfilment.canDeclarePackages && DastakMerchantValidation.packageCount(packageText) != fulfilment.packageCount {
                    Text("Confirm your package-count changes before marking this order Ready.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Label(
                    "Confirm package count and add a Ready photo to continue.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }.disabled(busy || evidenceLoading)
    }

    private func loadEvidence(_ item: PhotosPickerItem) async {
        guard !evidenceLoading else { return }
        let token = UUID(); evidenceGeneration = token; evidenceLoading = true; evidenceFailure = nil
        defer { if evidenceGeneration == token { evidenceLoading = false; evidenceItem = nil } }
        do {
            let photo = try await DastakMerchantPhoto.load(purpose: .ready) { try await item.loadTransferable(type: Data.self) }
            guard evidenceGeneration == token, !Task.isCancelled else { return }
            guard !busy else { evidenceFailure = "This order changed while the photo was loading. Check it and choose the photo again."; return }
            captureEvidence(photo.data, photo.contentType, photo.fileExtension)
        } catch {
            if evidenceGeneration == token { evidenceFailure = DastakMerchantPhoto.failureMessage(error) }
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

            HStack {
                Text("Product value").font(.subheadline.weight(.semibold))
                Spacer()
                Text(DastakFormatting.money(order.itemSubtotal))
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Product value \(DastakFormatting.money(order.itemSubtotal)). Delivery and platform fees are not shown to the merchant.")

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
                    .buttonStyle(DastakMerchantActionStyle())
                Button("Accept") { perform(.accept) }
                    .buttonStyle(DastakMerchantActionStyle(primary: true))
            }
        case .merchantAccepted:
            HStack(spacing: MarketplaceSpacing.compact) {
                Button("Reject", role: .destructive) { perform(.reject) }
                    .buttonStyle(DastakMerchantActionStyle())
                Button("Mark ready") { perform(.ready) }
                    .buttonStyle(DastakMerchantActionStyle(primary: true))
            }
        case .ready:
            Button("Reject order", role: .destructive) { perform(.reject) }
                .buttonStyle(DastakMerchantActionStyle())
        case .returningToMerchant:
            Button("Confirm items returned") { perform(.confirmReturn) }
                .buttonStyle(DastakMerchantActionStyle(primary: true))
        case .cancelled where order.paymentState == .refundPending:
            Button("Process refund") { perform(.refund) }
                .buttonStyle(DastakMerchantActionStyle(primary: true))
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
