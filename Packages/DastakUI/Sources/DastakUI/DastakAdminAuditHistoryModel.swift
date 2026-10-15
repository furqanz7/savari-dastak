import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakAdminAuditDraft {
    var actor = ""
    var action = ""
    var resourceType = ""
    var resourceID = ""
    var orderID = ""
    var branchID = ""
    var accountID = ""
    var eventID = ""
    var from: Date?
    var to: Date?
    func filters() -> DastakAdminAuditFilters? {
        func clean(_ value: String) -> String? {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        for value in [resourceID, orderID, branchID, accountID] {
            if let value = clean(value), UUID(uuidString: value) == nil { return nil }
        }
        var result = DastakAdminAuditFilters()
        result.actorQuery = clean(actor); result.action = clean(action); result.resourceType = clean(resourceType)
        result.resourceId = clean(resourceID).flatMap(UUID.init(uuidString:))
        result.orderId = clean(orderID).flatMap(UUID.init(uuidString:))
        result.branchId = clean(branchID).flatMap(UUID.init(uuidString:))
        result.accountId = clean(accountID).flatMap(UUID.init(uuidString:))
        result.eventId = clean(eventID)
        let formatter = ISO8601DateFormatter()
        result.fromOccurredAt = from.map { formatter.string(from: $0) }
        result.toOccurredAt = to.map { formatter.string(from: $0) }
        return result.isValid ? result : nil
    }
}

@MainActor
final class DastakAdminAuditHistoryModel: ObservableObject {
    @Published private(set) var events: [DastakAdminAuditEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = false
    @Published private(set) var needsRefresh = true
    @Published private(set) var error: String?
    @Published var draft = DastakAdminAuditDraft()
    private var filters = DastakAdminAuditFilters()
    private var cursor: DastakAdminAuditCursor?
    private var generation = 0
    private let client: any DastakAdminAuditHistoryClient
    init(client: any DastakAdminAuditHistoryClient) { self.client = client }
    func applyDraft() async {
        guard let filters = draft.filters() else {
            error = "Check complete UUIDs, v1: or legacy: event IDs, filter lengths and the start/end time range."
            return
        }
        if self.filters != filters { events = []; cursor = nil; hasMore = false }
        self.filters = filters
        await refresh()
    }
    func clearFilters() async { draft = .init(); await applyDraft() }
    func refresh() async { await fetch(append: false) }
    func loadMore() async {
        guard !isLoading, !needsRefresh, hasMore else { return }
        await fetch(append: true)
    }
    private func fetch(append: Bool) async {
        generation += 1
        let current = generation
        isLoading = true; needsRefresh = true
        defer { if generation == current { isLoading = false } }
        do {
            let page = try await client.auditHistory(filters: filters, limit: 50, cursor: append ? cursor : nil,
                idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!)
            guard generation == current, !Task.isCancelled else { return }
            var merged = append ? events : []
            for event in page.events where !merged.contains(where: { $0.id == event.id }) { merged.append(event) }
            events = merged; cursor = page.nextCursor; hasMore = page.hasMore && cursor != nil
            error = nil; needsRefresh = false
        } catch {
            guard generation == current else { return }
            if case let FunctionClientError.api(statusCode: code, code: _, message: _) = error, [401, 403].contains(code) { events = [] }
            self.error = "Audit history could not be refreshed. Any retained events may be outdated. An authorized refresh is required before loading older events."
        }
    }
}
