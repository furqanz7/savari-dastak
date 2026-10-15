import SwiftUI
import MarketplaceInfrastructure

struct DastakAdminExecutionWorkspace: View {
    @ObservedObject var model: DastakAdminExecutionModel
    @State private var scope = "ACTIVE"
    @State private var query = ""
    @State private var review: Review?
    private struct Review: Identifiable {
        let id = UUID()
        let action: DastakAdminExecutionAction
        let target: DastakAdminTraceRecord
        let trace: DastakV1AdminExecutionTrace
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Order execution & recovery").font(.title2.bold())
            Text("Current-generation order trace. Recovery decisions require current permissions and a fresh server read.").font(.subheadline).foregroundStyle(.secondary)
            Picker("Order scope", selection: $scope) { Text("Active").tag("ACTIVE"); Text("History").tag("HISTORY") }.pickerStyle(.segmented)
                .onChange(of: scope) { _, value in Task { await model.refreshPage(scope: value, query: query) } }
            HStack {
                TextField("Order number or ID", text: $query).textFieldStyle(.roundedBorder).onSubmit { refresh() }
                Button("Search", action: refresh).disabled(query.count > 80 || model.busy)
            }
            if let message = model.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("admin-execution-message") }
            if let pending = model.pending {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved action: \(pending.request.operation.title)").bold()
                    Text("Order \(pending.orderID.uuidString). The original details and request key are retained. Recovery does not start another refund.").font(.caption)
                    Button(pending.acknowledged ? "Finish local recovery" : "Retry saved action") { Task { await model.retry() } }.disabled(model.busy)
                }.padding().background(Color.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if model.loading { ProgressView("Refreshing order directory") }
            if !model.listCurrent { Text("Directory not current. Refresh before loading more.").font(.caption).foregroundStyle(.secondary) }
            if model.orders.isEmpty, model.listCurrent { Text("No orders match this scope and search.").foregroundStyle(.secondary) }
            ForEach(model.orders) { order in
                Button { Task { await model.select(order.id) } } label: {
                    HStack {
                        VStack(alignment: .leading) { Text(order.displayOrderNumber).bold(); Text("\(order.orderType) · \(order.status)").font(.caption) }
                        Spacer()
                        if model.selectedID == order.id { Image(systemName: "checkmark.circle.fill") }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered).disabled(model.busy)
            }
            if model.cursor != nil { Button("Load more orders") { Task { await model.refreshPage(append: true) } }.disabled(model.loading || !model.listCurrent || model.busy) }
            if let trace = model.trace {
                Divider()
                HStack {
                    VStack(alignment: .leading) { Text(trace.order.displayOrderNumber).font(.headline); Text("\(trace.order.status) · version \(trace.order.version)").font(.caption) }
                    Spacer()
                    Button("Refresh trace") { Task { await model.select(trace.order.id) } }.disabled(model.busy)
                }
                if !model.fresh() { Text("Trace stale. Refresh before reviewing a new action.").foregroundStyle(.orange) }
                if !trace.financeCurrent { Text("Recovery and finance data is incomplete. Financial actions are locked; raw trace remains available below.").foregroundStyle(.orange) }
                if !trace.deliveryCurrent { Text("Delivery override data is incomplete. Exceptional handoff is locked.").foregroundStyle(.orange) }
                if let payment = trace.launchPayment {
                    Text("Doorstep collection: \(payment.collectionStatus)").bold()
                    if let commitment = payment.commitment { Text("Committed amount: \(money(commitment.amountPaise, commitment.currencyCode))") }
                    ForEach(payment.attempts) { attempt in Text("\(attempt.outcome) · \(attempt.method) · \(attempt.attemptedAt)").font(.caption) }
                    if let fee = payment.platformFee { Text("Platform fee: \(money(fee.amountPaise, fee.currencyCode)) · \(fee.balanced ? "balanced ledger" : "ledger not balanced")").font(.caption) }
                } else { Text("Launch payment summary unavailable; no collection outcome inferred.").font(.caption).foregroundStyle(.secondary) }
                if trace.cancellation?.canCancel == true {
                    actionButton(.cancel, target: trace.root.record("order") ?? .init(fields: [:]), trace: trace)
                } else if let blocker = trace.cancellation?.blocker { Text("Cancellation: \(blocker)").font(.caption) }
                financeSection("Recovery cases", key: "recoveryCases", trace: trace)
                financeSection("Customer issues", key: "customerIssues", trace: trace)
                financeSection("Returns & custody", key: "returns", trace: trace)
                financeSection("Refunds", key: "refunds", trace: trace)
                financeSection("Settlements", key: "settlements", trace: trace)
                if let mission = trace.delivery?.record("mission"), trace.delivery?.flag("canAuthorizeExceptionalHandoff") == true {
                    actionButton(.handoff, target: mission, trace: trace)
                }
                Text("Settlement calculation is not a payout. Refund submission is not proof of provider completion. Prepared food cannot enter physical-return custody.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Complete server trace (read-only)") {
                    ForEach(trace.root.fields.keys.sorted(), id: \.self) { key in
                        DisclosureGroup(label(key)) { Text(render(trace.root.fields[key] ?? .null)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    Text("Royalty balances and withdrawals may cover the account, not this order alone. Missing or null values are unknown, not zero.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task { if !model.restored { await model.refreshPage() } }
        .sheet(item: $review) { value in
            DastakAdminExecutionReview(model: model, action: value.action, target: value.target, reviewed: value.trace)
        }
    }
    private func refresh() { Task { await model.refreshPage(scope: scope, query: query) } }
    private func financeSection(_ title: String, key: String, trace: DastakV1AdminExecutionTrace) -> some View {
        DisclosureGroup("\(title) · \(model.rows(key).count)") {
            if model.rows(key).isEmpty { Text(trace.financeCurrent ? "None recorded." : "Unknown until finance refresh succeeds.").font(.caption) }
            ForEach(Array(model.rows(key).enumerated()), id: \.offset) { _, record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.text("type") ?? record.text("category") ?? record.text("entryType") ?? title).bold()
                    Text("\(record.text("status") ?? "Unknown") · \(record.uuid()?.uuidString ?? "Unknown ID")").font(.caption).textSelection(.enabled)
                    if key == "refunds" || key == "settlements" {
                        Text("Amount: \(record.integer("amountPaise").map { money($0, record.text("currency") ?? "Unknown currency") } ?? "Not calculated / unknown")")
                    }
                    if let reason = record.text("reason") ?? record.text("description") { Text(reason).font(.subheadline) }
                    if key == "recoveryCases" {
                        if record.text("type") == "EXACT_SKU" { actionButton(.offer, target: record, trace: trace); actionButton(.fail, target: record, trace: trace) }
                        if record.text("type") == "DELIVERY" { actionButton(.delivery, target: record, trace: trace) }
                    }
                    if key == "customerIssues" { actionButton(.issue, target: record, trace: trace) }
                    if key == "returns", let mission = record.record("mission") { actionButton(.rider, target: mission, trace: trace) }
                    if key == "refunds" { actionButton(.refund, target: record, trace: trace) }
                    if key == "settlements" { actionButton(.settlement, target: record, trace: trace) }
                    DisclosureGroup("Record details") { Text(render(.object(record.fields))).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }.padding(12).background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private func actionButton(_ action: DastakAdminExecutionAction, target: DastakAdminTraceRecord, trace: DastakV1AdminExecutionTrace) -> some View {
        Button(action.title) { review = .init(action: action, target: target, trace: trace) }
            .buttonStyle(.bordered).disabled(model.blocksActions || !model.fresh() || (action != .cancel && action != .handoff && !trace.financeCurrent))
    }
}

private struct DastakAdminExecutionReview: View {
    @ObservedObject var model: DastakAdminExecutionModel
    let action: DastakAdminExecutionAction
    let target: DastakAdminTraceRecord
    let reviewed: DastakV1AdminExecutionTrace
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var identifier = ""
    @State private var fault = "DASTAK"
    @State private var deliveryAction = "RESUME_DELIVERY"
    @State private var decision = "RESOLVE_NO_REFUND"
    @State private var amount = ""
    @State private var count = ""
    @State private var address = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var accepted = false
    @State private var orderConfirmation = ""
    @State private var evidenceURL: URL?
    @State private var loadedEvidenceID: String?
    @State private var evidenceMessage: String?
    @State private var requestedEvidenceID: String?
    @State private var evidenceGeneration = UUID()
    private var refundDecision: Bool { ["PHYSICAL_RETURN", "REFUND_WITHOUT_RETURN"].contains(decision) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Review \(reviewed.order.displayOrderNumber)") {
                    Text(action.title).font(.headline)
                    Text("Target \(target.uuid()?.uuidString ?? "Unknown") · version \(target.integer("version") ?? 0)").font(.caption).textSelection(.enabled)
                    Text("No action is sent until you explicitly confirm. The server checks permissions, versions, custody and policy again.").font(.subheadline)
                    if action == .fail { Text("Ends recovery and creates the policy refund for the affected line. No substitute SKU will be selected.").foregroundStyle(.orange) }
                    if action == .refund { Text("Submits this already-approved refund to the payment provider. Pending is not completed. Retry only the saved request if the outcome is uncertain.").foregroundStyle(.orange); Text("Approved amount: \(target.integer("amountPaise").map { money($0, target.text("currency") ?? "Unknown currency") } ?? "Unknown")") }
                    if action == .settlement { Text("Calculates the server-configured settlement amount. This does not transfer funds or mark a bank payout paid.") }
                    if action == .handoff { Text("Exceptional handoff completes delivery without the normal PIN verification. Review the delivery evidence first.").foregroundStyle(.red) }
                }
                Section("Action details") {
                    if action == .offer || action == .rider {
                        TextField(action == .offer ? "Eligible branch UUID" : "Onboarded rider UUID", text: $identifier)
                        Text("Use the exact identifier from the Admin network directory; the server validates eligibility. No automatic branch or rider selection.").font(.caption)
                    }
                    if action == .handoff {
                        Picker("Delivery evidence", selection: $identifier) {
                            Text("Choose evidence").tag("")
                            ForEach(Array((reviewed.delivery?.rows("deliveryEvidence") ?? []).enumerated()), id: \.offset) { _, record in
                                Text(record.text("objectPath") ?? record.uuid()?.uuidString ?? "Unknown").tag(record.uuid()?.uuidString ?? "")
                            }
                        }
                        DisclosureGroup("Evidence records") { Text(render(.array((reviewed.delivery?.rows("deliveryEvidence") ?? []).map { .object($0.fields) }))).font(.caption).textSelection(.enabled) }
                        evidenceControls(reviewed.delivery?.rows("deliveryEvidence") ?? [])
                    }
                    if action == .delivery {
                        Picker("Delivery action", selection: $deliveryAction) { Text("Resume delivery").tag("RESUME_DELIVERY"); Text("Return to origin").tag("RETURN_TO_ORIGIN") }
                        if deliveryAction == "RETURN_TO_ORIGIN" { Text("Returns current rider custody to the origin merchants. Refund is not automatic. Prepared food is not physically returnable.").foregroundStyle(.orange) }
                        if deliveryAction == "RESUME_DELIVERY" {
                            TextField("Corrected address (optional)", text: $address)
                            TextField("Latitude (required with correction)", text: $latitude)
                            TextField("Longitude (required with correction)", text: $longitude)
                        }
                    }
                    if action == .issue {
                        Picker("Issue decision", selection: $decision) {
                            Text("Resolve without refund").tag("RESOLVE_NO_REFUND")
                            Text("Reject issue").tag("REJECT")
                            Text("Refund without physical return").tag("REFUND_WITHOUT_RETURN")
                            if target.flag("physicalReturnAllowed") == true && target.flag("preparedFood") == false && reviewed.order.orderType == "RETAIL_ONLY" { Text("Approve physical return").tag("PHYSICAL_RETURN") }
                        }
                        if decision == "PHYSICAL_RETURN" { TextField("Physical package count (1–1000)", text: $count) }
                        DisclosureGroup("Customer issue and evidence") { Text(render(.object(target.fields))).font(.caption).textSelection(.enabled) }
                        evidenceControls(target.rows("evidence") ?? [])
                    }
                    if action == .delivery || (action == .issue && refundDecision) {
                        Picker("Fault source", selection: $fault) {
                            ForEach(["RIDER", "MERCHANT", "DASTAK", "CUSTOMER"], id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    }
                    if action == .issue && refundDecision || action == .delivery && deliveryAction == "RETURN_TO_ORIGIN" && fault != "CUSTOMER" {
                        TextField(action == .issue ? "Refund amount in paise (required)" : "Refund amount in paise (optional)", text: $amount)
                        Text("Enter a whole number of paise, not rupees. The server enforces the refundable limit.").font(.caption)
                    }
                    if [.fail, .delivery, .issue, .handoff, .cancel].contains(action) { TextField("Reason for this decision", text: $reason, axis: .vertical).lineLimit(3...6) }
                }
                Section("Confirmation") {
                    Toggle("I reviewed this order, evidence and consequences", isOn: $accepted)
                    if [.handoff, .fail, .cancel, .refund].contains(action) { TextField("Type \(reviewed.order.displayOrderNumber)", text: $orderConfirmation) }
                    if !eligible { Text("Complete all fields, use current permissions and refresh/reopen this review if the trace changed or is older than one minute.").font(.caption).foregroundStyle(.secondary) }
                    Button("Confirm \(action.title)", role: [.handoff, .fail, .cancel].contains(action) ? .destructive : nil) {
                        guard let request, eligible else { return }
                        Task { await model.submit(request, reviewed: reviewed); dismiss() }
                    }.disabled(!eligible)
                }
            }
            .navigationTitle("Review Admin action")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel review") { dismiss() } } }
        }
    }
    private var eligible: Bool {
        guard accepted, let request, model.allowed(request, reviewed: reviewed) else { return false }
        return (![.handoff, .fail, .cancel, .refund].contains(action) || orderConfirmation == reviewed.order.displayOrderNumber) && (action != .handoff || loadedEvidenceID == identifier)
    }
    private func evidenceControls(_ records: [DastakAdminTraceRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                if let path = record.text("objectPath"), let id = record.uuid() {
                    Button("View evidence \(id.uuidString.prefix(8))") {
                        evidenceURL = nil; loadedEvidenceID = nil
                        let generation = UUID(); evidenceGeneration = generation; requestedEvidenceID = id.uuidString
                        Task {
                            do {
                                let url = try await model.evidenceURL(path: path, reviewed: reviewed)
                                guard evidenceGeneration == generation else { return }
                                evidenceURL = url; evidenceMessage = nil; if action == .handoff { identifier = id.uuidString }
                            } catch { if evidenceGeneration == generation { evidenceMessage = "Evidence could not be loaded. Refresh the trace and review again." } }
                        }
                    }
                }
            }
            if let evidenceMessage { Text(evidenceMessage).font(.caption).foregroundStyle(.orange) }
            if let evidenceURL {
                AsyncImage(url: evidenceURL) { phase in
                    switch phase {
                    case .empty: ProgressView("Loading evidence")
                    case let .success(image): image.resizable().scaledToFit().frame(maxHeight: 320).onAppear { loadedEvidenceID = requestedEvidenceID }
                    case .failure: Text("Evidence image unavailable. No handoff approval enabled.").foregroundStyle(.orange)
                    @unknown default: EmptyView()
                    }
                }.id(evidenceURL)
            }
        }
    }
    private var request: DastakAdminExecutionRequest? {
        var request = DastakAdminExecutionRequest(operation: action)
        switch action {
        case .offer: request.recoveryCaseId = target.uuid(); request.branchId = UUID(uuidString: identifier); request.expectedVersion = target.integer("version")
        case .fail: request.recoveryCaseId = target.uuid(); request.expectedVersion = target.integer("version"); request.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        case .delivery:
            request.recoveryCaseId = target.uuid(); request.expectedVersion = target.integer("version"); request.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines); request.action = deliveryAction; request.faultSource = fault
            if deliveryAction == "RESUME_DELIVERY", !address.isEmpty || !latitude.isEmpty || !longitude.isEmpty {
                guard let lat = Double(latitude), let lon = Double(longitude) else { return nil }
                request.correctedAddress = .init(line1: address, latitude: lat, longitude: lon)
            }
            if deliveryAction == "RETURN_TO_ORIGIN", fault != "CUSTOMER", !amount.isEmpty { guard let value = Int(amount) else { return nil }; request.refundAmountPaise = value }
        case .issue:
            request.issueId = target.uuid(); request.expectedVersion = target.integer("version"); request.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines); request.decision = decision
            if refundDecision { request.refundAmountPaise = Int(amount); request.faultSource = fault }
            if decision == "PHYSICAL_RETURN" { request.returnPackageCount = Int(count) }
        case .rider: request.returnMissionId = target.uuid(); request.expectedVersion = target.integer("version"); request.riderId = UUID(uuidString: identifier)
        case .refund: request.orderId = reviewed.order.id; request.refundId = target.uuid(); request.entityType = "dastak_v1_order"
        case .settlement: request.settlementEntryId = target.uuid(); request.expectedVersion = target.integer("version")
        case .handoff: request.missionId = target.uuid(); request.expectedMissionVersion = target.integer("version"); request.deliveryEvidenceId = UUID(uuidString: identifier); request.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        case .cancel: request.orderId = reviewed.order.id; request.expectedVersion = reviewed.order.version; request.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return request.valid ? request : nil
    }
}

private func money(_ paise: Int, _ currency: String) -> String { String(format: "%.2f %@", Double(paise) / 100, currency) }
private func render(_ value: DastakAdminTraceValue) -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "Unavailable"
}
private func label(_ text: String) -> String { text.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }
