import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakAdminRestaurantListingsTests: XCTestCase {
    func testEligibilityFailsClosedForLegacyPendingAndNonRestaurantRows() throws {
        XCTAssertTrue(try row().supportsVisibilityChange)
        XCTAssertTrue(try row(status: "SUSPENDED").supportsVisibilityChange)
        XCTAssertFalse(try row(visible: nil).supportsVisibilityChange)
        XCTAssertFalse(try row(status: "PENDING_REVIEW").supportsVisibilityChange)
        XCTAssertFalse(try row(type: "RETAIL_STORE").supportsVisibilityChange)
        XCTAssertFalse(try row(version: 0).supportsVisibilityChange)
    }

    func testRemovalRequiresReasonAndExactBranchNameButRestoreDoesNotRequireTyping() throws {
        let remove = DastakAdminListingIntent(row: try row())
        XCTAssertFalse(remove.canConfirm(reason: "Listing correction", confirmation: "Wrong branch"))
        XCTAssertFalse(remove.canConfirm(reason: " ", confirmation: "Central"))
        XCTAssertTrue(remove.canConfirm(reason: "Listing correction", confirmation: "Central"))
        let restore = DastakAdminListingIntent(row: try row(visible: false))
        XCTAssertTrue(restore.canConfirm(reason: "Merchant requested", confirmation: ""))
    }

    func testSuccessfulRemovalReloadsServerStateAndKeepsClosedStoreClosed() async throws {
        let client = ListingClientDouble(initial: try row())
        let model = DastakAdminRestaurantListingsModel(client: client)
        await model.load()
        let succeeded = await model.submit(DastakAdminListingIntent(row: try row()), reason: " Listing correction ", confirmation: "Central")
        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.rows.first?.branch.customerListingVisible, false)
        XCTAssertEqual(model.rows.first?.branch.version, 4)
        XCTAssertEqual(model.rows.first?.branch.operationalState.isOpen, false)
        XCTAssertNil(model.pending)
        XCTAssertTrue(model.canReview)
        let fetchCount = await client.fetchCount()
        XCTAssertEqual(fetchCount, 2)
    }

    func testUncertainResponseRetriesIdenticalCommandAndBlocksNewAction() async throws {
        let client = ListingClientDouble(initial: try row(), failMutationOnce: true)
        let model = DastakAdminRestaurantListingsModel(client: client)
        await model.load()
        let intent = DastakAdminListingIntent(row: try row())
        let first = await model.submit(intent, reason: " Listing correction ", confirmation: "Central")
        XCTAssertFalse(first)
        XCTAssertNotNil(model.pending)
        XCTAssertFalse(model.canReview)
        let second = await model.retryPending()
        XCTAssertTrue(second)
        let calls = await client.calls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0], calls[1])
        XCTAssertEqual(calls[0].reason, "Listing correction")
    }

    func testFailedPostMutationRefreshNeverEnablesStaleControls() async throws {
        let client = ListingClientDouble(initial: try row(), failReload: true)
        let model = DastakAdminRestaurantListingsModel(client: client)
        await model.load()
        let result = await model.submit(DastakAdminListingIntent(row: try row()), reason: "Listing correction", confirmation: "Central")
        XCTAssertTrue(result, "Mutation was acknowledged; refresh failed separately")
        XCTAssertTrue(model.needsRefresh)
        XCTAssertFalse(model.canReview)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.pending)
        await model.load()
        XCTAssertTrue(model.canReview)
        XCTAssertEqual(model.rows.first?.branch.customerListingVisible, false)
    }

    func testStaleReviewCannotSubmitAfterServerRefresh() async throws {
        let client = ListingClientDouble(initial: try row(version: 4))
        let model = DastakAdminRestaurantListingsModel(client: client)
        await model.load()
        let result = await model.submit(DastakAdminListingIntent(row: try row(version: 3)), reason: "Listing correction", confirmation: "Central")
        XCTAssertFalse(result)
        let calls = await client.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testRestoreDoesNotReopenStore() async throws {
        let initial = try row(visible: false)
        let client = ListingClientDouble(initial: initial)
        let model = DastakAdminRestaurantListingsModel(client: client)
        await model.load()
        let result = await model.submit(DastakAdminListingIntent(row: initial), reason: "Merchant requested", confirmation: "")
        XCTAssertTrue(result)
        XCTAssertEqual(model.rows.first?.branch.customerListingVisible, true)
        XCTAssertEqual(model.rows.first?.branch.operationalState.isOpen, false)
        XCTAssertEqual(model.rows.first?.branch.operationalState.acceptingOrders, false)
    }

    func testKnownVersionRejectionRequiresFreshReviewNotBlindReplay() async throws {
        let client = ListingClientDouble(initial: try row(), rejectMutation: true)
        let model = DastakAdminRestaurantListingsModel(client: client)
        await model.load()
        let result = await model.submit(DastakAdminListingIntent(row: try row()), reason: "Listing correction", confirmation: "Central")
        XCTAssertFalse(result)
        XCTAssertNil(model.pending)
        XCTAssertNotNil(model.error)
        let calls = await client.calls()
        XCTAssertEqual(calls.count, 1)
        let retried = await model.retryPending()
        XCTAssertFalse(retried)
    }
}

