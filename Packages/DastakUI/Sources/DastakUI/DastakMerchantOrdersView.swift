import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct DastakMerchantOrdersView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var rejection: DastakOrderRejection?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    header

                    if model.isLoading {
                        DastakLoadingOverlay(title: "Loading orders")
                            .frame(maxWidth: .infinity)
                            .padding(.top, MarketplaceSpacing.xxLarge)
                    } else {
                        if let earnings = model.earnings {
                            DastakEarningsCard(earnings: earnings, title: "Earnings")
                        }
                        summary
                        v1OrderSection
                        orderSection(
                            title: "Active orders",
                            orders: model.activeOrders,
                            emptyMessage: model.v1Fulfilments.isEmpty
                                ? "Confirmed orders will appear here."
                                : "Your current Dastak orders are shown above."
                        )
                        if !model.recentOrders.isEmpty {
                            orderSection(
                                title: "Recent orders",
                                orders: model.recentOrders,
                                emptyMessage: ""
                            )
                        }
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refreshAll() }
            .navigationTitle("Orders")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(MarketplaceIconButtonStyle())
                    .disabled(model.isRefreshing || model.isBusy)
                    .accessibilityLabel("Refresh orders")
                }
            }
        }
        .sheet(item: $rejection) { rejection in
            DastakRejectOrderSheet(order: rejection.order) { reason in
                Task {
                    await model.perform(.reject, order: rejection.order, reason: reason)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            DastakWordmark(size: 30)
            Text(model.store?.name ?? "Merchant workspace")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
        }
        .padding(.top, MarketplaceSpacing.compact)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            summaryItem(
                value: model.activeOrders.count + activeV1Fulfilments.count,
                label: "Active"
            )
            Divider().frame(height: 42)
            summaryItem(
                value: activeV1Fulfilments.filter { $0.status == "PREPARING" }.count,
                label: "Preparing"
            )
            Divider().frame(height: 42)
            summaryItem(
                value: model.activeOrders.filter { $0.status == .ready }.count
                    + activeV1Fulfilments.filter { $0.status == "READY" }.count,
                label: "Ready"
            )
        }
        .padding(.vertical, MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private func summaryItem(value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value.formatted())
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var activeV1Fulfilments: [DastakV1MerchantFulfilment] {
        model.v1Fulfilments.filter {
            ["PREPARING", "READY", "PICKED_UP"].contains($0.status)
        }
    }

    @ViewBuilder
    private var v1OrderSection: some View {
        if !activeV1Fulfilments.isEmpty {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                HStack {
                    Text("Confirmed Dastak orders")
                        .font(MarketplaceTypography.sectionTitle)
                    Text(activeV1Fulfilments.count.formatted())
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, MarketplaceSpacing.small)
                        .frame(minHeight: 26)
                        .background(.thinMaterial, in: Capsule())
                }

                ForEach(activeV1Fulfilments) { fulfilment in
                    DastakV1MerchantFulfilmentCard(
                        fulfilment: fulfilment,
                        busy: model.busyIdentity?.contains(fulfilment.id.uuidString) == true,
                        declarePackages: { count in
                            Task { await model.declareV1Packages(fulfilment, count: count) }
                        },
                        captureEvidence: { data, contentType, fileExtension in
                            Task {
                                await model.addV1ReadyEvidence(
                                    fulfilment,
                                    data: data,
                                    contentType: contentType,
                                    fileExtension: fileExtension
                                )
                            }
                        },
                        markReady: {
                            Task { await model.markV1Ready(fulfilment) }
                        },
                        reportError: { model.errorMessage = $0 }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func orderSection(
        title: String,
        orders: [MerchantOrderSnapshot],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                Text(title)
                    .font(MarketplaceTypography.sectionTitle)
                Text(orders.count.formatted())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MarketplaceSpacing.small)
                    .frame(minHeight: 26)
                    .background(.thinMaterial, in: Capsule())
            }

            if orders.isEmpty {
                DastakEmptyState(
                    symbol: "list.bullet.clipboard",
                    title: "No active orders",
                    message: emptyMessage
                )
                .frame(minHeight: 240)
            } else {
                ForEach(orders, id: \.orderID) { order in
                    DastakMerchantOrderCard(
                        order: order,
                        busy: model.busyIdentity?.contains(order.orderID.uuidString) == true,
                        perform: { action in
                            if action == .reject {
                                rejection = DastakOrderRejection(order: order)
                            } else {
                                Task { await model.perform(action, order: order) }
                            }
                        }
                    )
                }
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: "bag.fill")
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 40, height: 40)
                    .background(MarketplaceColors.dastakAccentSoft.color)
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
                DastakStatusPill(text: statusLabel, emphasis: fulfilment.status != "PICKED_UP")
            }

            Label(
                "Order confirmed. Prepare the full secured basket now.",
                systemImage: "checkmark.seal.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MarketplaceColors.success.color)

            Text("The delivery partner will collect payment from the customer at the doorstep. No payment action is needed here.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: MarketplaceSpacing.small) {
                ForEach(fulfilment.lines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(line.quantity) ×")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text(line.name)
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
            .padding(.vertical, MarketplaceSpacing.compact)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }

            if fulfilment.status == "PREPARING" {
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
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .onAppear { packageCount = max(fulfilment.packageCount ?? 1, 1) }
        .onChange(of: fulfilment.packageCount) { _, count in
            packageCount = max(count ?? 1, 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var prepProgress: some View {
        HStack {
            Label(
                fulfilment.runningLate ? "Preparation needs attention" : "Preparing",
                systemImage: fulfilment.runningLate ? "clock.badge.exclamationmark" : "clock"
            )
            .foregroundStyle(
                fulfilment.runningLate
                    ? MarketplaceColors.warning.color
                    : MarketplaceColors.dastakAccent.color
            )
            Spacer()
            Text(prepTimeLabel)
                .font(.subheadline.bold().monospacedDigit())
        }
        .font(.subheadline.weight(.semibold))
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
                Button("Mark order Ready") { markReady() }
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
            let types = item.supportedContentTypes
            let type: UTType = types.contains(.png) ? .png :
                types.contains(.heic) ? .heic : .jpeg
            let fileExtension = type == .png ? "png" : type == .heic ? "heic" : "jpg"
            captureEvidence(data, type.preferredMIMEType ?? "image/jpeg", fileExtension)
        } catch {
            reportError("The Ready photo could not be opened. Choose another photo.")
        }
    }

    private var statusLabel: String {
        switch fulfilment.status {
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
