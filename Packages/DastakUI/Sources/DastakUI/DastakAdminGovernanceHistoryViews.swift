import Foundation
import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakAdminDeliveryGovernanceView: View {
    @ObservedObject var model: DastakAdminDeliveryGovernanceModel
    @State private var intent: DastakAdminDeliveryIntent?
    var body: some View {
        List {
            Section {
                Text("Govern approved Delivery Partners without changing approval evidence, historical work or earnings. Active work and custody must be resolved before suspension.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Status filter", selection: $model.statusDraft) {
                    Text("All statuses").tag(Optional<DastakAdminRiderStatus>.none)
                    Text("Active").tag(Optional(DastakAdminRiderStatus.active))
                    Text("Suspended").tag(Optional(DastakAdminRiderStatus.suspended))
                }
                Button("Apply search and status") { Task { await model.load(query: model.queryDraft, status: model.statusDraft) } }
                    .disabled(model.isLoading || model.isSubmitting)
            }
            if let notice = model.notice { Text(notice).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if let command = model.pending {
                Section("Unverified action") {
                    Text("\(command.intent.title): \(command.intent.row.rider.displayName)")
                    Text("Reason: \(command.reason)")
                    Button("Retry reviewed action") { Task { _ = await model.retryPending() } }
                        .disabled(model.isLoading || model.isSubmitting)
                }
            }
            if model.isLoading || model.isSubmitting { ProgressView(model.isSubmitting ? "Checking action" : "Loading Delivery Partners") }
            if model.rows.isEmpty, !model.isLoading, model.error == nil { Text("No Delivery Partners match these filters.") }
            ForEach(model.rows) { row in
                Section {
                    Text(row.rider.displayName).font(.headline)
                    Text(row.rider.maskedPhoneNumber ?? row.id.uuidString).font(.subheadline)
                    LabeledContent("Governance", value: row.governance.status.rawValue)
                    LabeledContent("Availability", value: row.availability.status.rawValue)
                    LabeledContent("Approval", value: row.approval.status)
                    LabeledContent("Transport", value: row.transportMethod)
                    LabeledContent("Governance version", value: String(row.governance.version))
                    LabeledContent("Service area", value: row.availability.serviceZone?.name ?? "Not active")
                    LabeledContent("Last seen", value: adminHistoryWhen(row.availability.lastSeenAt))
                    if let until = row.availability.availableUntil { LabeledContent("Availability until", value: adminHistoryWhen(until)) }
                    Text("Identity evidence: \(row.approval.hasIdentityEvidence ? "Present" : "Missing") · Vehicle evidence: \(row.approval.hasVehicleEvidence ? "Present" : "Not present / not applicable")")
                        .font(.caption).foregroundStyle(.secondary)
                    if let work = row.activeWork {
                        Text("Active \(work.domain.rawValue) work: \(work.id.uuidString)").font(.caption).foregroundStyle(.orange)
                    } else { Text("No active work reported. The server checks custody again before suspension.").font(.caption) }
                    if let reason = row.governance.reason { Text("Suspension reason: \(reason)").font(.subheadline) }
                    Text("Account: \(row.id.uuidString)\nApplication: \(row.approval.applicationId.uuidString)").font(.caption).textSelection(.enabled)
                    let action = DastakAdminDeliveryIntent(row: row)
                    Button(action.title) { intent = action }.disabled(!model.canReview || action.blocker != nil)
                    if let blocker = action.blocker { Text(blocker).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if model.hasMore {
                Button("Load more Delivery Partners") { Task { await model.loadMore() } }
                    .disabled(model.isLoading || model.isSubmitting || model.needsRefresh)
            }
        }
        .navigationTitle("Delivery Partners")
        .searchable(text: $model.queryDraft, prompt: "Rider, phone or exact account/application ID")
        .onSubmit(of: .search) { Task { await model.load(query: model.queryDraft, status: model.statusDraft) } }
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .toolbar {
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.isLoading || model.isSubmitting).accessibilityLabel("Refresh Delivery Partners")
        }
        .sheet(item: $intent) { DastakAdminDeliveryReview(model: model, intent: $0) }
        .marketplacePage()
    }
}

private struct DastakAdminDeliveryReview: View {
    @ObservedObject var model: DastakAdminDeliveryGovernanceModel
    let intent: DastakAdminDeliveryIntent
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirmation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    Text(intent.row.rider.displayName).font(.headline)
                    Text(intent.row.id.uuidString).font(.caption).textSelection(.enabled)
                    Text("\(intent.row.governance.status.rawValue) · \(intent.row.availability.status.rawValue) → \(intent.target.rawValue) · OFFLINE")
                    Text("Expected governance version: \(intent.row.governance.version)")
                    Text(intent.consequence)
                    if let blocker = intent.blocker { Text(blocker).foregroundStyle(.red) }
                }
                Section("Required reason") {
                    TextField("Explain the reviewed action (3–500 characters)", text: $reason, axis: .vertical)
                    if intent.target == .suspended { TextField("Type \(intent.row.rider.displayName) to confirm", text: $confirmation) }
                }.disabled(model.pending != nil || model.isSubmitting)
                if let error = model.error { Text(error).foregroundStyle(.red) }
                if model.pending != nil {
                    Text("An unverified request is retained in this Admin session. Do not create another action.")
                    Button("Retry original reviewed action") { Task { if await model.retryPending() { dismiss() } } }
                        .disabled(model.isLoading || model.isSubmitting)
                } else {
                    Button(intent.title) {
                        Task { if await model.submit(intent, reason: reason, confirmation: confirmation) { dismiss() } }
                    }.disabled(!model.canReview || !intent.canConfirm(reason: reason, confirmation: confirmation))
                }
                if model.isSubmitting { ProgressView("Checking authoritative result") }
            }
            .navigationTitle(intent.title)
            .toolbar { Button("Close") { dismiss() }.disabled(model.isSubmitting) }
            .interactiveDismissDisabled(model.isSubmitting)
        }
    }
}

