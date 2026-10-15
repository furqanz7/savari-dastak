import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakAdminMerchantGovernanceView: View {
    @ObservedObject var model: DastakAdminMerchantGovernanceModel
    @State private var query = ""
    @State private var intent: DastakAdminMerchantIntent?
    @State private var editing: DastakAdminMerchantListing?

    var body: some View {
        List {
            Section {
                Text("Govern Merchant eligibility and correct reviewed branch records. Store open/closed settings, Customer listing removal and operational pauses are separate controls.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let notice = model.notice { Text(notice).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if let action = model.pending {
                Section("Unverified action") {
                    Text("\(action.intent.title): \(action.intent.targetName)")
                    Text("Reason: \(action.reason)")
                    Button("Retry reviewed action") { Task { _ = await model.retryPending() } }
                        .disabled(model.isLoading || model.isSubmitting)
                }
            }
            if model.isLoading || model.isSubmitting { ProgressView(model.isSubmitting ? "Checking action" : "Loading Merchants") }
            if model.rows.isEmpty, !model.isLoading, model.error == nil { Text("No Merchant branches match this search.") }
            ForEach(model.rows) { row in
                Section {
                    Text(row.organization.displayName).font(.headline)
                    Text("\(row.branch.displayName) · \(row.organization.merchantType.replacingOccurrences(of: "_", with: " "))")
                    LabeledContent("Organization", value: row.organization.status)
                    LabeledContent("Branch", value: row.branch.status)
                    LabeledContent("Merchant setting", value: "\(row.branch.operationalState.isOpen ? "Open" : "Closed") · \(row.branch.operationalState.acceptingOrders ? "Accepting orders" : "Not accepting orders")")
                    if let pause = row.branch.operationalPause, pause.active { Text("Operational pause: \(pause.reason)").foregroundStyle(.orange) }
                    Text(row.branch.normalizedAddress?.summary ?? "Pickup address unavailable").font(.subheadline)
                    Text("Service zone: \(row.branch.serviceZone?.name ?? "Unavailable") · Capacity: \(row.branch.capacityLimit.map(String.init) ?? "Unavailable")").font(.caption)
                    Text("Coordinates: \(row.branch.latitude.map { String($0) } ?? "Unavailable"), \(row.branch.longitude.map { String($0) } ?? "Unavailable")").font(.caption)
                    Text("Branch ID: \(row.id.uuidString)").font(.caption).textSelection(.enabled)
                    ForEach([DastakAdminMerchantTarget.organization, .branch], id: \.rawValue) { target in
                        let action = DastakAdminMerchantIntent(row: row, kind: .status(target))
                        Button(action.title) { intent = action }.disabled(!model.canReview || action.blocker != nil)
                        if let blocker = action.blocker { Text(blocker).font(.caption).foregroundStyle(.secondary) }
                    }
                    Button("Correct branch details") { editing = row }
                        .disabled(!model.canReview || !["ACTIVE", "SUSPENDED"].contains(row.branch.status) || row.branch.version < 1)
                }
            }
            if model.hasMore {
                Button("Load more branches") { Task { await model.load(query: query, append: true) } }
                    .disabled(model.isLoading || model.isSubmitting || model.needsRefresh)
            }
        }
        .navigationTitle("Merchant governance")
        .searchable(text: $query, prompt: "Organization, branch or exact ID")
        .onSubmit(of: .search) { Task { await model.load(query: query) } }
        .task { await model.load(query: query) }
        .refreshable { await model.load(query: query) }
        .toolbar {
            Button { Task { await model.load(query: query) } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.isLoading || model.isSubmitting).accessibilityLabel("Refresh Merchant governance")
        }
        .sheet(item: $intent) { DastakAdminMerchantReview(model: model, intent: $0) }
        .sheet(item: $editing) { DastakAdminBranchEditor(model: model, row: $0) }
        .marketplacePage()
    }
}

private struct DastakAdminMerchantReview: View {
    @ObservedObject var model: DastakAdminMerchantGovernanceModel
    let intent: DastakAdminMerchantIntent
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirmation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Reviewed record") {
                    Text(intent.row.organization.displayName).font(.headline)
                    Text(intent.targetName)
                    Text("\(intent.targetID.uuidString) · Version \(intent.expectedVersion)").font(.caption)
                }
                Section("Changes") { ForEach(intent.reviewLines, id: \.self) { Text($0) } }
                Section("Consequences") { Text(intent.consequence) }
                if let blocker = intent.blocker { Text(blocker).foregroundStyle(.red) }
                Section("Required reason") {
                    TextField("Explain this reviewed action", text: $reason, axis: .vertical)
                        .disabled(model.pending != nil || model.isSubmitting)
                }
                if intent.requiresName {
                    Section("Type the exact name to confirm") {
                        Text(intent.targetName).textSelection(.enabled)
                        TextField("Exact name", text: $confirmation).autocorrectionDisabled()
                            .disabled(model.pending != nil || model.isSubmitting)
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                Button(model.pending == nil ? intent.title : "Retry reviewed action") {
                    Task {
                        let success = model.pending == nil
                            ? await model.submit(intent, reason: reason, confirmation: confirmation)
                            : await model.retryPending()
                        if success { dismiss() }
                    }
                }
                .disabled(model.isSubmitting || model.isLoading || (model.pending == nil &&
                    (!model.canReview || !intent.canConfirm(reason: reason, confirmation: confirmation))))
                .accessibilityIdentifier("dastak.admin.merchant.confirm")
            }
            .navigationTitle(intent.title)
            .toolbar { Button("Close") { dismiss() }.disabled(model.isSubmitting) }
            .interactiveDismissDisabled(model.isSubmitting)
        }
    }
}

