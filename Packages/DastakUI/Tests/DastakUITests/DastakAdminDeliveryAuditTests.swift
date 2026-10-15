import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakAdminDeliveryAuditTests: XCTestCase {
    func testSuspensionBlocksEveryActiveWorkDomainAndRequiresReasonAndExactName() throws {
        for domain in ["DASTAK_V1", "RETURN", "LEGACY_COURIER", "PARCEL"] {
            XCTAssertNotNil(DastakAdminDeliveryIntent(row: try riderRow(work: domain)).blocker)
        }
        let intent = DastakAdminDeliveryIntent(row: try riderRow())
        XCTAssertNil(intent.blocker)
        XCTAssertEqual(intent.target, .suspended)
        XCTAssertFalse(intent.canConfirm(reason: "Safety review", confirmation: "Other"))
        XCTAssertFalse(intent.canConfirm(reason: "  ", confirmation: "Rider"))
        XCTAssertFalse(intent.canConfirm(reason: String(repeating: "a", count: 501), confirmation: "Rider"))
        XCTAssertTrue(intent.canConfirm(reason: " Safety review ", confirmation: "Rider"))
        XCTAssertNotNil(DastakAdminDeliveryIntent(row: try riderRow(version: 0)).blocker)
        XCTAssertNotNil(DastakAdminDeliveryIntent(row: try riderRow(approval: "pending")).blocker)
    }
    func testReactivationRestoresEligibilityWithoutGoingOnlineOrErasingHistory() throws {
        let intent = DastakAdminDeliveryIntent(row: try riderRow(status: "SUSPENDED"))
        XCTAssertEqual(intent.target, .active)
        XCTAssertTrue(intent.canConfirm(reason: "Compliance cleared", confirmation: ""))
        XCTAssertTrue(intent.consequence.contains("stays offline"))
        XCTAssertTrue(intent.consequence.contains("earnings remain unchanged"))
    }
    func testSuccessfulSuspensionAndReactivationBindVersionThenReload() async throws {
        for status in ["ACTIVE", "SUSPENDED"] {
            let row = try riderRow(status: status)
            let client = DeliveryGovernanceFake(row: row)
            let model = DastakAdminDeliveryGovernanceModel(client: client)
            await model.refresh()
            let intent = DastakAdminDeliveryIntent(row: row)
            let result = await model.submit(intent, reason: "  Reviewed safety  ", confirmation: "Rider")
            XCTAssertTrue(result); XCTAssertNil(model.pending); XCTAssertTrue(model.canReview)
            let calls = await client.recorded()
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].version, 4); XCTAssertEqual(calls[0].reason, "Reviewed safety")
            XCTAssertEqual(calls[0].status, intent.target)
            let loads = await client.loadCount()
            XCTAssertEqual(loads, 2)
        }
    }
    func testNetworkUncertaintyLocksOtherActionsAndRetriesOriginalCommand() async throws {
        let client = DeliveryGovernanceFake(row: try riderRow())
        await client.configure(mutationFailure: .network)
        let model = DastakAdminDeliveryGovernanceModel(client: client)
        await model.refresh()
        let intent = DastakAdminDeliveryIntent(row: try XCTUnwrap(model.rows.first))
        let accepted = await model.submit(intent, reason: "Safety review", confirmation: "Rider")
        XCTAssertFalse(accepted); XCTAssertNotNil(model.pending); XCTAssertFalse(model.canReview)
        let duplicate = await model.submit(intent, reason: "Different request", confirmation: "Rider")
        XCTAssertFalse(duplicate)
        await client.configure(mutationFailure: nil)
        let retry = await model.retryPending()
        XCTAssertTrue(retry)
        let calls = await client.recorded()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].key, calls[1].key)
        XCTAssertEqual(calls[0].reason, calls[1].reason)
        XCTAssertEqual(calls[0].version, calls[1].version)
        XCTAssertEqual(calls[0].status, calls[1].status)
    }
    func testKnownPermissionVersionAndCustodyRejectionsRequireFreshReview() async throws {
        for code in [403, 409, 422] {
            let client = DeliveryGovernanceFake(row: try riderRow())
            await client.configure(mutationFailure: .rejected(code))
            let model = DastakAdminDeliveryGovernanceModel(client: client)
            await model.refresh()
            let result = await model.submit(.init(row: try XCTUnwrap(model.rows.first)), reason: "Reviewed", confirmation: "Rider")
            XCTAssertFalse(result); XCTAssertNil(model.pending); XCTAssertNotNil(model.error)
            let loads = await client.loadCount()
            XCTAssertEqual(loads, 2)
        }
    }
    func testMismatchedAcknowledgementsRemainUnverifiedAndCannotEnableNewActions() async throws {
        for mismatch in ["identity", "version", "online", "status"] {
            let client = DeliveryGovernanceFake(row: try riderRow())
            await client.configure(mismatch: mismatch)
            let model = DastakAdminDeliveryGovernanceModel(client: client)
            await model.refresh()
            let result = await model.submit(.init(row: try XCTUnwrap(model.rows.first)), reason: "Reviewed", confirmation: "Rider")
            XCTAssertFalse(result); XCTAssertNotNil(model.pending); XCTAssertFalse(model.canReview)
        }
    }
    func testAcknowledgedMutationWithFailedReloadDisablesStaleControls() async throws {
        let client = DeliveryGovernanceFake(row: try riderRow())
        await client.configure(failAfterMutation: true)
        let model = DastakAdminDeliveryGovernanceModel(client: client)
        await model.refresh()
        let result = await model.submit(.init(row: try XCTUnwrap(model.rows.first)), reason: "Reviewed", confirmation: "Rider")
        XCTAssertTrue(result); XCTAssertNil(model.pending); XCTAssertNotNil(model.notice)
        XCTAssertTrue(model.needsRefresh); XCTAssertFalse(model.canReview); XCTAssertNotNil(model.error)
    }
    func testStaleReviewAndUnauthorizedRefreshDoNotPermitMutation() async throws {
        let original = try riderRow()
        let client = DeliveryGovernanceFake(row: original)
        let model = DastakAdminDeliveryGovernanceModel(client: client)
        await model.refresh()
        await client.replace(row: try riderRow(name: "Updated rider"))
        await model.refresh()
        let result = await model.submit(.init(row: original), reason: "Reviewed", confirmation: "Rider")
        XCTAssertFalse(result)
        let calls = await client.recorded()
        XCTAssertTrue(calls.isEmpty)
        await client.configure(loadFailure: .rejected(403))
        await model.refresh()
        XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.canReview)
    }
    func testRiderPaginationUsesAppliedFiltersNotUnappliedDraftAndMergesIDs() async throws {
        let client = DeliveryGovernanceFake(row: try riderRow(), paginated: true)
        let model = DastakAdminDeliveryGovernanceModel(client: client)
        await model.load(query: " Rider ", status: .active)
        model.queryDraft = "Different search"; model.statusDraft = .suspended
        await model.loadMore()
        XCTAssertEqual(model.rows.count, 1)
        let requests = await client.pages()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].query, "Rider"); XCTAssertEqual(requests[1].status, .active)
        XCTAssertNotNil(requests[1].cursor)
    }
    func testAuditDraftRejectsBadIDsRangeAndLengthsAndNormalizesValidFilters() {
        var draft = DastakAdminAuditDraft()
        draft.actor = "  Admin  "; draft.resourceID = riderID.uuidString; draft.eventID = " v1:12 "
        XCTAssertEqual(draft.filters()?.actorQuery, "Admin")
        XCTAssertEqual(draft.filters()?.eventId, "v1:12")
        XCTAssertEqual(draft.filters()?.resourceId, riderID)
        draft.resourceID = "not-uuid"; XCTAssertNil(draft.filters())
        draft.resourceID = ""; draft.eventID = "v1:abc"; XCTAssertNil(draft.filters())
        draft.eventID = ""; draft.from = Date(timeIntervalSince1970: 200); draft.to = Date(timeIntervalSince1970: 100)
        XCTAssertNil(draft.filters())
        draft.from = nil; draft.to = nil; draft.actor = String(repeating: "a", count: 101)
        XCTAssertNil(draft.filters())
    }
    func testAuditPaginationDeduplicatesSourcesAndUsesAppliedFilters() async throws {
        let client = AuditHistoryFake()
        let model = DastakAdminAuditHistoryModel(client: client)
        model.draft.actor = " Admin "
        await model.applyDraft()
        model.draft.actor = "Unapplied"
        await model.loadMore()
        XCTAssertEqual(model.events.map(\.id), ["v1:12", "legacy:" + riderID.uuidString])
        let requests = await client.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].filters.actorQuery, "Admin")
        XCTAssertEqual(requests[1].cursor?.eventId, "v1:12")
    }
    func testAuditInvalidFiltersNeverSendRequestAndUnauthorizedRefreshClearsData() async {
        let client = AuditHistoryFake()
        let model = DastakAdminAuditHistoryModel(client: client)
        model.draft.orderID = "bad"
        await model.applyDraft()
        let initial = await client.recorded()
        XCTAssertTrue(initial.isEmpty); XCTAssertNotNil(model.error)
        await model.clearFilters()
        XCTAssertEqual(model.events.count, 1)
        await client.reject(403)
        await model.refresh()
        XCTAssertTrue(model.events.isEmpty); XCTAssertTrue(model.needsRefresh)
        await model.loadMore()
        let requests = await client.recorded()
        XCTAssertEqual(requests.count, 2)
    }
    func testLateAuditRefreshCannotOverwriteNewFilterResults() async throws {
        let client = AuditHistoryFake(holdFirst: true)
        let model = DastakAdminAuditHistoryModel(client: client)
        let first = Task { await model.refresh() }
        while !(await client.isHolding()) { await Task.yield() }
        model.draft.action = "NEW_ACTION"
        await model.applyDraft()
        try await client.releaseFirst()
        await first.value
        XCTAssertEqual(model.events.first?.action, "NEW_ACTION")
        XCTAssertFalse(model.isLoading); XCTAssertFalse(model.needsRefresh)
    }
}

