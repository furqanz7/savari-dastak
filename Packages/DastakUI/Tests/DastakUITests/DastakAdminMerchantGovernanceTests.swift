import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakAdminMerchantGovernanceTests: XCTestCase {
    func testOrganizationSuspensionUsesOrganizationVersionAndBlocksActiveWork() throws {
        let intent = DastakAdminMerchantIntent(row: try merchantRow(), kind: .status(.organization))
        XCTAssertEqual(intent.expectedVersion, 7)
        XCTAssertEqual(intent.targetID, organizationID)
        XCTAssertNil(intent.blocker)
        XCTAssertFalse(intent.canConfirm(reason: "Reviewed safety action", confirmation: "Central"))
        XCTAssertTrue(intent.canConfirm(reason: "Reviewed safety action", confirmation: "Merchant"))
        for (fulfilments, work) in [(1, 0), (0, 1)] {
            let blocked = DastakAdminMerchantIntent(row: try merchantRow(fulfilments: fulfilments, work: work), kind: .status(.organization))
            XCTAssertNotNil(blocked.blocker)
        }
    }

    func testBranchSuspensionDoesNotPretendToCancelExistingWorkAndReactivationDoesNotReopen() throws {
        let intent = DastakAdminMerchantIntent(row: try merchantRow(fulfilments: 1, work: 1), kind: .status(.branch))
        XCTAssertNil(intent.blocker, "Branch eligibility uses a different backend policy from organization suspension")
        XCTAssertEqual(intent.expectedVersion, 3)
        XCTAssertTrue(intent.consequence.contains("does not cancel"))
        let reactivation = DastakAdminMerchantIntent(row: try merchantRow(status: "SUSPENDED"), kind: .status(.branch))
        XCTAssertEqual(reactivation.resultingStatus, .active)
        XCTAssertTrue(reactivation.canConfirm(reason: "Compliance cleared", confirmation: ""))
        XCTAssertTrue(reactivation.consequence.contains("does not reopen"))
    }

    func testMissingWorkProjectionAndPendingOnboardingFailClosed() throws {
        let legacy = try merchantRow(legacy: true)
        XCTAssertNotNil(DastakAdminMerchantIntent(row: legacy, kind: .status(.organization)).blocker)
        XCTAssertNotNil(DastakAdminMerchantIntent(row: legacy, kind: .correction(.init(latitude: 13, longitude: 77))).blocker)
        let pending = try merchantRow(status: "PENDING_REVIEW")
        XCTAssertNotNil(DastakAdminMerchantIntent(row: pending, kind: .status(.branch)).blocker)
    }

    func testDraftOnlySendsReviewedChangesAndNormalizesAddress() throws {
        let row = try merchantRow()
        let zones = try merchantPage().serviceZones ?? []
        var draft = DastakAdminBranchDraft(row: row)
        XCTAssertNil(draft.patch(for: row, zones: zones), "Unchanged records must not send mutations")
        draft.displayName = "  Updated branch  "
        let nameOnly = try XCTUnwrap(draft.patch(for: row, zones: zones))
        XCTAssertEqual(nameOnly.displayName, "Updated branch")
        XCTAssertNil(nameOnly.address)
        XCTAssertNil(nameOnly.latitude)
        XCTAssertFalse(nameOnly.isRouteCritical)
        draft.line1 = "  22 Market Road  "; draft.line2 = " "; draft.countryCode = " in "
        let addressed = try XCTUnwrap(draft.patch(for: row, zones: zones))
        XCTAssertEqual(addressed.address?.line1, "22 Market Road")
        XCTAssertNil(addressed.address?.line2)
        XCTAssertEqual(addressed.address?.countryCode, "IN")
        XCTAssertTrue(addressed.isRouteCritical)
    }

    func testInvalidDraftValuesNeverBecomeReviewable() throws {
        let row = try merchantRow()
        let zones = try merchantPage().serviceZones ?? []
        for bad in ["nan", "inf", "91", ""] {
            var draft = DastakAdminBranchDraft(row: row); draft.latitude = bad
            XCTAssertNil(draft.patch(for: row, zones: zones))
        }
        for bad in ["0", "501", "1.5"] {
            var draft = DastakAdminBranchDraft(row: row); draft.capacityLimit = bad
            XCTAssertNil(draft.patch(for: row, zones: zones))
        }
        var draft = DastakAdminBranchDraft(row: row); draft.serviceZoneID = UUID()
        XCTAssertNil(draft.patch(for: row, zones: zones))
        XCTAssertFalse(DastakAdminBranchPatch(latitude: 12).isValid)
        XCTAssertFalse(DastakAdminBranchPatch(latitude: .nan, longitude: 77).isValid)
    }

    func testActivePickupBlocksDestinationsButNotNameOrCapacityCorrections() throws {
        let row = try merchantRow(work: 1)
        XCTAssertNotNil(DastakAdminMerchantIntent(row: row, kind: .correction(.init(latitude: 13, longitude: 77))).blocker)
        let name = DastakAdminMerchantIntent(row: row, kind: .correction(.init(displayName: "Updated")))
        XCTAssertNil(name.blocker)
        XCTAssertFalse(name.canConfirm(reason: "Correction", confirmation: "Updated"))
        XCTAssertTrue(name.canConfirm(reason: "Correction", confirmation: "Central"))
        XCTAssertNil(DastakAdminMerchantIntent(row: row, kind: .correction(.init(capacityLimit: 30))).blocker)
    }

    func testSuccessfulOrganizationMutationRefreshesServerStateAndPreservesOperations() async throws {
        let client = MerchantDouble()
        let model = DastakAdminMerchantGovernanceModel(client: client)
        await model.load()
        let row = try XCTUnwrap(model.rows.first)
        let success = await model.submit(.init(row: row, kind: .status(.organization)), reason: "Compliance intervention", confirmation: "Merchant")
        XCTAssertTrue(success)
        XCTAssertEqual(model.rows.first?.organization.status, "SUSPENDED")
        XCTAssertEqual(model.rows.first?.organization.version, 8)
        XCTAssertEqual(model.rows.first?.branch.operationalState.isOpen, false)
        XCTAssertEqual(model.rows.first?.branch.customerListingVisible, false)
        XCTAssertEqual(model.rows.first?.branch.operationalPause?.active, true)
        XCTAssertTrue(model.canReview)
    }

    func testCorrectionUncertainResponseRetainsExactPatchReasonVersionAndKey() async throws {
        let client = MerchantDouble(failOnce: true)
        let model = DastakAdminMerchantGovernanceModel(client: client)
        await model.load()
        let row = try XCTUnwrap(model.rows.first)
        let result = await model.submit(.init(row: row, kind: .correction(.init(displayName: "Updated"))), reason: "  Verified correction  ", confirmation: "Central")
        XCTAssertFalse(result)
        XCTAssertFalse(model.canReview)
        let retry = await model.retryPending()
        XCTAssertTrue(retry)
        let calls = await client.calls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.first, calls.last)
        XCTAssertEqual(calls.first?.reason, "Verified correction")
        XCTAssertEqual(model.rows.first?.branch.displayName, "Updated")
        XCTAssertEqual(model.rows.first?.branch.version, 4)
    }

    func testFailedAuthoritativeReloadBlocksFurtherChangesUntilRecovery() async throws {
        let client = MerchantDouble(failReload: true)
        let model = DastakAdminMerchantGovernanceModel(client: client)
        await model.load()
        let row = try XCTUnwrap(model.rows.first)
        let result = await model.submit(.init(row: row, kind: .status(.branch)), reason: "Safety review", confirmation: "Central")
        XCTAssertTrue(result)
        XCTAssertTrue(model.needsRefresh)
        XCTAssertFalse(model.canReview)
        XCTAssertNotNil(model.error)
        await model.load()
        XCTAssertTrue(model.canReview)
        XCTAssertEqual(model.rows.first?.branch.status, "SUSPENDED")
    }

    func testStaleReviewAndBlockedOrganizationNeverSendCommands() async throws {
        let client = MerchantDouble()
        let model = DastakAdminMerchantGovernanceModel(client: client)
        await model.load()
        let stale = try merchantRow(status: "SUSPENDED")
        let result = await model.submit(.init(row: stale, kind: .status(.branch)), reason: "Reviewed", confirmation: "")
        XCTAssertFalse(result)
        let calls = await client.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testKnownServerRejectionRefreshesAndCannotBlindlyReplay() async throws {
        let client = MerchantDouble(reject: true)
        let model = DastakAdminMerchantGovernanceModel(client: client)
        await model.load()
        let row = try XCTUnwrap(model.rows.first)
        let result = await model.submit(.init(row: row, kind: .status(.branch)), reason: "Safety review", confirmation: "Central")
        XCTAssertFalse(result)
        XCTAssertNil(model.pending)
        XCTAssertNotNil(model.error)
        let retry = await model.retryPending()
        XCTAssertFalse(retry)
        let calls = await client.calls()
        XCTAssertEqual(calls.count, 1)
    }

    func testWrongAcknowledgedEntityKeepsCommandUnverified() async throws {
        let client = MerchantDouble(wrongResult: true)
        let model = DastakAdminMerchantGovernanceModel(client: client)
        await model.load()
        let row = try XCTUnwrap(model.rows.first)
        let result = await model.submit(.init(row: row, kind: .status(.branch)), reason: "Safety review", confirmation: "Central")
        XCTAssertFalse(result)
        XCTAssertNotNil(model.pending)
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.canReview)
    }

    func testReactivationPreservesClosedPausedRemovedStoreState() async throws {
        let client = MerchantDouble(suspended: true)
        let model = DastakAdminMerchantGovernanceModel(client: client)
        await model.load()
        let row = try XCTUnwrap(model.rows.first)
        let result = await model.submit(.init(row: row, kind: .status(.branch)), reason: "Compliance cleared", confirmation: "")
        XCTAssertTrue(result)
        XCTAssertEqual(model.rows.first?.branch.status, "ACTIVE")
        XCTAssertEqual(model.rows.first?.branch.operationalState.isOpen, false)
        XCTAssertEqual(model.rows.first?.branch.operationalPause?.active, true)
        XCTAssertEqual(model.rows.first?.branch.customerListingVisible, false)
    }
}