private struct DastakAdminBranchEditor: View {
    @ObservedObject var model: DastakAdminMerchantGovernanceModel
    let row: DastakAdminMerchantListing
    @State private var draft: DastakAdminBranchDraft
    @State private var reviewed: DastakAdminMerchantIntent?
    @Environment(\.dismiss) private var dismiss
    init(model: DastakAdminMerchantGovernanceModel, row: DastakAdminMerchantListing) {
        self.model = model; self.row = row; _draft = State(initialValue: DastakAdminBranchDraft(row: row))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Branch") { TextField("Display name", text: $draft.displayName) }
                Section("Pickup address") {
                    TextField("Address line 1", text: $draft.line1)
                    TextField("Address line 2", text: $draft.line2)
                    TextField("City", text: $draft.city)
                    TextField("State", text: $draft.state)
                    TextField("Postal code", text: $draft.postalCode)
                    TextField("Country code", text: $draft.countryCode).autocorrectionDisabled()
                }
                Section("Routing and capacity") {
                    TextField("Latitude", text: $draft.latitude)
                    TextField("Longitude", text: $draft.longitude)
                    Picker("Active service zone", selection: $draft.serviceZoneID) {
                        Text("Choose a zone").tag(UUID?.none)
                        ForEach(model.zones.compactMap(\.id), id: \.self) { id in
                            Text(model.zones.first(where: { $0.id == id })?.name ?? id.uuidString).tag(UUID?.some(id))
                        }
                    }
                    TextField("Capacity (1–500)", text: $draft.capacityLimit)
                }
                Section {
                    Text("Review the exact pickup coordinates before changing them. The server verifies that the location is inside the active service zone. Active pickup/return work blocks destination changes.").font(.subheadline)
                    if let patch = draft.patch(for: row, zones: model.zones) {
                        let action = DastakAdminMerchantIntent(row: row, kind: .correction(patch))
                        if let blocker = action.blocker { Text(blocker).foregroundStyle(.red) }
                        Button("Review corrections") { reviewed = action }
                            .disabled(!model.canReview || action.blocker != nil)
                    } else { Text("Change at least one value. Name, address, coordinates, active zone and capacity must be valid before review.").foregroundStyle(.secondary) }
                }
            }
            .disabled(model.isSubmitting || model.pending != nil)
            .navigationTitle("Correct branch details")
            .toolbar { Button("Close") { dismiss() }.disabled(model.isSubmitting) }
            .sheet(item: $reviewed) { DastakAdminMerchantReview(model: model, intent: $0) }
            .onChange(of: model.notice) { if model.notice != nil && model.pending == nil { dismiss() } }
        }
    }
}
