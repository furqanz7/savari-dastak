import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

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
                        summary
                        orderSection(
                            title: "Active orders",
                            orders: model.activeOrders,
                            emptyMessage: "New paid orders will appear here."
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
                value: model.activeOrders.count,
                label: "Active"
            )
            Divider().frame(height: 42)
            summaryItem(
                value: model.activeOrders.filter { $0.status == .paid }.count,
                label: "New"
            )
            Divider().frame(height: 42)
            summaryItem(
                value: model.activeOrders.filter { $0.status == .ready }.count,
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
