import SwiftUI
import MarketplaceDesignSystem
import MarketplaceInfrastructure

struct DastakMerchantRecoveryStatus: View {
    @ObservedObject var model: DastakMerchantModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.recoveryCommandMessage {
                Text(message).font(.subheadline)
            }
            if let pending = model.pendingRecoveryCommand {
                Label("Pending: \(pending.description)", systemImage: "exclamationmark.circle")
                    .font(.headline)
                Text(pending.detail).font(.subheadline)
                Text("Related preparation changes are paused. Checking retries the original action, even if the latest order has changed.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Check pending recovery action") { Task { await model.retryRecoveryCommand() } }
                    .buttonStyle(DastakMerchantActionStyle()).disabled(model.busyIdentity != nil || !model.merchantJournalRestored)
                    .accessibilityIdentifier("merchant.recovery.retry")
            }
        }
    }
}

struct DastakMerchantRecoveryLane: View {
    @ObservedObject var model: DastakMerchantModel
    let history: Bool
    private var offers: [DastakV1RecoveryOpportunity] {
        model.scopedRecoveryOpportunities.filter { history ? $0.status != "OFFERED" : $0.status == "OFFERED" }
    }
    var body: some View {
        if !offers.isEmpty || !model.recoveryCurrent {
            VStack(alignment: .leading, spacing: 14) {
                Label(history ? "Recent recovery responses" : "Exact-item recovery", systemImage: "shippingbox.circle")
                    .font(.headline)
                if !model.recoveryCurrent {
                    Text("Recovery requests are being checked or could not be refreshed. Displayed requests may be outdated; actions stay disabled until refreshed.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Refresh recovery requests") { Task { await model.refreshV1Fulfilments() } }
                        .disabled(model.isBusy)
                }
                ForEach(offers) { offer in
                    if history {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(offer.requestedQuantity) × \(offer.sku.name)").font(.headline)
                            Text([offer.sku.variantName, offer.sku.packSize].compactMap { $0 }.joined(separator: " · "))
                            Text("\(offer.branch.displayName) · \(offer.status.lowercased())").font(.caption).foregroundStyle(.secondary)
                        }.padding(14).marketplaceFlatSurface()
                    } else {
                        DastakMerchantRecoveryOfferCard(model: model, offer: offer)
                            .id("\(offer.id):\(offer.version)")
                    }
                    DastakMerchantOrderDetailButton(model: model,
                        target: .init(kind: .recovery, id: offer.id, branchID: offer.branch.id))
                }
            }.accessibilityIdentifier("merchant.recovery.lane")
        }
    }
}

private struct DastakMerchantRecoveryOfferCard: View {
    @ObservedObject var model: DastakMerchantModel
    let offer: DastakV1RecoveryOpportunity
    @State private var physicallyConfirmed = false
    @State private var prepMinutes = 10
    @State private var review: Review?
    private struct Review { let offer: DastakV1RecoveryOpportunity; let accept: Bool; let minutes: Int }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = DastakMerchantOrderClock.date(offer.expiresAt).map { $0 <= context.date } ?? true
            VStack(alignment: .leading, spacing: 12) {
                Text(offer.branch.displayName).font(.caption).foregroundStyle(.secondary)
                Text("\(offer.requestedQuantity) × \(offer.sku.name)").font(.title3.bold())
                Text([offer.sku.variantName, offer.sku.packSize].compactMap { $0 }.joined(separator: " · "))
                Label(expired ? "Request expired · Refresh for the latest state" : "Respond within \(DastakMerchantOrderClock.remaining(offer.expiresAt, now: context.date))", systemImage: "timer")
                    .font(.footnote)
                Toggle("I physically hold this exact SKU and full quantity. No substitution.", isOn: $physicallyConfirmed)
                Stepper("Preparation: \(prepMinutes) minutes", value: $prepMinutes, in: 1...180)
                Text("Your preparation promise must be allowed by your store configuration. Dastak validates it before acceptance.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Accept exact item") { review = Review(offer: offer, accept: true, minutes: prepMinutes) }
                    .buttonStyle(DastakMerchantActionStyle(primary: true)).disabled(!physicallyConfirmed)
                    .accessibilityIdentifier("merchant.recovery.accept")
                Button("Unavailable") { review = Review(offer: offer, accept: false, minutes: 0) }
                    .buttonStyle(DastakMerchantActionStyle())
                    .accessibilityIdentifier("merchant.recovery.unavailable")
            }
            .disabled(model.recoveryActionsDisabled || expired)
            .padding(18).marketplaceFlatSurface()
        }
        .confirmationDialog(review?.accept == true ? "Accept this exact item and full quantity?" : "Mark this recovery request unavailable?",
            isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), titleVisibility: .visible) {
            if let reviewed = review {
                Button(reviewed.accept ? "Confirm exact stock and accept" : "Confirm unavailable") {
                    review = nil
                    Task { await model.respondToRecovery(reviewed.offer, accept: reviewed.accept,
                        prepMinutes: reviewed.minutes, physicallyConfirmed: reviewed.accept) }
                }
                .disabled(model.recoveryActionsDisabled)
            }
            Button("Cancel", role: .cancel) { review = nil }
        } message: {
            if let reviewed = review {
                Text("\(reviewed.offer.requestedQuantity) × \(reviewed.offer.sku.name) · \(reviewed.offer.sku.packSize). \(reviewed.accept ? "Preparation promise: \(reviewed.minutes) minutes. No substitutions or partial quantities." : "Dastak will continue looking for the exact item elsewhere.")")
            }
        }
    }
}

