import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakAdminListingIntent: Identifiable {
    let row: DastakAdminMerchantListing
    var id: UUID { row.id }
    var visible: Bool { row.branch.customerListingVisible == false }
    var title: String { visible ? "Restore to Customer" : "Remove from Customer" }

    func canConfirm(reason: String, confirmation: String) -> Bool {
        row.supportsVisibilityChange &&
        (3...500).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count) &&
        (visible || confirmation == row.branch.displayName)
    }
}

@MainActor
final class DastakAdminRestaurantListingsModel: ObservableObject {
    struct Pending {
        let intent: DastakAdminListingIntent
        let reason: String
        let key: IdempotencyKey
    }
    @Published private(set) var rows: [DastakAdminMerchantListing] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var needsRefresh = true
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var pending: Pending?
    private let client: any DastakAdminRestaurantListingClient
    private var cursor: DastakAdminMerchantListingCursor?
    private var query = ""
    private var generation = 0

    init(client: any DastakAdminRestaurantListingClient) { self.client = client }

    var canReview: Bool { !isLoading && !isSubmitting && !needsRefresh && pending == nil }

    func load(query: String = "", append: Bool = false) async {
        guard !isSubmitting, !append || (!isLoading && hasMore && !needsRefresh) else { return }
        await fetch(query: query, append: append)
    }

    private func fetch(query: String, append: Bool = false) async {
        generation += 1
        let requestGeneration = generation
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = normalized
        isLoading = true
        needsRefresh = true
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let page = try await client.merchantListingPage(query: normalized.isEmpty ? nil : normalized,
                limit: 40, cursor: append ? cursor : nil, idempotencyKey: newKey())
            guard generation == requestGeneration, !Task.isCancelled else { return }
            // The shared governance feed contains both merchant types; only restaurants belong here.
            let restaurants = page.merchants.filter { $0.organization.merchantType == "RESTAURANT_CAFE" }
            var merged = append ? rows : []
            for row in restaurants {
                if let index = merged.firstIndex(where: { $0.id == row.id }) { merged[index] = row }
                else { merged.append(row) }
            }
            rows = merged
            cursor = page.nextCursor
            hasMore = page.hasMore && page.nextCursor != nil
            needsRefresh = false
            error = nil
        } catch {
            guard generation == requestGeneration else { return }
            self.error = "Restaurant listings could not be refreshed. Shown data may be outdated; changes are disabled until refresh succeeds."
        }
    }

    func submit(_ intent: DastakAdminListingIntent, reason: String, confirmation: String) async -> Bool {
        guard canReview, intent.canConfirm(reason: reason, confirmation: confirmation),
              rows.first(where: { $0.id == intent.id }) == intent.row else { return false }
        pending = Pending(intent: intent, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), key: newKey())
        return await retryPending()
    }

    func retryPending() async -> Bool {
        guard let action = pending, !isLoading, !isSubmitting else { return false }
        isSubmitting = true
        error = nil
        notice = nil
        defer { isSubmitting = false }
        do {
            let result = try await client.setRestaurantCustomerVisibility(branchID: action.intent.id,
                visible: action.intent.visible, expectedVersion: action.intent.row.branch.version,
                reason: action.reason, idempotencyKey: action.key)
            guard result.branchId == action.intent.id,
                  result.customerListingVisible == action.intent.visible,
                  result.version == action.intent.row.branch.version + 1 else {
                throw FunctionClientError.invalidResponse
            }
            pending = nil
            notice = action.intent.visible ? "Restaurant restored to Customer listings. This does not reopen a closed store."
                : "Restaurant removed from Customer listings. Existing orders and records are preserved."
            await fetch(query: query)
            return true
        } catch {
            // A known rejection requires fresh review. A timeout/unknown result must reuse the exact command.
            if case let FunctionClientError.api(statusCode: code, code: _, message: _) = error,
               [400, 401, 403, 404, 409, 422].contains(code) {
                pending = nil
                await fetch(query: query)
                self.error = "The server rejected this change. Refresh and review the current restaurant state before trying again."
            } else {
                self.error = "The result could not be verified. Retry the reviewed action to check the same request; do not submit a different change."
            }
            return false
        }
    }

    private func newKey() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
}

struct DastakAdminRestaurantListingsView: View {
    @ObservedObject private var model: DastakAdminRestaurantListingsModel
    @State private var query = ""
    @State private var intent: DastakAdminListingIntent?

    init(model: DastakAdminRestaurantListingsModel) {
        self.model = model
    }