private let riderID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let stamp = "2026-10-10T00:00:00Z"
private func decode<T: Decodable>(_ type: T.Type, _ body: [String: Any]) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: body))
}
private func riderRow(status: String = "ACTIVE", work: String? = nil, version: Int = 4,
    approval: String = "approved", name: String = "Rider") throws -> DastakAdminDeliveryPartner {
    try decode(DastakAdminDeliveryPartner.self, [
        "rider": ["accountId": riderID.uuidString, "displayName": name, "maskedPhoneNumber": "•••• 8881", "accountState": "ACTIVE"],
        "approval": ["applicationId": riderID.uuidString, "status": approval, "submittedAt": stamp,
            "verificationVersion": 2, "hasIdentityEvidence": true, "hasVehicleEvidence": false],
        "transportMethod": "bicycle", "governance": ["status": status, "version": version],
        "availability": ["status": status == "ACTIVE" ? "ONLINE" : "OFFLINE", "version": 8],
        "activeWork": work.map { ["domain": $0, "id": riderID.uuidString] } ?? NSNull() as Any, "updatedAt": stamp])
}
private enum Failure: Sendable {
    case network, rejected(Int)
    var error: any Error {
        switch self {
        case .network: return URLError(.networkConnectionLost)
        case let .rejected(code): return FunctionClientError.api(statusCode: code, code: "GUARD", message: "Rejected")
        }
    }
}
private actor DeliveryGovernanceFake: DastakAdminDeliveryGovernanceClient {
    struct Call: Sendable { let status: DastakAdminRiderStatus; let version: Int; let reason: String; let key: IdempotencyKey }
    struct PageCall: Sendable { let query: String?; let status: DastakAdminRiderStatus?; let cursor: DastakAdminDeliveryCursor? }
    private var row: DastakAdminDeliveryPartner
    private let paginated: Bool
    private var calls: [Call] = []
    private var pageCalls: [PageCall] = []
    private var mutationFailure: Failure?
    private var loadFailure: Failure?
    private var mismatch: String?
    private var failAfterMutation = false
    init(row: DastakAdminDeliveryPartner, paginated: Bool = false) { self.row = row; self.paginated = paginated }
    func configure(mutationFailure: Failure? = nil, loadFailure: Failure? = nil, mismatch: String? = nil, failAfterMutation: Bool = false) {
        self.mutationFailure = mutationFailure; self.loadFailure = loadFailure; self.mismatch = mismatch; self.failAfterMutation = failAfterMutation
    }
    func replace(row: DastakAdminDeliveryPartner) { self.row = row }
    func recorded() -> [Call] { calls }
    func pages() -> [PageCall] { pageCalls }
    func loadCount() -> Int { pageCalls.count }
    func deliveryGovernancePage(query: String?, status: DastakAdminRiderStatus?, limit: Int,
        cursor: DastakAdminDeliveryCursor?, idempotencyKey: IdempotencyKey) async throws -> DastakAdminDeliveryPage {
        pageCalls.append(.init(query: query, status: status, cursor: cursor))
        if let loadFailure { throw loadFailure.error }
        let hasMore = paginated && cursor == nil
        let body: [String: Any] = [
            "rider": ["accountId": row.id.uuidString, "displayName": row.rider.displayName,
                "maskedPhoneNumber": row.rider.maskedPhoneNumber ?? NSNull() as Any, "accountState": row.rider.accountState],
            "approval": ["applicationId": row.approval.applicationId.uuidString, "status": row.approval.status, "submittedAt": stamp,
                "verificationVersion": row.approval.verificationVersion, "hasIdentityEvidence": row.approval.hasIdentityEvidence,
                "hasVehicleEvidence": row.approval.hasVehicleEvidence],
            "transportMethod": row.transportMethod, "governance": ["status": row.governance.status.rawValue, "version": row.governance.version],
            "availability": ["status": row.availability.status.rawValue, "version": row.availability.version],
            "activeWork": row.activeWork.map { ["domain": $0.domain.rawValue, "id": $0.id.uuidString] } ?? NSNull() as Any,
            "updatedAt": row.updatedAt]
        return try decode(DastakAdminDeliveryPage.self, ["deliveryPartners": [body], "hasMore": hasMore,
            "nextCursor": hasMore ? ["updatedAt": stamp, "riderId": riderID.uuidString] : NSNull() as Any])
    }
    func setDeliveryPartnerStatus(riderID: UUID, status: DastakAdminRiderStatus, expectedGovernanceVersion: Int,
        reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminDeliveryStatusResult {
        calls.append(.init(status: status, version: expectedGovernanceVersion, reason: reason, key: idempotencyKey))
        if let mutationFailure { throw mutationFailure.error }
        if failAfterMutation { loadFailure = .network }
        return try decode(DastakAdminDeliveryStatusResult.self, [
            "riderId": mismatch == "identity" ? UUID().uuidString : riderID.uuidString,
            "status": mismatch == "status" ? "ACTIVE" : status.rawValue,
            "governanceVersion": mismatch == "version" ? 4 : 5,
            "availabilityStatus": mismatch == "online" ? "ONLINE" : "OFFLINE", "availabilityVersion": 9, "updatedAt": stamp])
    }
}

private actor AuditHistoryFake: DastakAdminAuditHistoryClient {
    struct Call: Sendable { let filters: DastakAdminAuditFilters; let cursor: DastakAdminAuditCursor? }
    private var calls: [Call] = []
    private var rejection: Int?
    private let holdFirst: Bool
    private var held: CheckedContinuation<DastakAdminAuditPage, any Error>?
    init(holdFirst: Bool = false) { self.holdFirst = holdFirst }
    func recorded() -> [Call] { calls }
    func reject(_ code: Int) { rejection = code }
    func isHolding() -> Bool { held != nil }
    func releaseFirst() throws { held?.resume(returning: try auditPage(action: "OLD_ACTION")); held = nil }
    func auditHistory(filters: DastakAdminAuditFilters, limit: Int, cursor: DastakAdminAuditCursor?,
        idempotencyKey: IdempotencyKey) async throws -> DastakAdminAuditPage {
        calls.append(.init(filters: filters, cursor: cursor))
        if let rejection { throw Failure.rejected(rejection).error }
        if holdFirst && calls.count == 1 { return try await withCheckedThrowingContinuation { held = $0 } }
        return try auditPage(action: filters.action ?? "ACTION", append: cursor != nil)
    }
}
private func auditPage(action: String, append: Bool = false) throws -> DastakAdminAuditPage {
    func event(_ id: String, source: String) -> [String: Any] {
        ["source": source, "eventId": id, "occurredAt": stamp, "actor": ["displayName": "System"],
            "action": action, "resource": ["type": "delivery_partner", "id": riderID.uuidString],
            "summary": ["outcome": "Reviewed"], "references": ["accountId": riderID.uuidString]]
    }
    return try decode(DastakAdminAuditPage.self, ["events": append
        ? [event("v1:12", source: "V1"), event("legacy:" + riderID.uuidString, source: "LEGACY")]
        : [event("v1:12", source: "V1")], "hasMore": !append,
        "nextCursor": append ? NSNull() : ["occurredAt": stamp, "eventId": "v1:12"] as Any])
}