struct DastakMerchantProblemView: View {
    @ObservedObject var model: DastakMerchantModel
    let fulfilment: DastakV1MerchantFulfilment
    @State private var exactItem = false
    @State private var lineID: UUID?
    @State private var reason = ""
    @State private var review: Review?
    private struct Review { let order: DastakV1MerchantFulfilment; let lineID: UUID?; let reason: String }
    private var reasonValid: Bool {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && reason.utf16.count <= 500
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let cases = fulfilment.recoveryCases, !cases.isEmpty {
                ForEach(cases) { entry in
                    Text("Item recovery: \(entry.status.lowercased().replacingOccurrences(of: "_", with: " ")) · \(entry.reason)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let reports = fulfilment.problemReports, !reports.isEmpty {
                DisclosureGroup("\(reports.count) recorded problem reports") {
                    ForEach(reports) { entry in
                        Text(entry.reason).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if fulfilment.orderStatus == "PREPARING", ["PREPARING", "READY"].contains(fulfilment.status) {
                DisclosureGroup("Report an unavailable item or preparation problem") {
                    VStack(alignment: .leading, spacing: 12) {
                        if fulfilment.canReportExactSkuFailure == true && fulfilment.packageCount == nil {
                            Toggle("An exact item is unavailable", isOn: $exactItem)
                            if exactItem {
                                Picker("Exact unavailable item", selection: $lineID) {
                                    Text("Choose an item").tag(UUID?.none)
                                    ForEach(fulfilment.lines) { line in
                                        Text("\(line.quantity) × \(line.name) · \(line.packSize ?? line.variant ?? "")").tag(UUID?.some(line.id))
                                    }
                                }
                                Text("Recovery covers this exact SKU and the full quantity only. Do not replace it with another product or pack size.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        TextField("Problem details (3–500 characters)", text: $reason, axis: .vertical)
                            .lineLimit(3...5).textFieldStyle(.roundedBorder)
                        Text("A general problem report does not cancel the order or undo Ready.").font(.caption).foregroundStyle(.secondary)
                        Button(exactItem ? "Review exact-item recovery" : "Review problem report") {
                            review = Review(order: fulfilment, lineID: exactItem ? lineID : nil,
                                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .buttonStyle(DastakMerchantActionStyle())
                        .disabled(!reasonValid || (exactItem && lineID == nil))
                    }.padding(.top, 10).disabled(!model.canReportProblem(fulfilment))
                }
            }
        }
        .accessibilityIdentifier("merchant.recovery.problem.\(fulfilment.id)")
        .onChange(of: fulfilment.version) { _, _ in
            review = nil
            if fulfilment.canReportExactSkuFailure != true || fulfilment.packageCount != nil {
                exactItem = false; lineID = nil
            } else if let selected = lineID, !fulfilment.lines.contains(where: { $0.id == selected }) {
                lineID = nil
            }
        }
        .onChange(of: fulfilment.status) { _, _ in review = nil }
        .confirmationDialog("Submit this report for \(fulfilment.displayOrderNumber)?",
            isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), titleVisibility: .visible) {
            if let reviewed = review {
                Button(reviewed.lineID == nil ? "Submit problem report" : "Start exact-item recovery") {
                    review = nil
                    Task {
                        if await model.reportRecoveryProblem(reviewed.order, lineID: reviewed.lineID, reason: reviewed.reason) {
                            reason = ""; lineID = nil; exactItem = false
                        }
                    }
                }.disabled(!model.canReportProblem(reviewed.order))
            }
            Button("Cancel", role: .cancel) { review = nil }
        } message: {
            if let reviewed = review {
                Text("\(reviewed.reason)\n\(reviewed.lineID == nil ? "This preserves the current preparation status." : "Dastak will look for the exact item and full quantity at another eligible store.")")
            }
        }
    }
}
