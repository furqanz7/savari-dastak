import Foundation
import SwiftUI
import MarketplaceDesignSystem
import MarketplaceInfrastructure

enum DastakMerchantReceiptPresentation {
    /// A read is a snapshot, not a perpetual handoff authorization. Recheck after a minute.
    static func returnCode(_ receipt: DastakV1MerchantReturnReceipt, current: Bool,
        refreshedAt: Date?, physicallyConfirmed: Bool, now: Date) -> String? {
        guard current, physicallyConfirmed, let refreshedAt,
              (0..<60).contains(now.timeIntervalSince(refreshedAt)),
              receipt.status == "ARRIVED", receipt.verificationStatus == "ACTIVE",
              receipt.packageCount > 0, receipt.completedAt == nil,
              DastakMerchantOrderClock.date(receipt.arrivedAt ?? "") != nil,
              let code = receipt.receiptCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return nil }
        return code
    }

    static func amount(_ entry: DastakV1MerchantSettlement) -> String {
        guard entry.calculationStatus == "CALCULATED", let paise = entry.amountPaise else {
            return "Amount not calculated"
        }
        guard entry.currency == "INR" else { return "Amount unavailable · Unsupported currency" }
        // Decimal avoids converting paise through an imprecise Double or dropping the debit sign.
        return (Decimal(paise) / 100).formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
    }

    static func label(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
    }

    static func date(_ value: String) -> String {
        DastakMerchantOrderClock.date(value)?.formatted(date: .abbreviated, time: .shortened)
            ?? "Time unavailable"
    }
}

struct DastakMerchantReturnsView: View {
    @ObservedObject var model: DastakMerchantModel
    let history: Bool
    let showAll: Bool
    private var receipts: [DastakV1MerchantReturnReceipt] {
        model.scopedReturnReceipts.filter { showAll || (($0.status == "COMPLETED") == history) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showAll || !receipts.isEmpty {
                Text(history ? "Completed return receipts" : "Return receipts").font(.title3.bold())
                Text("Returns for your store. Check the store details and every package before sharing a code. The assigned delivery partner completes the handoff.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !model.returnsCurrent {
                    Label("Return updates unavailable or refreshing. Previously loaded receipts are read-only; codes are hidden.", systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if receipts.isEmpty && model.returnsCurrent {
                    Text("No return receipts are available.").foregroundStyle(.secondary)
                }
                Button("Refresh return receipts") { Task { await model.refreshV1Fulfilments() } }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("merchant.returns.refresh")
                ForEach(receipts) { receipt in
                    DastakMerchantReturnCard(receipt: receipt, current: model.returnsCurrent,
                        refreshedAt: model.returnsRefreshedAt)
                    DastakMerchantOrderDetailButton(model: model,
                        target: .init(kind: .returned, id: receipt.id, branchID: receipt.branch.id))
                }
            }
        }.accessibilityIdentifier("merchant.returns.lane")
    }
}

private struct DastakMerchantReturnCard: View {
    let receipt: DastakV1MerchantReturnReceipt
    let current: Bool
    let refreshedAt: Date?
    @State private var physicallyConfirmed = false
    @State private var revealed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = DastakMerchantReceiptPresentation.returnCode(receipt, current: current,
                refreshedAt: refreshedAt, physicallyConfirmed: physicallyConfirmed, now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                Text(receipt.branch.displayName).font(.headline)
                Text("Order ID: \(receipt.orderId.uuidString)").font(.caption).foregroundStyle(.secondary)
                Label(DastakMerchantReceiptPresentation.label(receipt.status), systemImage: "shippingbox")
                    .font(.subheadline.bold())
                Text("\(receipt.packageCount) package(s) · All packages must arrive together")
                    .font(.subheadline)
                if let arrived = receipt.arrivedAt {
                    Text("Arrived: \(DastakMerchantReceiptPresentation.date(arrived))").font(.caption)
                }
                if let completed = receipt.completedAt {
                    Text("Completed: \(DastakMerchantReceiptPresentation.date(completed))").font(.caption)
                }
                if receipt.status == "ARRIVED", receipt.verificationStatus == "ACTIVE", receipt.completedAt == nil {
                    Toggle("I checked the store details and all \(receipt.packageCount) returned packages are physically present.", isOn: $physicallyConfirmed)
                        .disabled(!current || scenePhase != .active)
                        .accessibilityIdentifier("merchant.returns.packagesChecked")
                    if revealed, let code, scenePhase == .active {
                        Text("Share only with the assigned delivery partner after checking every package.")
                            .font(.footnote)
                        Text(code).font(.largeTitle.monospaced().bold())
                            .accessibilityLabel("Return receipt code \(code.map(String.init).joined(separator: " "))")
                            .accessibilityIdentifier("merchant.returns.code")
                        Button("Hide code") { revealed = false }.frame(minHeight: 44)
                    } else {
                        Button("Show return receipt code") { revealed = true }
                            .buttonStyle(DastakMerchantActionStyle())
                            .disabled(code == nil || scenePhase != .active)
                        Text("Check every package, then reveal the code. If unavailable, refresh return receipts.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Receipt verification: \(DastakMerchantReceiptPresentation.label(receipt.verificationStatus ?? "PENDING"))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(18).marketplaceFlatSurface()
        }
        .onChange(of: receipt) { _, _ in resetCode() }
        .onChange(of: refreshedAt) { _, _ in resetCode() }
        .onChange(of: current) { _, value in if !value { resetCode() } }
        .onChange(of: physicallyConfirmed) { _, value in if !value { revealed = false } }
        .onChange(of: scenePhase) { _, value in if value != .active { resetCode() } }
    }

    private func resetCode() { physicallyConfirmed = false; revealed = false }
}

struct DastakMerchantSettlementsView: View {
    @ObservedObject var model: DastakMerchantModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settlement status").font(.title3.bold())
            Text("Business-wide entries available to this account, not an order-by-order earnings total. This list is not a lifetime balance or bank payout confirmation. No payment can be initiated here.")
                .font(.footnote).foregroundStyle(.secondary)
            if !model.settlementsCurrent {
                Label("Settlement updates unavailable or refreshing. Showing the last available information.", systemImage: "wifi.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Button("Refresh settlement status") { Task { await model.refreshV1Fulfilments() } }
                .accessibilityIdentifier("merchant.settlements.refresh")
            if model.settlements.isEmpty && model.settlementsCurrent {
                Text("No settlement entries are available.").foregroundStyle(.secondary)
            }
            ForEach(model.settlements) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    Text(DastakMerchantReceiptPresentation.label(entry.entryType)).font(.headline)
                    Text(DastakMerchantReceiptPresentation.amount(entry)).font(.title3.bold()).monospacedDigit()
                    Text("Ledger status: \(DastakMerchantReceiptPresentation.label(entry.status))").font(.subheadline)
                    if entry.calculationStatus != "CALCULATED" {
                        Text("Calculation: \(DastakMerchantReceiptPresentation.label(entry.calculationStatus))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Order ID: \(entry.orderId.uuidString)").font(.caption).foregroundStyle(.secondary)
                    if let fulfilment = entry.fulfilmentId {
                        Text("Fulfilment ID: \(fulfilment.uuidString)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let eligible = entry.eligibleAt {
                        Text("Eligible: \(DastakMerchantReceiptPresentation.date(eligible))").font(.caption)
                    }
                    if let settled = entry.settledAt {
                        Text("Recorded settled: \(DastakMerchantReceiptPresentation.date(settled))").font(.caption)
                    }
                }.padding(18).marketplaceFlatSurface()
            }
        }.accessibilityIdentifier("merchant.settlements.lane")
    }
}
