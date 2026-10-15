import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

@MainActor
final class DastakAdminExecutionModel: ObservableObject {
    @Published private(set) var orders: [DastakV1AdminOrder] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var trace: DastakV1AdminExecutionTrace?
    @Published private(set) var current = false
    @Published private(set) var readAt: Date?
    @Published private(set) var loading = false
    @Published private(set) var busy = false
    @Published private(set) var restored = false
    @Published private(set) var pending: DastakAdminExecutionCommand?
    @Published private(set) var message: String?
    @Published private(set) var scope = "ACTIVE"
    @Published private(set) var query = ""
    @Published private(set) var cursor: DastakAdminExecutionCursor?
    @Published private(set) var listCurrent = false
    private let services: MarketplaceAuthenticatedServices
    private let storage: any DastakAdminExecutionStorage
    private var accountID: UUID?
    private var listGeneration = UUID()
    private var traceGeneration = UUID()
    private var mutationGeneration = UUID()
    private var seenCursors: Set<String> = []
    var blocksActions: Bool { !restored || busy || pending != nil }
    init(services: MarketplaceAuthenticatedServices, storage: any DastakAdminExecutionStorage = DastakAdminExecutionFileStore.shared) { self.services = services; self.storage = storage }
    func restore() async {
        guard !restored, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let id = try await services.accountID()
            let saved = try await storage.load(id)
            guard try await services.accountID() == id else { throw DastakAdminExecutionError.changed }
            accountID = id; pending = saved; restored = true
            if saved != nil { message = "A saved Admin action needs recovery. Retry its unchanged request before starting another action." }
        } catch { message = "Admin recovery storage could not be read. Actions remain locked; no record was removed." }
    }
    func refreshPage(scope: String? = nil, query: String? = nil, append: Bool = false) async {
        await restore()
        guard restored, let accountID, !busy else { return }
        let newScope = scope ?? self.scope
        let newQuery = (query ?? self.query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["ACTIVE", "HISTORY"].contains(newScope), newQuery.count <= 80, !append || (listCurrent && cursor != nil && !loading) else { return }
        let oldCursor = append ? cursor : nil
        self.scope = newScope; self.query = newQuery
        let generation = UUID(); listGeneration = generation
        let epoch = mutationGeneration
        loading = true; listCurrent = false
        if !append { orders = []; cursor = nil; seenCursors = [] }
        defer { if listGeneration == generation { loading = false } }
        do {
            guard try await services.accountID() == accountID else { throw DastakAdminExecutionError.changed }
            let page: DastakAdminExecutionPage = try await services.functions.invoke("dastak-v1-orders", request: ListRequest(operation: "adminExecutionOrders", limit: 50, scope: newScope, query: newQuery.isEmpty ? nil : newQuery, cursor: oldCursor), idempotencyKey: key())
            guard listGeneration == generation, mutationGeneration == epoch, try await services.accountID() == accountID else { return }
            guard page.scope == newScope, page.orders.count <= 50, Set(page.orders.map(\.id)).count == page.orders.count,
                  page.orders.allSatisfy({ $0.version > 0 && Self.timestamp($0.updatedAt) }),
                  !page.hasMore || (page.nextCursor != nil && page.nextCursor != oldCursor && Self.timestamp(page.nextCursor!.updatedAt) && page.orders.last?.id == page.nextCursor?.orderId && page.orders.last?.updatedAt == page.nextCursor?.updatedAt && !seenCursors.contains(Self.cursorKey(page.nextCursor!))),
                  page.hasMore || page.nextCursor == nil else { throw DastakAdminExecutionError.invalid }
            if append {
                for order in page.orders {
                    if let index = orders.firstIndex(where: { $0.id == order.id }) { if order.version >= orders[index].version { orders[index] = order } }
                    else { orders.append(order) }
                }
            } else { orders = page.orders }
            cursor = page.hasMore ? page.nextCursor : nil; listCurrent = true
            if let cursor { seenCursors.insert(Self.cursorKey(cursor)) }
            if let selectedID, orders.contains(where: { $0.id == selectedID }) { await select(selectedID) }
            else if let first = orders.first { await select(first.id) }
            else { selectedID = nil; trace = nil; current = false; readAt = nil; traceGeneration = UUID() }
        } catch {
            guard listGeneration == generation, mutationGeneration == epoch else { return }
            message = "Order directory could not be refreshed. Pagination and actions require a fresh read."
        }
    }
    func select(_ id: UUID) async {
        guard let accountID, restored, !busy else { return }
        if selectedID != id { trace = nil; readAt = nil }
        selectedID = id; current = false
        let generation = UUID(); traceGeneration = generation
        let epoch = mutationGeneration
        do {
            guard try await services.accountID() == accountID else { throw DastakAdminExecutionError.changed }
            let value: DastakV1AdminExecutionTrace = try await services.functions.invoke("dastak-v1-orders", request: TraceRequest(operation: "adminExecutionTrace", orderId: id), idempotencyKey: key())
            guard selectedID == id, traceGeneration == generation, mutationGeneration == epoch, try await services.accountID() == accountID else { return }
            guard value.order.id == id, value.order.version > 0, trace.map({ $0.order.id != id || value.order.version >= $0.order.version }) ?? true else { throw DastakAdminExecutionError.invalid }
            trace = value; current = true; readAt = .now
        } catch {
            guard selectedID == id, traceGeneration == generation, mutationGeneration == epoch else { return }
            current = false; message = "This order trace is unavailable or stale. No new recovery action can be submitted."
        }
    }
    func fresh(at date: Date = .now) -> Bool { current && trace?.order.id == selectedID && readAt.map { (0..<60).contains(date.timeIntervalSince($0)) } == true }
    func rows(_ name: String) -> [DastakAdminTraceRecord] { trace?.failureAndFinance?.record.rows(name) ?? [] }
    private func permits(_ name: String) -> Bool { trace?.failureAndFinance?.record.record("permissions")?.flag(name) == true }
    private func row(_ name: String, _ id: UUID?) -> DastakAdminTraceRecord? { rows(name).first { $0.uuid() == id } }

    /// The reviewed trace is immutable and compared again after the confirmation sheet closes.
    func allowed(_ request: DastakAdminExecutionRequest, reviewed: DastakV1AdminExecutionTrace? = nil, now: Date = .now) -> Bool {
        guard !blocksActions, fresh(at: now), request.valid, let trace, reviewed == nil || trace == reviewed else { return false }
        if request.operation == .cancel { return request.orderId == trace.order.id && request.expectedVersion == trace.order.version && trace.cancellation?.canCancel == true && trace.order.paidAt == nil }
        if request.operation == .handoff {
            guard trace.deliveryCurrent, let delivery = trace.delivery, let mission = delivery.record("mission") else { return false }
            return delivery.flag("canAuthorizeExceptionalHandoff") == true && mission.uuid() == request.missionId && mission.integer("version") == request.expectedMissionVersion && mission.text("status") == "ARRIVED" && delivery.rows("deliveryEvidence")?.contains { $0.uuid() == request.deliveryEvidenceId } == true
        }
        guard trace.financeCurrent else { return false }
        switch request.operation {
        case .offer, .fail:
            guard permits("canManageRecovery"), let record = row("recoveryCases", request.recoveryCaseId) else { return false }
            return record.text("type") == "EXACT_SKU" && record.text("status") == "SEARCHING_EXACT_SKU" && record.integer("version") == request.expectedVersion
        case .delivery:
            guard permits("canManageRecovery"), let record = row("recoveryCases", request.recoveryCaseId), let mission = trace.delivery?.record("mission") else { return false }
            return record.text("type") == "DELIVERY" && record.text("status") == "ACTION_REQUIRED" && record.integer("version") == request.expectedVersion && record.uuid("deliveryMissionId") == mission.uuid() && mission.text("status") == "DELIVERY_RECOVERY" && mission.uuid("assignedRiderId") != nil && (request.action != "RETURN_TO_ORIGIN" || trace.order.orderType == "RETAIL_ONLY")
        case .issue:
            guard permits("canApproveReturns"), let record = row("customerIssues", request.issueId), record.integer("version") == request.expectedVersion, ["OPEN", "UNDER_REVIEW"].contains(record.text("status") ?? "") else { return false }
            if ["PHYSICAL_RETURN", "REFUND_WITHOUT_RETURN"].contains(request.decision ?? ""), !permits("canApproveRefunds") { return false }
            return request.decision != "PHYSICAL_RETURN" || (record.flag("physicalReturnAllowed") == true && record.flag("preparedFood") == false && trace.order.orderType == "RETAIL_ONLY")
        case .rider:
            guard permits("canApproveReturns") else { return false }
            return rows("returns").contains { record in
                guard let mission = record.record("mission") else { return false }
                return record.flag("physicalReturnRequired") == true && mission.uuid() == request.returnMissionId && mission.integer("version") == request.expectedVersion && mission.text("status") == "RIDER_SEARCH" && mission.uuid("assignedRiderId") == nil && trace.order.orderType == "RETAIL_ONLY"
            }
        case .refund:
            guard permits("canProcessRefunds"), request.orderId == trace.order.id, let record = row("refunds", request.refundId) else { return false }
            return ["APPROVED", "FAILED"].contains(record.text("status") ?? "") && (record.integer("amountPaise") ?? 0) > 0 && record.text("currency") != nil
        case .settlement:
            guard permits("canManageSettlements"), let record = row("settlements", request.settlementEntryId) else { return false }
            return record.text("status") == "PENDING" && record.integer("version") == request.expectedVersion && record.text("currency")?.isEmpty == false
        default: return false
        }
    }
    func submit(_ request: DastakAdminExecutionRequest, reviewed: DastakV1AdminExecutionTrace) async {
        guard allowed(request, reviewed: reviewed), let accountID else { message = "The reviewed state changed or expired. Refresh and review the action again."; return }
        let command = DastakAdminExecutionCommand(accountID: accountID, orderID: reviewed.order.id, key: key(), request: request,
            relatedMissionID: request.operation == .delivery ? row("recoveryCases", request.recoveryCaseId)?.uuid("deliveryMissionId") : nil,
            currency: request.operation == .settlement ? row("settlements", request.settlementEntryId)?.text("currency") : request.operation == .refund ? row("refunds", request.refundId)?.text("currency") : nil,
            approvedAmountPaise: request.operation == .refund ? row("refunds", request.refundId)?.integer("amountPaise") : nil)
        busy = true; defer { busy = false }
        mutationGeneration = UUID(); current = false
        do {
            guard try await services.accountID() == accountID else { throw DastakAdminExecutionError.changed }
            try await storage.replace(command, accountID: accountID, expectedRevision: nil)
            pending = command
            await sendPending()
        } catch { restored = false; message = "The action could not be secured locally. No write was sent. Reopen recovery before continuing." }
    }
    func retry() async {
        guard !busy, restored, pending != nil else { return }
        busy = true; defer { busy = false }
        mutationGeneration = UUID(); current = false
        await sendPending()
    }
    private func sendPending() async {
        guard var command = pending, let accountID, command.accountID == accountID else { return }
        do {
            guard command.valid, try await services.accountID() == accountID, try await storage.load(accountID) == command else { throw DastakAdminExecutionError.changed }
            if !command.acknowledged {
                let reply: DastakAdminTraceRecord = try await services.functions.invoke(command.request.operation == .refund ? "dastak-payments" : "dastak-v1-orders", request: command.request, idempotencyKey: command.key)
                var acknowledged = Self.acknowledges(command, reply)
                // The existing provider endpoint's already-processed branch returns orderId only.
                // Never substitute the requested refundId: reconcile the exact completed row instead.
                if !acknowledged, command.request.operation == .refund, reply.uuid("refundId") == nil,
                   reply.uuid("orderId") == command.orderID, reply.text("refundState") == "processed" {
                    let confirmed: DastakV1AdminExecutionTrace = try await services.functions.invoke("dastak-v1-orders", request: TraceRequest(operation: "adminExecutionTrace", orderId: command.orderID), idempotencyKey: key())
                    acknowledged = Self.completedRefund(command, trace: confirmed)
                }
                guard try await services.accountID() == accountID, acknowledged else { message = "The response did not confirm the saved action. Its original request is retained; retry recovery without changing details."; return }
                let old = command.revision
                command.acknowledged = true; command.revision = UUID()
                try await storage.replace(command, accountID: accountID, expectedRevision: old)
                pending = command
            }
            try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
            pending = nil
            message = command.request.operation == .refund ? "Refund submission acknowledged. A pending provider response is not a completed refund; refresh the trace for the final status." : "Action acknowledged. Refresh the order trace before taking another action. Settlement calculation does not transfer money."
        } catch {
            if case let FunctionClientError.api(status, _, reason) = error, (400..<500).contains(status), ![408, 429].contains(status) {
                do {
                    try await storage.replace(nil, accountID: accountID, expectedRevision: command.revision)
                    pending = nil; message = reason + " Refresh and review again before starting a new action."
                } catch { message = "The action was rejected, but its saved record could not be cleared. Recovery remains locked." }
            } else { message = "Outcome or local storage is uncertain. Retry the original saved action; do not create a new refund or recovery request." }
        }
    }
    static func acknowledges(_ command: DastakAdminExecutionCommand, _ reply: DastakAdminTraceRecord) -> Bool {
        let r = command.request
        switch r.operation {
        case .offer: return reply.uuid("recoveryCaseId") == r.recoveryCaseId && reply.uuid("branchId") == r.branchId && reply.uuid("recoveryOpportunityId") != nil && reply.uuid("exactSkuId") != nil && (reply.integer("quantity") ?? 0) > 0 && reply.text("status") == "OFFERED" && timestamp(reply.text("expiresAt") ?? "")
        case .fail: return reply.uuid("recoveryCaseId") == r.recoveryCaseId && reply.uuid("orderId") == command.orderID && reply.text("status") == "RECOVERY_FAILED" && reply.text("lineStatus") == "REFUNDED" && reply.uuid("refundId") != nil
        case .delivery:
            guard reply.uuid("recoveryCaseId") == r.recoveryCaseId, reply.text("action") == r.action, reply.uuid("deliveryMissionId") == command.relatedMissionID else { return false }
            if r.action == "RETURN_TO_ORIGIN" { return reply.uuid("returnId") != nil && reply.uuid("returnMissionId") != nil && reply.text("returnStatus") == "IN_RIDER_CUSTODY" && reply.text("missionStatus") == "DELIVERY_RECOVERY" }
            return reply.text("recoveryStatus") == "RESOLVED" && ["ARRIVED", "OUT_FOR_DELIVERY", "ALL_PACKAGES_PICKED_UP", "PICKUP_IN_PROGRESS"].contains(reply.text("missionStatus") ?? "")
        case .issue:
            guard reply.uuid("issueId") == r.issueId, reply.text("decision") == r.decision else { return false }
            switch r.decision {
            case "REJECT": return reply.text("issueStatus") == "REJECTED"
            case "RESOLVE_NO_REFUND": return reply.text("issueStatus") == "RESOLVED"
            case "REFUND_WITHOUT_RETURN": return reply.text("issueStatus") == "RESOLVED" && reply.uuid("refundId") != nil
            case "PHYSICAL_RETURN": return reply.text("issueStatus") == "UNDER_REVIEW" && reply.uuid("returnId") != nil && reply.uuid("returnMissionId") != nil && reply.text("returnStatus") == "RIDER_SEARCH"
            default: return false
            }
        case .rider: return reply.uuid("returnMissionId") == r.returnMissionId && reply.uuid("riderId") == r.riderId && reply.text("missionStatus") == "ASSIGNED" && reply.uuid("returnId") != nil
        case .refund: return reply.uuid("refundId") == r.refundId && ["pending", "processed"].contains(reply.text("refundState") ?? "")
        case .settlement: return reply.uuid("settlementEntryId") == r.settlementEntryId && ["PENDING", "ELIGIBLE"].contains(reply.text("status") ?? "") && reply.text("calculationStatus") == "CALCULATED" && reply.integer("amountPaise") != nil && reply.text("currency") == command.currency && (reply.integer("version") ?? 0) >= (r.expectedVersion ?? 1)
        case .handoff: return reply.uuid("exceptionalHandoffAuthorizationId") != nil && reply.record("completedMission")?.uuid() == r.missionId && reply.record("completedMission")?.uuid("orderId") == command.orderID && reply.record("completedMission")?.text("status") == "DELIVERED" && reply.record("completedMission")?.text("verificationStatus") == "OVERRIDDEN"
        case .cancel: return reply.text("status") == "CANCELLED" && (reply.integer("version") ?? 0) > (r.expectedVersion ?? 0) && timestamp(reply.text("cancelledAt") ?? "")
        }
    }
    static func timestamp(_ text: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if formatter.date(from: text) != nil { return true }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text) != nil
    }
    static func completedRefund(_ command: DastakAdminExecutionCommand, trace: DastakV1AdminExecutionTrace) -> Bool {
        guard trace.order.id == command.orderID, trace.financeCurrent,
              let refund = trace.failureAndFinance?.record.rows("refunds")?.first(where: { $0.uuid() == command.request.refundId }) else { return false }
        return refund.text("status") == "COMPLETED" && timestamp(refund.text("completedAt") ?? "") && refund.integer("amountPaise") == command.approvedAmountPaise && refund.text("currency") == command.currency
    }
    private func key() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
    private static func cursorKey(_ cursor: DastakAdminExecutionCursor) -> String { cursor.updatedAt + cursor.orderId.uuidString }
    func evidenceURL(path: String, reviewed: DastakV1AdminExecutionTrace) async throws -> URL {
        guard fresh(), trace == reviewed, let accountID else { throw DastakAdminExecutionError.changed }
        let records = (reviewed.delivery?.rows("deliveryEvidence") ?? []) + rows("customerIssues").flatMap { $0.rows("evidence") ?? [] }
        guard !path.isEmpty, records.contains(where: { $0.text("objectPath") == path }), try await services.accountID() == accountID else { throw DastakAdminExecutionError.invalid }
        let download = try await SupabaseDastakV1AdminClient(functions: services.functions).evidenceDownloadURL(objectPath: path, idempotencyKey: key())
        guard try await services.accountID() == accountID, trace == reviewed, download.expiresIn > 0,
              let url = URL(string: download.signedURL), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw DastakAdminExecutionError.invalid }
        return url
    }
    private struct ListRequest: Encodable, Sendable { let operation: String; let limit: Int; let scope: String; let query: String?; let cursor: DastakAdminExecutionCursor? }
    private struct TraceRequest: Encodable, Sendable { let operation: String; let orderId: UUID }
}
