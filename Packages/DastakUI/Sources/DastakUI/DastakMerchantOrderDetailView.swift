import SwiftUI
import MarketplaceFoundation
import MarketplaceInfrastructure
import MarketplaceDesignSystem

@MainActor
final class DastakMerchantOrderDetailModel: ObservableObject {
    @Published private(set) var detail: DastakMerchantOrderDetail?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published private(set) var checkedAt: Date?
    let target: DastakMerchantDetailTarget
    private let services: MarketplaceAuthenticatedServices
    private let client: SupabaseDastakMerchantOrderDetailClient
    private var account: UUID?
    private var generation = UUID()
    init(target: DastakMerchantDetailTarget, services: MarketplaceAuthenticatedServices) {
        self.target = target; self.services = services
        client = .init(functions: DastakMerchantFunctionClient(base: services.functions))
    }
    func refresh() async {
        guard !loading else { return }
        let token = UUID(); generation = token; loading = true
        defer { if generation == token { loading = false } }
        do {
            let identity = try await MarketplaceRequestDeadline.run(after: .seconds(12)) { [services] in try await services.accountID() }
            guard account == nil || account == identity else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
            account = identity
            let value = try await client.get(target, key: IdempotencyKey(rawValue: UUID().uuidString)!)
            let after = try await MarketplaceRequestDeadline.run(after: .seconds(12)) { [services] in try await services.accountID() }
            guard identity == after else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
            guard generation == token, !Task.isCancelled else { return }
            detail = value; checkedAt = .now; failure = nil
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            if case let FunctionClientError.api(status, _, _) = error, [401,403,404].contains(status) { detail = nil; checkedAt = nil }
            if error is MarketplaceAuthenticatedServicesError { detail = nil; checkedAt = nil }
            if case FunctionClientError.authenticationRequired = error { detail = nil; checkedAt = nil }
            failure = "This order could not be verified. Refresh, check your Merchant session, or return to the order desk. Any retained details are from the last successful check."
        }
    }
}

struct DastakMerchantOrderDetailButton: View {
    @ObservedObject var model: DastakMerchantModel
    let target: DastakMerchantDetailTarget
    @State private var showing = false
    var body: some View {
        DastakMerchantDetailLink { showing = true }
            .font(.subheadline.weight(.semibold))
            .sheet(isPresented: $showing) { DastakMerchantOrderDetailView(model: model.makeOrderDetail(target)) }
            .onChange(of: model.selectedLocationID) { _, _ in showing = false }
            .accessibilityIdentifier("merchant.order.detail.\(target.id)")
    }
}