private let organizationID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
private let merchantBranchID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let zoneID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private func merchantObject(status: String = "ACTIVE", fulfilments: Int = 0, work: Int = 0, legacy: Bool = false) -> [String: Any] {
    var organization: [String: Any] = ["id": organizationID.uuidString, "displayName": "Merchant", "merchantType": "RETAIL_STORE", "status": "ACTIVE"]
    var branch: [String: Any] = ["id": merchantBranchID.uuidString, "displayName": "Central", "status": status, "version": 3,
        "customerListingVisible": false, "operationalState": ["isOpen": false, "acceptingOrders": false],
        "operationalPause": ["active": true, "reason": "Existing pause"],
        "normalizedAddress": ["line1": "12 Market Road", "line2": "Unit 2", "city": "Mysuru", "state": "Karnataka", "postalCode": "570001", "countryCode": "IN"],
        "latitude": 12.3, "longitude": 76.6, "serviceZone": ["id": zoneID.uuidString, "name": "Mysuru"], "capacityLimit": 20]
    if !legacy {
        organization["version"] = 7
        organization["activeNonTerminalFulfilmentCount"] = fulfilments
        organization["activePickupReturnWorkCount"] = work
        branch["activeNonTerminalFulfilmentCount"] = fulfilments
        branch["activePickupReturnWorkCount"] = work
    }
    return ["organization": organization, "branch": branch, "updatedAt": "2026-10-10T00:00:00Z"]
}
private func merchantRow(status: String = "ACTIVE", fulfilments: Int = 0, work: Int = 0, legacy: Bool = false) throws -> DastakAdminMerchantListing {
    try JSONDecoder().decode(DastakAdminMerchantListing.self, from: JSONSerialization.data(withJSONObject: merchantObject(status: status, fulfilments: fulfilments, work: work, legacy: legacy)))
}
private func merchantPage(object: [String: Any] = merchantObject()) throws -> DastakAdminMerchantListingPage {
    try JSONDecoder().decode(DastakAdminMerchantListingPage.self, from: JSONSerialization.data(withJSONObject: [
        "merchants": [object], "hasMore": false, "serviceZones": [["id": zoneID.uuidString, "name": "Mysuru"]]
    ]))
}
private actor MerchantDouble: DastakAdminMerchantGovernanceClient {
    struct Command: Equatable, Sendable {
        let target: DastakAdminMerchantTarget; let id: UUID; let status: DastakAdminMerchantStatus?
        let patch: DastakAdminBranchPatch?; let version: Int; let reason: String; let key: IdempotencyKey
    }
    private var object = merchantObject()
    private var recorded: [Command] = []
    private var failOnce: Bool
    private var failReload: Bool
    private let reject: Bool
    private let wrongResult: Bool
    private var loads = 0
    init(failOnce: Bool = false, failReload: Bool = false, reject: Bool = false, wrongResult: Bool = false, suspended: Bool = false) {
        self.failOnce = failOnce; self.failReload = failReload; self.reject = reject
        self.wrongResult = wrongResult
        if suspended { object = merchantObject(status: "SUSPENDED") }
    }
    func calls() -> [Command] { recorded }
    func merchantListingPage(query: String?, limit: Int, cursor: DastakAdminMerchantListingCursor?, idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantListingPage {
        loads += 1
        if loads == 2 && failReload { failReload = false; throw URLError(.timedOut) }
        return try merchantPage(object: object)
    }
    func setRestaurantCustomerVisibility(branchID: UUID, visible: Bool, expectedVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminRestaurantVisibilityResult { throw FunctionClientError.invalidResponse }
    func setMerchantStatus(target: DastakAdminMerchantTarget, id: UUID, status: DastakAdminMerchantStatus, expectedVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantGovernanceResult {
        try apply(Command(target: target, id: id, status: status, patch: nil, version: expectedVersion, reason: reason, key: idempotencyKey))
    }
    func correctMerchantBranch(id: UUID, changes: DastakAdminBranchPatch, expectedVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantGovernanceResult {
        try apply(Command(target: .branch, id: id, status: nil, patch: changes, version: expectedVersion, reason: reason, key: idempotencyKey))
    }
    private func apply(_ command: Command) throws -> DastakAdminMerchantGovernanceResult {
        recorded.append(command)
        if reject { throw FunctionClientError.api(statusCode: 409, code: "stale_version", message: "Changed record") }
        let target = command.target.rawValue
        var entity = object[target] as! [String: Any]
        entity["version"] = command.version + 1
        if let status = command.status { entity["status"] = status.rawValue }
        if let name = command.patch?.displayName { entity["displayName"] = name }
        object[target] = entity
        if failOnce { failOnce = false; throw URLError(.timedOut) }
        var result: [String: Any] = ["organizationId": organizationID.uuidString, "status": entity["status"]!, "version": command.version + 1, "updatedAt": "2026-10-10T00:00:00Z"]
        if command.target == .branch { result["branchId"] = merchantBranchID.uuidString }
        if wrongResult { result["branchId"] = UUID().uuidString }
        if command.patch != nil { result["changedFields"] = ["displayName"] }
        return try JSONDecoder().decode(DastakAdminMerchantGovernanceResult.self, from: JSONSerialization.data(withJSONObject: result))
    }
}