private let branchID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private func row(visible: Bool? = true, status: String = "ACTIVE", type: String = "RESTAURANT_CAFE", version: Int = 3) throws -> DastakAdminMerchantListing {
    let object: [String: Any] = [
        "organization": ["id": "22222222-2222-4222-8222-222222222222", "displayName": "Cafe", "merchantType": type, "status": "ACTIVE"],
        "branch": ["id": branchID.uuidString, "displayName": "Central", "status": status, "version": version,
                   "customerListingVisible": visible.map { $0 as Any } ?? NSNull(),
                   "operationalState": ["isOpen": false, "acceptingOrders": false]],
        "updatedAt": "2026-10-10T00:00:00Z"
    ]
    return try JSONDecoder().decode(DastakAdminMerchantListing.self, from: JSONSerialization.data(withJSONObject: object))
}

private actor ListingClientDouble: DastakAdminRestaurantListingClient {
    struct Command: Equatable { let id: UUID; let visible: Bool; let version: Int; let reason: String; let key: IdempotencyKey }
    private var current: DastakAdminMerchantListing
    private var recorded: [Command] = []
    private var fetches = 0
    private var failMutationOnce: Bool
    private var failReload: Bool
    private var rejectMutation: Bool
    init(initial: DastakAdminMerchantListing, failMutationOnce: Bool = false, failReload: Bool = false, rejectMutation: Bool = false) {
        current = initial; self.failMutationOnce = failMutationOnce; self.failReload = failReload
        self.rejectMutation = rejectMutation
    }
    func calls() -> [Command] { recorded }
    func fetchCount() -> Int { fetches }
    func merchantListingPage(query: String?, limit: Int, cursor: DastakAdminMerchantListingCursor?, idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantListingPage {
        fetches += 1
        if fetches == 2, failReload { failReload = false; throw URLError(.timedOut) }
        let data = try JSONEncoder().encode(ListingFixture(row: current))
        return try JSONDecoder().decode(DastakAdminMerchantListingPage.self, from: data)
    }
    func setRestaurantCustomerVisibility(branchID: UUID, visible: Bool, expectedVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminRestaurantVisibilityResult {
        recorded.append(Command(id: branchID, visible: visible, version: expectedVersion, reason: reason, key: idempotencyKey))
        if rejectMutation { throw FunctionClientError.api(statusCode: 409, code: "conflict", message: "stale branch version") }
        // Simulate commit followed by a lost response; retry returns the same recorded result.
        current = try row(visible: visible, version: expectedVersion + 1)
        if failMutationOnce { failMutationOnce = false; throw URLError(.timedOut) }
        return try JSONDecoder().decode(DastakAdminRestaurantVisibilityResult.self, from: JSONSerialization.data(withJSONObject: [
            "branchId": branchID.uuidString, "customerListingVisible": visible,
            "version": expectedVersion + 1, "updatedAt": "2026-10-10T00:00:00Z"
        ]))
    }
}

private struct ListingFixture: Encodable {
    let row: DastakAdminMerchantListing
    func encode(to encoder: Encoder) throws {
        // Encode only the projection needed by this screen, exactly matching the backend envelope.
        var page = encoder.container(keyedBy: Keys.self)
        try page.encode(false, forKey: .hasMore)
        try page.encodeNil(forKey: .nextCursor)
        var rows = page.nestedUnkeyedContainer(forKey: .merchants)
        var item = rows.nestedContainer(keyedBy: Keys.self)
        var organization = item.nestedContainer(keyedBy: Keys.self, forKey: .organization)
        try organization.encode(row.organization.id, forKey: .id)
        try organization.encode(row.organization.displayName, forKey: .displayName)
        try organization.encode(row.organization.merchantType, forKey: .merchantType)
        try organization.encode(row.organization.status, forKey: .status)
        var branch = item.nestedContainer(keyedBy: Keys.self, forKey: .branch)
        try branch.encode(row.id, forKey: .id)
        try branch.encode(row.branch.displayName, forKey: .displayName)
        try branch.encode(row.branch.status, forKey: .status)
        try branch.encode(row.branch.version, forKey: .version)
        try branch.encodeIfPresent(row.branch.customerListingVisible, forKey: .customerListingVisible)
        var operation = branch.nestedContainer(keyedBy: Keys.self, forKey: .operationalState)
        try operation.encode(row.branch.operationalState.isOpen, forKey: .isOpen)
        try operation.encode(row.branch.operationalState.acceptingOrders, forKey: .acceptingOrders)
        try item.encode(row.updatedAt, forKey: .updatedAt)
    }
    enum Keys: String, CodingKey { case merchants, hasMore, nextCursor, organization, branch, id, displayName, merchantType, status, version, customerListingVisible, operationalState, isOpen, acceptingOrders, updatedAt }
}
