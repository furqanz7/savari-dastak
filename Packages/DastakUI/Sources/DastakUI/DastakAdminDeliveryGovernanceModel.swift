import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakAdminDeliveryIntent: Identifiable {
    let row: DastakAdminDeliveryPartner
    var id: UUID { row.id }
    var target: DastakAdminRiderStatus { row.governance.status == .active ? .suspended : .active }
    var title: String { target == .suspended ? "Suspend Delivery Partner" : "Reactivate Delivery Partner" }
    var blocker: String? {
        guard row.governance.version > 0, row.governance.version < Int.max,
              row.approval.verificationVersion > 0, row.approval.status == "approved",
              row.availability.version >= 0 else { return "Rider eligibility could not be verified. Refresh before acting." }
        if target == .suspended, row.activeWork != nil {
            return "Resolve active work or physical custody through the existing recovery/release workflow before suspension."
        }
        return nil
    }
    var consequence: String {
        target == .suspended
            ? "Suspension prevents availability and new delivery, return, courier and parcel work. Active work or physical custody blocks it. History, evidence and earnings remain intact."
            : "Eligibility is restored, but the rider stays offline and must go online through the normal availability flow. History, evidence and earnings remain unchanged."
    }
    func canConfirm(reason: String, confirmation: String) -> Bool {
        blocker == nil && (3...500).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count) &&
            (target != .suspended || confirmation == row.rider.displayName)
    }
}

@MainActor
final class DastakAdminDeliveryGovernanceModel: ObservableObject {
    struct Pending { let intent: DastakAdminDeliveryIntent; let reason: String; let key: IdempotencyKey }
    @Published private(set) var rows: [DastakAdminDeliveryPartner] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var needsRefresh = true
    @Published private(set) var pending: Pending?
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published var queryDraft = ""
    @Published var statusDraft: DastakAdminRiderStatus?
    private let client: any DastakAdminDeliveryGovernanceClient
    private var cursor: DastakAdminDeliveryCursor?
    private var query = ""
    private var status: DastakAdminRiderStatus?
    private var generation = 0
    init(client: any DastakAdminDeliveryGovernanceClient) { self.client = client }
    var canReview: Bool { !isLoading && !isSubmitting && !needsRefresh && pending == nil }

    func load(query: String, status: DastakAdminRiderStatus?) async {
        guard !isSubmitting else { return }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count <= 100 else { error = "Search must be 100 characters or fewer."; return }
        if self.query != query || self.status != status { rows = []; cursor = nil; hasMore = false }
        self.query = query; self.status = status
        await fetch()
    }
    func refresh() async { guard !isSubmitting else { return }; await fetch() }
    func loadMore() async {
        guard !isSubmitting, !isLoading, hasMore, !needsRefresh else { return }
        await fetch(append: true)
    }
    private func fetch(append: Bool = false) async {
        generation += 1
        let current = generation
        isLoading = true; needsRefresh = true
        defer { if generation == current { isLoading = false } }
        do {
            let page = try await client.deliveryGovernancePage(query: query.isEmpty ? nil : query, status: status,
                limit: 40, cursor: append ? cursor : nil, idempotencyKey: newKey())
            guard generation == current, !Task.isCancelled else { return }
            var merged = append ? rows : []
            for row in page.deliveryPartners {
                if let index = merged.firstIndex(where: { $0.id == row.id }) { merged[index] = row }
                else { merged.append(row) }
            }
            rows = merged; cursor = page.nextCursor; hasMore = page.hasMore && cursor != nil
            error = nil; needsRefresh = false
        } catch {
            guard generation == current else { return }
            if case let FunctionClientError.api(statusCode: code, code: _, message: _) = error, [401, 403].contains(code) { rows = [] }
            self.error = "Delivery Partner records could not be refreshed. Changes are disabled until an authorized refresh succeeds."
        }
    }
    func submit(_ intent: DastakAdminDeliveryIntent, reason: String, confirmation: String) async -> Bool {
        guard canReview, intent.canConfirm(reason: reason, confirmation: confirmation),
              rows.first(where: { $0.id == intent.id }) == intent.row else { return false }
        pending = Pending(intent: intent, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), key: newKey())
        return await retryPending()
    }
    func retryPending() async -> Bool {
        guard let command = pending, !isLoading, !isSubmitting else { return false }
        isSubmitting = true; error = nil; notice = nil
        defer { isSubmitting = false }
        do {
            let result = try await client.setDeliveryPartnerStatus(riderID: command.intent.id, status: command.intent.target,
                expectedGovernanceVersion: command.intent.row.governance.version, reason: command.reason, idempotencyKey: command.key)
            guard result.riderId == command.intent.id, result.status == command.intent.target,
                  result.governanceVersion == command.intent.row.governance.version + 1,
                  result.availabilityStatus == .offline, result.availabilityVersion >= 0 else { throw FunctionClientError.invalidResponse }
            pending = nil
            notice = "\(command.intent.title) accepted. The rider is offline; historical work and earnings are unchanged."
            await fetch()
            return true
        } catch {
            if case let FunctionClientError.api(statusCode: code, code: _, message: _) = error,
               [400, 401, 403, 404, 409, 422].contains(code) {
                pending = nil
                await fetch()
                self.error = "The server rejected the action. Review the refreshed record; permission, version or active-work/custody safeguards may block it."
            } else {
                self.error = "The result is unverified. Retry the same reviewed action with its original request. Other changes remain disabled."
            }
            return false
        }
    }
    private func newKey() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
}
