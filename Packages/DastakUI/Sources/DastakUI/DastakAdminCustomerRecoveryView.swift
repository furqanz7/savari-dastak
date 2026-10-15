import SwiftUI
import MarketplaceInfrastructure

struct DastakAdminCustomerRecoveryView: View {
    @ObservedObject var model: DastakAdminCustomerRecoveryModel
    @State private var query = ""
    @State private var replacementPhones: [UUID: String] = [:]
    @State private var intent: DastakAdminCustomerRecoveryIntent?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Text("Review the exact Customer account before revoking sessions or correcting contact data. Apple/Google identity and email cannot be changed here.").font(.subheadline).foregroundStyle(.secondary)
                Button("Search customers") { Task { await model.load(query: query) } }.disabled(model.busy || query.trimmingCharacters(in: .whitespacesAndNewlines).count > 100)
            }
            if let notice = model.notice { Text(notice).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("admin-customer-recovery-error") }
            if let pending = model.pending {
                Section("Saved action needs recovery") {
                    Text(pending.action == .phone ? "Contact-phone correction" : "\(pending.scope ?? "Unknown") session revocation").bold()
                    Text("Customer account \(pending.accountID.uuidString)").font(.caption).textSelection(.enabled)
                    if let phone = pending.replacementPhone { Text("Replacement: \(DastakAdminCustomerRecoveryContract.mask(phone))").font(.caption) }
                    Text("Retry uses the saved customer, scope, phone/session, reason and original request key. Edited form values cannot replace it.").font(.caption)
                    Button(pending.acknowledged ? "Finish local recovery" : "Retry original action") { Task { await model.retry() } }.disabled(model.busy)
                }
            }
            if model.loading || model.busy { ProgressView(model.busy ? "Securing recovery action" : "Loading customers") }
            if !model.current { Text("Records are not current. New changes require a successful authorized refresh.").font(.caption).foregroundStyle(.secondary) }
            if model.current && model.rows.isEmpty { Text("No customers match this search.") }
            ForEach(model.rows) { row in
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.account.displayName).font(.headline)
                        Text(row.account.maskedPhoneNumber).font(.subheadline)
                        if let email = row.account.email { Text(email).font(.caption).textSelection(.enabled) }
                        Text("Account \(row.id.uuidString)").font(.caption).textSelection(.enabled)
                    }
                    LabeledContent("Account", value: row.account.accountState)
                    LabeledContent("Customer", value: row.account.customerState)
                    LabeledContent("Sign-in identities", value: row.identityProviders.isEmpty ? "None reported" : row.identityProviders.joined(separator: " + ").capitalized)
                    Text("Updated \(customerRecoveryWhen(row.updatedAt))").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Sessions & contact recovery") {
                        LabeledContent("Active sessions", value: String(row.activeSessionCount))
                        if row.sessions.isEmpty { Text("No active account sessions reported in this read.").font(.caption) }
                        ForEach(row.sessions) { session in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(session.deviceName, systemImage: session.platform == "ios" ? "iphone" : "laptopcomputer")
                                Text("\(session.appName) · \(session.platform) · last seen \(customerRecoveryWhen(session.lastSeenAt))").font(.caption)
                                Text(session.id.uuidString).font(.caption2).textSelection(.enabled)
                                Button("Review session revocation", role: .destructive) { intent = .init(row: row, action: .sessions, sessionID: session.id, replacementPhone: nil) }
                                    .disabled(model.blocksActions || !model.fresh(row) || !active(row))
                            }.padding(.vertical, 6)
                        }
                        if row.activeSessionCount > 0 {
                            Button("Review revoke all sessions", role: .destructive) { intent = .init(row: row, action: .sessions, sessionID: nil, replacementPhone: nil) }
                                .disabled(model.blocksActions || !model.fresh(row) || !active(row))
                        }
                        LabeledContent("Phone claim", value: "\(row.phoneClaim.state) · version \(row.phoneClaim.version)")
                        Text("Verification source: \(row.phoneClaim.verificationSource)").font(.caption)
                        TextField("Replacement phone, e.g. +919876543210", text: Binding(get: { replacementPhones[row.id] ?? "" }, set: { replacementPhones[row.id] = $0 })).textContentType(.none).autocorrectionDisabled()
                        let replacement = (replacementPhones[row.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        Button("Review contact correction") { intent = .init(row: row, action: .phone, sessionID: nil, replacementPhone: replacement) }
                            .disabled(model.blocksActions || !model.fresh(row) || !active(row) || row.phoneClaim.version < 1 || !DastakAdminCustomerRecoveryContract.phone(replacement) || replacement == row.account.currentPhoneNumber)
                        if row.phoneClaim.version == 0 { Text("The phone claim is missing. This screen cannot invent or merge a claim.").font(.caption).foregroundStyle(.orange) }
                        Text("Phone correction creates an unverified Dastak contact claim. Existing submitted orders retain their recipient snapshots.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if model.cursor != nil { Button("Load more customers") { Task { await model.load(append: true) } }.disabled(model.loading || model.busy || !model.current) }
            else if model.current && !model.rows.isEmpty { Text("All matching customers loaded for this successful search.").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Customer recovery")
        .searchable(text: $query, prompt: "Name, phone, email or exact account ID")
        .onSubmit(of: .search) { Task { await model.load(query: query) } }
        .task { await model.load(query: query) }
        .refreshable { await model.load(query: query) }
        .toolbar { Button { Task { await model.load(query: query) } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy).accessibilityLabel("Refresh customer recovery") }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load(query: query) } } else { model.markStale() } }
        .onDisappear { model.markStale(); replacementPhones = [:] }
        .sheet(item: $intent) { DastakAdminCustomerRecoveryReview(model: model, intent: $0) }
        .marketplacePage()
    }
    private func active(_ row: DastakAdminCustomerRecoveryRow) -> Bool { row.account.accountState == "ACTIVE" && row.account.customerState == "ACTIVE" }
}