struct DastakMerchantOrderDetailView: View {
    @StateObject var model: DastakMerchantOrderDetailModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let failure = model.failure { Label(failure, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.secondary) }
                    if model.loading { ProgressView("Checking order details") }
                    if let detail = model.detail {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.branch.displayName).font(.caption.weight(.semibold))
                            Text(detail.order.displayOrderNumber).font(.title2.bold()).textSelection(.enabled)
                            Text(label(detail.order.status)).font(.headline)
                            stamp("Order placed", detail.order.createdAt)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).marketplaceFlatSurface()
                        Text("Only this location's items and operational records are shown. Product values in requested and fulfilled sections may overlap—do not add them together. Customer-wide charges and private delivery details are excluded.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(detail.records, id: \.identity) { record in recordCard(record) }
                        if !detail.recoveryOffers.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Exact-item recovery").font(.headline)
                                ForEach(detail.recoveryOffers) { offer in
                                    Text("\(offer.requestedQuantity) × \(offer.sku.name) · \(offer.sku.packSize)").bold()
                                    Text(label(offer.status)).font(.subheadline)
                                    stamp("Recovery offered", offer.startedAt)
                                    if let minutes = offer.promisedPrepMinutes { Text("Preparation promise · \(minutes) min").font(.footnote) }
                                }
                            }.padding(18).marketplaceFlatSurface()
                        }
                        if detail.records.isEmpty { Text("No preparation record is available for this recovery or return yet.").foregroundStyle(.secondary) }
                        if !detail.returns.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Returns").font(.headline)
                                ForEach(detail.returns) { receipt in
                                    Text("\(receipt.packageCount) package(s) · \(label(receipt.status))")
                                    stamp("Arrived", receipt.arrivedAt); stamp("Received", receipt.completedAt)
                                }
                            }.padding(18).marketplaceFlatSurface()
                        }
                        if !detail.settlements.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Fulfilment settlement records").font(.headline)
                                Text("Not a balance or bank payout confirmation.").font(.caption).foregroundStyle(.secondary)
                                ForEach(detail.settlements) { entry in
                                    Text(DastakMerchantReceiptPresentation.amount(entry)).bold()
                                    Text("\(label(entry.entryType)) · \(label(entry.status))").font(.footnote)
                                }
                            }.padding(18).marketplaceFlatSurface()
                        }
                        Text("Pickup and return codes remain on their guarded operational cards.").font(.footnote).foregroundStyle(.secondary)
                        if let date = model.checkedAt { Text("Checked \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    } else if !model.loading { Text("Order details unavailable").font(.title3.bold()) }
                    Button("Refresh details", systemImage: "arrow.clockwise") { Task { await model.refresh() } }.disabled(model.loading)
                }.frame(maxWidth: MarketplaceMetrics.contentMaxWidth).padding(20).frame(maxWidth: .infinity)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Full order").dastakInlineNavigationTitle()
            .modifier(DastakMerchantKeyboardDismiss())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.marketplacePage()
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    private func recordCard(_ record: DastakMerchantOrderDetail.Record) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(record.kind == "FULFILMENT" ? "Fulfilment" : record.kind == "RESTAURANT_REQUEST" ? "Kitchen request" : "Retail request").font(.headline)
            Text(label(record.status)).font(.subheadline.weight(.semibold))
            DastakMerchantLineList(lines: record.lines)
            if let amount = record.productSubtotalPaise { LabeledContent("Product value", value: DastakFormatting.money(Money(paise: amount))) }
            if let minutes = record.promisedPrepMinutes { LabeledContent("Preparation promise", value: "\(minutes) min") }
            if let count = record.packageCount { LabeledContent("Sealed packages", value: "\(count)") }
            stamp("Offered", record.offeredAt); stamp("Responded", record.respondedAt)
            stamp("Preparation started", record.prepStartedAt); stamp("Expected ready", record.estimatedReadyAt); stamp("Ready", record.actualReadyAt)
            if let reason = record.responseReason, !reason.isEmpty { Text(reason).font(.footnote) }
            if record.kind == "FULFILMENT" {
                Label("\(record.evidence.count) Ready photo(s) recorded", systemImage: "camera.fill").font(.footnote)
                ForEach(record.evidence) { photo in stamp("Photo recorded", photo.capturedAt) }
                if record.delivery.riderAssigned == true {
                    Text(record.delivery.riderName ?? "Delivery partner assigned").font(.subheadline.weight(.semibold))
                    if let status = record.delivery.stopStatus { Text("Pickup · \(label(status))").font(.footnote) }
                    stamp("Collected", record.delivery.pickedUpAt)
                }
            }
            ForEach(record.problems) { problem in Text("\(label(problem.statusAtReport)): \(problem.reason)").font(.footnote); stamp("Reported", problem.reportedAt) }
            ForEach(record.recovery) { recovery in Text("\(label(recovery.status)): \(recovery.reason)").font(.footnote); stamp("Recovery opened", recovery.openedAt); stamp("Resolved", recovery.resolvedAt) }
        }.padding(18).marketplaceFlatSurface()
    }
    @ViewBuilder private func stamp(_ title: String, _ value: String?) -> some View {
        if let value { LabeledContent(title, value: DastakMerchantOrderClock.date(value)?.formatted(date: .abbreviated, time: .shortened) ?? "Time unavailable").font(.footnote) }
    }
    private func label(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").lowercased().capitalized }
}

private extension DastakMerchantOrderDetail.Record { var identity: String { "\(kind):\(id)" } }