    var body: some View {
        List {
            Section {
                Text("Closed restaurants stay listed unless Admin removes them. Removal changes Customer visibility only—not menus, store hours, suspension, orders or financial history.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let notice = model.notice { Section { Text(notice).foregroundStyle(.secondary) } }
            if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            if let action = model.pending {
                Section("Unverified action") {
                    Text("\(action.intent.title): \(action.intent.row.organization.displayName) / \(action.intent.row.branch.displayName)")
                    Text("Reason: \(action.reason)").font(.subheadline)
                    Button("Retry reviewed action") { Task { _ = await model.retryPending() } }
                        .disabled(model.isLoading || model.isSubmitting)
                }
            }
            if model.isLoading || model.isSubmitting { ProgressView(model.isSubmitting ? "Checking action" : "Loading listings") }
            if model.rows.isEmpty, !model.isLoading, model.error == nil {
                Text(model.hasMore ? "No restaurants on this page. Load more to continue." : "No restaurants match this search.")
            }
            ForEach(model.rows) { row in
                Section {
                    Text(row.organization.displayName).font(.headline)
                    Text(row.branch.displayName)
                    LabeledContent("Customer listing", value: listingLabel(row))
                    LabeledContent("Store", value: row.branch.operationalState.isOpen && row.branch.operationalState.acceptingOrders ? "Accepting orders" : "Closed / not accepting orders")
                    LabeledContent("Organization", value: row.organization.status)
                    LabeledContent("Branch", value: row.branch.status)
                    Text("Branch ID: \(row.id.uuidString)").font(.caption).textSelection(.enabled)
                    Button(row.branch.customerListingVisible == false ? "Restore to Customer" : "Remove from Customer") {
                        intent = DastakAdminListingIntent(row: row)
                    }
                    .disabled(!model.canReview || !row.supportsVisibilityChange)
                    .accessibilityIdentifier("dastak.admin.restaurant.visibility.\(row.id)")
                }
            }
            if model.hasMore {
                Button("Load more branches") { Task { await model.load(query: query, append: true) } }
                    .disabled(model.isLoading || model.isSubmitting || model.needsRefresh)
            }
        }
        .navigationTitle("Restaurant listings")
        .searchable(text: $query, prompt: "Organization, branch or exact ID")
        .onSubmit(of: .search) { Task { await model.load(query: query) } }
        .task { await model.load() }
        .refreshable { await model.load(query: query) }
        .toolbar {
            Button { Task { await model.load(query: query) } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.isLoading || model.isSubmitting).accessibilityLabel("Refresh restaurant listings")
        }
        .sheet(item: $intent) { action in
            DastakAdminRestaurantVisibilityReview(model: model, intent: action)
        }
        .marketplacePage()
    }

    private func listingLabel(_ row: DastakAdminMerchantListing) -> String {
        guard let visible = row.branch.customerListingVisible else { return "Control unavailable" }
        return visible ? "Listed in Customer" : "Removed by Admin"
    }
}

private struct DastakAdminRestaurantVisibilityReview: View {
    @ObservedObject var model: DastakAdminRestaurantListingsModel
    let intent: DastakAdminListingIntent
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Restaurant branch") {
                    Text(intent.row.organization.displayName).font(.headline)
                    Text(intent.row.branch.displayName)
                    Text("\(intent.row.id.uuidString) · Version \(intent.row.branch.version)").font(.caption)
                }
                Section("What changes") {
                    Text(intent.visible ? "Removed from Customer → Listed in Customer" : "Listed in Customer → Removed from Customer")
                    Text("Open/closed state, suspension, menus, orders and financial history remain unchanged. Already-confirmed orders continue. Restoring a listing does not reopen a closed store.")
                }
                Section("Required reason") {
                    TextField("Explain why this listing should change", text: $reason, axis: .vertical)
                        .disabled(model.pending != nil || model.isSubmitting)
                }
                if !intent.visible {
                    Section("Type the branch name to confirm removal") {
                        Text(intent.row.branch.displayName).textSelection(.enabled)
                        TextField("Exact branch name", text: $confirmation)
                            .autocorrectionDisabled().disabled(model.pending != nil || model.isSubmitting)
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                Button(model.pending == nil ? intent.title : "Retry reviewed action", role: intent.visible ? nil : .destructive) {
                    Task {
                        let success: Bool
                        if model.pending != nil { success = await model.retryPending() }
                        else { success = await model.submit(intent, reason: reason, confirmation: confirmation) }
                        if success { dismiss() }
                    }
                }
                .disabled(model.isSubmitting || model.isLoading || (model.pending == nil &&
                    (!model.canReview || !intent.canConfirm(reason: reason, confirmation: confirmation))))
                .accessibilityIdentifier("dastak.admin.restaurant.confirm")
            }
            .navigationTitle(intent.title)
            .toolbar { Button("Close") { dismiss() }.disabled(model.isSubmitting) }
            .interactiveDismissDisabled(model.isSubmitting)
        }
    }
}