private struct DastakAdminCustomerRecoveryReview: View {
    @ObservedObject var model: DastakAdminCustomerRecoveryModel
    let intent: DastakAdminCustomerRecoveryIntent
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirmation = ""
    @State private var acknowledged = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Reviewed customer") {
                    Text(intent.row.account.displayName).font(.headline)
                    Text(intent.row.account.maskedPhoneNumber)
                    Text(intent.row.id.uuidString).font(.caption).textSelection(.enabled)
                    if intent.action == .phone {
                        Text("Current claim version \(intent.row.phoneClaim.version)")
                        Text("Replacement \(intent.replacementPhone ?? "Unknown")")
                        Text("This releases the reviewed contact claim and establishes the replacement as unverified. Apple/Google identity and email stay unchanged. Accounts are not merged, and existing order-recipient snapshots are not rewritten.").font(.subheadline)
                    } else if let id = intent.sessionID, let session = intent.row.sessions.first(where: { $0.id == id }) {
                        Text("\(session.deviceName) · \(session.appName) · \(session.platform)")
                        Text("Session \(id.uuidString)").font(.caption).textSelection(.enabled)
                        Text("Only this reviewed session loses refresh capability and Dastak API access. Other sessions are not selected for revocation.").font(.subheadline).foregroundStyle(.orange)
                    } else {
                        Text("\(intent.row.activeSessionCount) active sessions in the reviewed read")
                        Text("Every session active at execution time is affected, including sessions opened after this review. Devices must sign in again. If this account also uses another Dastak role—or is your own account—those sessions may be affected too.").font(.subheadline).foregroundStyle(.orange)
                    }
                }
                Section("Confirm action") {
                    TextField("Reason (3–\(intent.action == .phone ? 500 : 200) characters)", text: $reason, axis: .vertical).lineLimit(3...6)
                    Text("Type \(intent.confirmationValue) to confirm").font(.caption).textSelection(.enabled)
                    TextField("Exact confirmation", text: $confirmation).autocorrectionDisabled().textContentType(.none)
                    Toggle("I reviewed the exact account and consequences", isOn: $acknowledged)
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        let allowed = model.canConfirm(intent, reason: reason, confirmation: confirmation, acknowledged: acknowledged, now: context.date)
                        VStack(alignment: .leading, spacing: 8) {
                            if !model.fresh(intent.row, now: context.date) { Text("This record changed or the review expired. Close, refresh and review again.").font(.caption).foregroundStyle(.orange) }
                            Button(intent.title, role: intent.action == .sessions ? .destructive : nil) {
                                Task {
                                    let completed = await model.submit(intent, reason: reason, confirmation: confirmation, acknowledged: acknowledged)
                                    // Close this immutable review after the attempt. Rejections stay visible
                                    // on the directory; another action requires opening a fresh review.
                                    if completed || !model.busy { dismiss() }
                                }
                            }.disabled(!allowed)
                        }
                    }
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }
            .navigationTitle(intent.title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel review") { dismiss() }.disabled(model.busy) } }
            .interactiveDismissDisabled(model.busy)
        }
    }
}
private func customerRecoveryWhen(_ text: String) -> String { DastakAdminCustomerRecoveryContract.date(text)?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown" }