struct DastakAdminAuditHistoryView: View {
    @ObservedObject var model: DastakAdminAuditHistoryModel
    var body: some View {
        List {
            Section {
                Text("Read-only, reviewed events from current and legacy Dastak systems. This screen cannot edit or remove history.")
                    .font(.subheadline).foregroundStyle(.secondary)
                DisclosureGroup("Search and filters") {
                    TextField("Actor name or account ID", text: $model.draft.actor)
                    TextField("Exact action", text: $model.draft.action)
                    TextField("Exact resource type", text: $model.draft.resourceType)
                    TextField("Resource UUID", text: $model.draft.resourceID)
                    TextField("Order UUID", text: $model.draft.orderID)
                    TextField("Branch UUID", text: $model.draft.branchID)
                    TextField("Account UUID", text: $model.draft.accountID)
                    TextField("Event: v1:123 or legacy:UUID", text: $model.draft.eventID)
                    Toggle("Start time", isOn: Binding(get: { model.draft.from != nil }, set: { model.draft.from = $0 ? Date() : nil }))
                    if model.draft.from != nil {
                        DatePicker("From", selection: Binding(get: { model.draft.from ?? Date() }, set: { model.draft.from = $0 }))
                    }
                    Toggle("End time", isOn: Binding(get: { model.draft.to != nil }, set: { model.draft.to = $0 ? Date() : nil }))
                    if model.draft.to != nil {
                        DatePicker("To", selection: Binding(get: { model.draft.to ?? Date() }, set: { model.draft.to = $0 }))
                    }
                    Button("Apply filters") { Task { await model.applyDraft() } }.disabled(model.isLoading)
                    Button("Clear all filters") { Task { await model.clearFilters() } }.disabled(model.isLoading)
                }
                .autocorrectionDisabled()
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if model.isLoading { ProgressView("Loading audit history") }
            if model.events.isEmpty, !model.isLoading, model.error == nil { Text("No audit events match these filters.") }
            ForEach(model.events) { event in
                Section {
                    Text(event.action.replacingOccurrences(of: "_", with: " ")).font(.headline)
                    LabeledContent("Source", value: event.source == .current ? "Current" : "Legacy")
                    LabeledContent("When", value: adminHistoryWhen(event.occurredAt))
                    LabeledContent("Actor", value: event.actor.displayName)
                    if let id = event.actor.id { Text("Actor ID: \(id.uuidString)").font(.caption).textSelection(.enabled) }
                    Text("Resource: \(event.resource.type)\(event.resource.id.map { " · " + $0.uuidString } ?? "")").font(.subheadline)
                    if let reason = event.reason { Text("Reason: \(reason)") }
                    ForEach(event.summary.values.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: event.summary.values[key]?.display ?? "")
                    }
                    if let id = event.references.orderId { Text("Order: \(id.uuidString)").font(.caption) }
                    if let id = event.references.branchId { Text("Branch: \(id.uuidString)").font(.caption) }
                    if let id = event.references.accountId { Text("Account: \(id.uuidString)").font(.caption) }
                    Text("Event: \(event.eventId)").font(.caption).textSelection(.enabled)
                }
            }
            if model.hasMore {
                Button("Load older events") { Task { await model.loadMore() } }.disabled(model.isLoading || model.needsRefresh)
            }
        }
        .navigationTitle("Audit history")
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .toolbar {
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.isLoading).accessibilityLabel("Refresh audit history")
        }
        .marketplacePage()
    }
}

private func adminHistoryWhen(_ value: String?) -> String {
    guard let value else { return "Not available" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: value)
    if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: value) }
    return date?.formatted(date: .abbreviated, time: .shortened) ?? "Not available"
}
