import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakDeliveryOrderTarget: Identifiable {
    let kind: String
    let workID: UUID
    var id: String { kind + workID.uuidString }
}

struct DastakDeliveryOrderDetailView: View {
    let target: DastakDeliveryOrderTarget
    let client: DastakDeliveryOrderDetailClient
    @Environment(\.dismiss) private var dismiss
    @State private var detail: DastakDeliveryOrderDetail?
    @State private var loading = false
    @State private var failed = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if failed {
                        Label("Order details could not update. Any shown information is from the previous read.", systemImage: "wifi.exclamationmark")
                        Button("Try again") { Task { await load() } }.disabled(loading)
                    }
                    if loading { ProgressView("Loading full order") }
                    if let detail {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.order.displayOrderNumber).font(.caption.monospaced().bold())
                            Text(DastakMerchantReceiptPresentation.label(detail.missionStatus)).font(.title2.bold())
                            Text(DastakMerchantReceiptPresentation.label(detail.order.orderType)).font(.subheadline).foregroundStyle(.secondary)
                            if detail.terminal { Label("Completed work · customer contact is private", systemImage: "lock.shield").font(.footnote) }
                        }
                        section("Items") {
                            ForEach(detail.order.lines) { line in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(alignment: .top) {
                                        Text("\(line.quantity) × \(line.name)").font(.headline)
                                        Spacer()
                                        Text(DastakFormatting.money(.init(paise: line.lineTotalPaise))).monospacedDigit()
                                    }
                                    Text([line.variant, line.packSize].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    Text("\(DastakFormatting.money(.init(paise: line.unitPricePaise))) each").font(.caption).foregroundStyle(.secondary)
                                    let options = line.foodSelection?.options.map(\.name).joined(separator: ", ") ?? ""
                                    if !options.isEmpty { Text(options).font(.caption) }
                                }.padding(.vertical, 5)
                            }
                        }
                        section(detail.kind == "RETURN" ? "Return stops" : "Pickup stops") {
                            ForEach(detail.pickupStops.sorted { $0.sequence < $1.sequence }) { stop in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(stop.sequence). \(stop.name)").font(.headline)
                                    Text(stop.address).font(.subheadline)
                                    Text([stop.status.map(DastakMerchantReceiptPresentation.label), stop.packageCount.map { "\($0) packages" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }
                        }
                        if !detail.terminal, !failed, !loading, let address = detail.order.deliveryAddress {
                            section("Deliver to") {
                                Text(DastakV1OrderPresentation.addressLine(address))
                                if let instructions = address.instructions, !instructions.isEmpty {
                                    Label(instructions, systemImage: "text.bubble").font(.subheadline)
                                }
                                if let recipient = detail.order.recipient {
                                    Text(recipient.name).font(.headline)
                                    if let url = DastakDeliveryPresentation.callURL(recipient.phoneNumber) { Link("Call customer", destination: url) }
                                }
                            }
                        }
                        section(detail.kind == "RETURN" ? "Original order bill" : "Order bill") {
                            if detail.kind == "RETURN" { Text("For reference only. Do not collect this amount again for a return.").font(.footnote) }
                            amount("Items", detail.order.price.subtotalPaise)
                            amount("Delivery", detail.order.price.deliveryFeePaise)
                            amount("Platform fee", detail.order.price.platformFeePaise)
                            if detail.order.price.discountPaise > 0 { amount("Discount", -detail.order.price.discountPaise) }
                            Divider()
                            amount("Total", detail.order.price.totalPaise).fontWeight(.bold)
                            Text("Tax is included").font(.caption).foregroundStyle(.secondary)
                            if let collection = detail.collection {
                                Text(DastakMerchantReceiptPresentation.label(collection.state.rawValue)).font(.headline)
                                if let method = collection.lastMethod { Text("Method: \(method.rawValue)").font(.caption) }
                            }
                            Text("The order bill is not your earnings balance.").font(.caption).foregroundStyle(.secondary)
                        }
                        section("Order record") {
                            Text("Created: \(DastakMerchantReceiptPresentation.date(detail.order.createdAt))")
                            Text("Updated: \(DastakMerchantReceiptPresentation.date(detail.order.updatedAt))")
                            if let date = detail.order.deliveredAt { Text("Delivered: \(DastakMerchantReceiptPresentation.date(date))") }
                        }
                    }
                }.padding(16).frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
            }
            .navigationTitle("Full order").dastakInlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
        }.marketplacePage().task(id: target.id) { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if scenePhase == .active { await load() }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do { detail = try await client.detail(kind: target.kind, workID: target.workID); failed = false }
        catch { if !Task.isCancelled { failed = true } }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.title3.bold()); content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).marketplaceFlatSurface()
    }
    private func amount(_ title: String, _ paise: Int) -> some View {
        HStack { Text(title); Spacer(); Text(DastakFormatting.money(.init(paise: paise))).monospacedDigit() }
    }
}
