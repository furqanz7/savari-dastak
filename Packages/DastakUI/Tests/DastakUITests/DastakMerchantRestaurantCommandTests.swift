import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantRestaurantCommandTests: XCTestCase {
    func testMissingOperationalVersionRemainsCustomerCompatibleButCannotAuthorizeControls() async throws {
        let functions = RestaurantCommandFunctions(menu: restaurantMenuData(operationalVersion: nil))
        let model = makeModel(functions)
        let loaded = await model.refreshRestaurantMenu()
        XCTAssertTrue(loaded)
        XCTAssertNil(model.restaurantMenu?.restaurant.operationalVersion)
        XCTAssertFalse(model.canChangeRestaurantOperatingState)
        let saved = await model.setRestaurantOperatingState(isOpen: true, acceptingOrders: true)
        XCTAssertFalse(saved)
        let writes = await functions.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testNegativeOperatingVersionFailsClosed() async {
        let functions = RestaurantCommandFunctions(menu: restaurantMenuData(operationalVersion: -1))
        let model = makeModel(functions)
        let loaded = await model.refreshRestaurantMenu(reportFailure: false)
        XCTAssertFalse(loaded)
        XCTAssertNil(model.restaurantMenu)
        XCTAssertTrue(model.restaurantChangesDisabled)
        XCTAssertNotNil(model.restaurantRefreshFailure)
    }

    func testOperatingControlsUseRestaurantScopeAndVersionWithoutRetailSnapshot() async throws {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        XCTAssertNil(model.canonicalCatalogue)
        XCTAssertTrue(model.canChangeRestaurantOperatingState)
        await functions.enqueue("updateBranchOperationalState", .data(stateMutation(open: false, accepting: false)))
        await functions.setMenu(restaurantMenuData(operationalVersion: 5, open: false, accepting: false))
        let saved = await model.setRestaurantOperatingState(isOpen: false, acceptingOrders: true)
        XCTAssertTrue(saved)
        let writes = await functions.writes
        let body = try object(XCTUnwrap(writes.first).body)
        XCTAssertEqual(body["branchId"] as? String, restaurantBranch.uuidString)
        XCTAssertEqual(body["expectedVersion"] as? Int, 4)
        XCTAssertEqual(body["isOpen"] as? Bool, false)
        XCTAssertEqual(body["acceptingOrders"] as? Bool, false, "Closing must also pause new orders.")
        XCTAssertNil(body["accountId"])
        XCTAssertEqual(model.restaurantMenu?.restaurant.operationalVersion, 5)
        XCTAssertFalse(try XCTUnwrap(model.restaurantMenu).restaurant.isOpen)
        XCTAssertNil(model.pendingRestaurantCommand)
    }

    func testOpenPausedThenResumeUsesNewVersionAndNewKey() async throws {
        let functions = RestaurantCommandFunctions(menu: restaurantMenuData(open: false, accepting: false))
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        await functions.enqueue("updateBranchOperationalState", .data(stateMutation(open: true, accepting: false)))
        await functions.setMenu(restaurantMenuData(operationalVersion: 5, open: true, accepting: false))
        let opened = await model.setRestaurantOperatingState(isOpen: true, acceptingOrders: false)
        XCTAssertTrue(opened)
        await functions.enqueue("updateBranchOperationalState", .data(stateMutation(open: true, accepting: true, version: 6)))
        await functions.setMenu(restaurantMenuData(operationalVersion: 6))
        let resumed = await model.setRestaurantOperatingState(isOpen: true, acceptingOrders: true)
        XCTAssertTrue(resumed)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertNotEqual(writes[0].key, writes[1].key)
        XCTAssertEqual(try object(writes[1].body)["expectedVersion"] as? Int, 5)
    }

    func testTimeoutThenEditedPayloadCannotReplaceOriginalAndRetryReusesKey() async throws {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        let first = await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 2,
            payload: .category(name: "Original breakfast", description: "Original details", sortOrder: 0, status: "ACTIVE"))
        XCTAssertFalse(first)
        XCTAssertNotNil(model.pendingRestaurantCommand)
        XCTAssertTrue(model.restaurantChangesDisabled)
        let edited = await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 2,
            payload: .category(name: "Changed after timeout", description: "", sortOrder: 1, status: "INACTIVE"))
        XCTAssertFalse(edited)
        let blocked = await model.setRestaurantOperatingState(isOpen: false, acceptingOrders: false)
        XCTAssertFalse(blocked)
        let retry = await model.retryRestaurantCommand()
        XCTAssertFalse(retry)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].key, writes[1].key)
        XCTAssertEqual(writes[0].body, writes[1].body)
        XCTAssertEqual((try object(writes[1].body)["payload"] as? [String: Any])?["name"] as? String, "Original breakfast")
    }

    func testUnknownNewCategoryCannotBeSubmittedTwiceAsANewCreation() async {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        let payload = DastakV1RestaurantMenuPayload.category(name: "Lunch", description: "", sortOrder: 1, status: "ACTIVE")
        _ = await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: payload)
        _ = await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: payload)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 1)
        XCTAssertNotNil(model.pendingRestaurantCommand)
    }

    func testDefinitiveRejectionAllowsNewReviewedCommandWithNewKey() async throws {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        await functions.enqueue("upsertRestaurantMenuEntity", .api(409))
        await functions.setMenu(restaurantMenuData(categoryVersion: 3))
        _ = await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 2, payload: categoryPayload)
        XCTAssertNil(model.pendingRestaurantCommand)
        XCTAssertFalse(model.restaurantChangesDisabled)
        XCTAssertNotNil(model.errorMessage)
        _ = await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 3, payload: categoryPayload)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertNotEqual(writes[0].key, writes[1].key)
        XCTAssertEqual(try object(writes[1].body)["expectedVersion"] as? Int, 3)
    }

    func testTimeoutRateLimitServerErrorAndMalformedAckRemainUncertain() async {
        for reply in [RestaurantCommandFunctions.Reply.timeout, .api(408), .api(429), .api(500), .data(Data("{}".utf8))] {
            let functions = RestaurantCommandFunctions()
            let model = makeModel(functions)
            await model.refreshRestaurantMenu()
            await functions.enqueue("updateBranchOperationalState", reply)
            let saved = await model.setRestaurantOperatingState(isOpen: true, acceptingOrders: false)
            XCTAssertFalse(saved)
            XCTAssertNotNil(model.pendingRestaurantCommand)
            XCTAssertTrue(model.restaurantChangesDisabled)
            _ = await model.retryRestaurantCommand()
            let writes = await functions.writes
            XCTAssertEqual(writes.count, 2)
            XCTAssertEqual(writes[0].key, writes[1].key)
            XCTAssertEqual(writes[0].body, writes[1].body)
        }
    }

    func testWrongBranchOperatingAcknowledgementCannotClaimSuccess() async {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        await functions.enqueue("updateBranchOperationalState", .data(stateMutation(open: true, accepting: false, branch: UUID())))
        let saved = await model.setRestaurantOperatingState(isOpen: true, acceptingOrders: false)
        XCTAssertFalse(saved)
        XCTAssertNotNil(model.pendingRestaurantCommand)
        XCTAssertNil(model.notice)
    }

    func testAcknowledgedSaveAndFailedRereadAreNotReportedAsAFailedSave() async {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        await functions.enqueue("updateBranchOperationalState", .data(stateMutation(open: true, accepting: false)))
        await functions.enqueue("merchantRestaurantMenu", .timeout)
        let saved = await model.setRestaurantOperatingState(isOpen: true, acceptingOrders: false)
        XCTAssertTrue(saved)
        XCTAssertNil(model.pendingRestaurantCommand)
        XCTAssertNotNil(model.notice)
        XCTAssertNotNil(model.restaurantRefreshFailure)
        XCTAssertTrue(model.restaurantChangesDisabled)
        await functions.setMenu(restaurantMenuData(operationalVersion: 5, accepting: false))
        await model.refreshRestaurantMenu()
        XCTAssertFalse(model.restaurantChangesDisabled)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 1, "Refreshing after acknowledgement must not repeat the write.")
    }

    func testMenuAcknowledgementChecksEntityAndVersion() async {
        for id in [restaurantCategory, UUID()] {
            let functions = RestaurantCommandFunctions()
            let model = makeModel(functions)
            await model.refreshRestaurantMenu()
            let ack = "{\"entityId\":\"\(id)\",\"entityType\":\"CATEGORY\",\"menu\":\(String(decoding: restaurantMenuData(categoryVersion: 3), as: UTF8.self))}"
            await functions.enqueue("upsertRestaurantMenuEntity", .data(Data(ack.utf8)))
            let saved = await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 2, payload: categoryPayload)
            XCTAssertEqual(saved, id == restaurantCategory)
            XCTAssertEqual(model.pendingRestaurantCommand == nil, id == restaurantCategory)
        }
    }

    func testMediaTimeoutDoesNotInferSuccessFromAnotherWritersVersionAndRetriesOriginalBytes() async throws {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        await functions.setMenu(restaurantMenuData(mediaVersion: 8))
        let bytes = Data([1, 2, 3, 4])
        let saved = await model.uploadRestaurantMedia(entityType: "RESTAURANT_BRANCH_BANNER", entityID: restaurantBranch,
            expectedMediaVersion: 1, data: bytes, contentType: "image/png", fileName: "original.png")
        XCTAssertFalse(saved)
        XCTAssertNotNil(model.pendingRestaurantCommand)
        let changed = await model.uploadRestaurantMedia(entityType: "RESTAURANT_BRANCH_BANNER", entityID: restaurantBranch,
            expectedMediaVersion: 8, data: Data([9]), contentType: "image/jpeg", fileName: "changed.jpg")
        XCTAssertFalse(changed)
        _ = await model.retryRestaurantCommand()
        let uploads = await functions.uploads
        XCTAssertEqual(uploads.count, 2)
        XCTAssertEqual(uploads[0].key, uploads[1].key)
        XCTAssertEqual(uploads[0].fields, uploads[1].fields)
        XCTAssertEqual(uploads[0].file, uploads[1].file)
        XCTAssertEqual(uploads[1].file.data, bytes)
    }

    func testMediaAcknowledgementClearsPendingOnlyForExactTargetAndAdvancedVersion() async {
        for version in [1, 2] {
            let functions = RestaurantCommandFunctions()
            let model = makeModel(functions)
            await model.refreshRestaurantMenu()
            let ack = "{\"entityId\":\"\(restaurantBranch)\",\"mediaVersion\":\(version),\"imageKey\":\"owned/banner.png\"}"
            await functions.enqueue("uploadGovernedMedia", .data(Data(ack.utf8)))
            let saved = await model.uploadRestaurantMedia(entityType: "RESTAURANT_BRANCH_BANNER", entityID: restaurantBranch,
                expectedMediaVersion: 1, data: Data([1]), contentType: "image/png", fileName: "banner.png")
            XCTAssertEqual(saved, version > 1)
        }
    }

    func testStaleEntityAndOutOfScopeMediaAreRejectedBeforeNetwork() async {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        _ = await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 1, payload: categoryPayload)
        _ = await model.saveRestaurantEntity(entityID: UUID(), expectedVersion: 2, payload: categoryPayload)
        _ = await model.uploadRestaurantMedia(entityType: "RESTAURANT_BRANCH_BANNER", entityID: UUID(),
            expectedMediaVersion: 1, data: Data([1]), contentType: "image/png", fileName: "banner.png")
        let writes = await functions.writes
        let uploads = await functions.uploads
        XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(uploads.isEmpty)
    }

    func testFailedRefreshPreservesLastGoodMenuButBlocksWrites() async {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        await functions.enqueue("merchantRestaurantMenu", .timeout)
        await model.refreshRestaurantMenu(reportFailure: false)
        XCTAssertNotNil(model.restaurantMenu)
        XCTAssertNotNil(model.restaurantRefreshFailure)
        XCTAssertFalse(model.canChangeRestaurantOperatingState)
        _ = await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 2, payload: categoryPayload)
        let writes = await functions.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testInFlightCommandRejectsConcurrentRetryAndNewChanges() async {
        let functions = RestaurantCommandFunctions()
        let model = makeModel(functions)
        await model.refreshRestaurantMenu()
        await functions.holdNextWrite()
        let task = Task { await model.setRestaurantOperatingState(isOpen: true, acceptingOrders: false) }
        await functions.waitUntilHeld()
        XCTAssertTrue(model.isBusy)
        let duplicate = await model.retryRestaurantCommand()
        let changed = await model.setRestaurantOperatingState(isOpen: false, acceptingOrders: false)
        let refreshed = await model.refreshRestaurantMenu()
        XCTAssertFalse(duplicate)
        XCTAssertFalse(changed)
        XCTAssertFalse(refreshed)
        await functions.release(.data(stateMutation(open: true, accepting: false)))
        let saved = await task.value
        XCTAssertTrue(saved)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 1)
        XCTAssertFalse(model.isBusy)
    }

    func testRestaurantMenuRelaunchKeepsOriginalCreationPayloadAndKey() async throws {
        let functions = RestaurantCommandFunctions(); let store = MerchantJournalTestStore(); let accountID = UUID()
        let model = makeModel(functions, storage: store, accountID: accountID); await model.refreshRestaurantMenu()
        await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 2, payload: categoryPayload)
        let onDisk = try await store.load(accountID); XCTAssertEqual(onDisk?.attempts, 1)
        let restored = makeModel(functions, storage: store, accountID: accountID); await restored.refreshRestaurantMenu()
        let replacement = await restored.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: .category(name: "Changed", description: "", sortOrder: 0, status: "ACTIVE"))
        XCTAssertFalse(replacement)
        let menu = String(data: restaurantMenuData(categoryVersion: 3), encoding: .utf8)!
        await functions.enqueue("upsertRestaurantMenuEntity", .data(Data("{\"entityId\":\"\(restaurantCategory)\",\"entityType\":\"CATEGORY\",\"menu\":\(menu)}".utf8)))
        let saved = await restored.retryRestaurantCommand(); XCTAssertTrue(saved)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes[0].body, writes[1].body); XCTAssertEqual(writes[0].key, writes[1].key)
    }
    func testRestaurantMediaBytesPersistAndRelaunchRetriesSameMultipartFields() async throws {
        let functions = RestaurantCommandFunctions(); let store = MerchantJournalTestStore(); let accountID = UUID()
        let model = makeModel(functions, storage: store, accountID: accountID); await model.refreshRestaurantMenu()
        let bytes = Data([1, 2, 3])
        await model.uploadRestaurantMedia(entityType: "RESTAURANT_BRANCH_BANNER", entityID: restaurantBranch, expectedMediaVersion: 1, data: bytes, contentType: "image/jpeg", fileName: "banner.jpg")
        let stored = try XCTUnwrap(model.merchantJournal)
        let roundTrip = try JSONDecoder().decode(DastakMerchantJournalRecord.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(stored, roundTrip)
        let restored = makeModel(functions, storage: store, accountID: accountID); await restored.restoreMerchantCommands()
        await functions.enqueue("uploadGovernedMedia", .data(Data("{\"entityId\":\"\(restaurantBranch)\",\"mediaVersion\":2,\"imageKey\":\"merchant/banner.jpg\"}".utf8)))
        let saved = await restored.retryRestaurantCommand(); XCTAssertTrue(saved)
        let uploads = await functions.uploads
        XCTAssertEqual(uploads.count, 2); XCTAssertEqual(uploads[0].key, uploads[1].key); XCTAssertEqual(uploads[0].fields, uploads[1].fields)
        XCTAssertEqual(uploads[0].file.data, bytes); XCTAssertEqual(uploads[0].file, uploads[1].file)
    }
    func testOperatingAcknowledgedCleanupRelaunchDoesNotToggleAgain() async throws {
        let functions = RestaurantCommandFunctions(); let store = MerchantJournalTestStore(); let accountID = UUID()
        let model = makeModel(functions, storage: store, accountID: accountID); await model.refreshRestaurantMenu()
        await store.failRemoval(); await functions.enqueue("updateBranchOperationalState", .data(stateMutation(open: false, accepting: false)))
        await model.setRestaurantOperatingState(isOpen: false, acceptingOrders: false)
        XCTAssertTrue(model.merchantJournal?.acknowledged == true)
        let restored = makeModel(functions, storage: store, accountID: accountID); await restored.restoreMerchantCommands()
        let saved = await restored.retryRestaurantCommand(); XCTAssertTrue(saved)
        let writes = await functions.writes; XCTAssertEqual(writes.count, 1)
        XCTAssertNil(restored.pendingRestaurantCommand)
    }
    func testRestaurantSaveFailureDoesNotSendMenuWrite() async {
        let functions = RestaurantCommandFunctions(); let store = MerchantJournalTestStore()
        let model = makeModel(functions, storage: store); await model.refreshRestaurantMenu(); await store.failSave()
        let saved = await model.saveRestaurantEntity(entityID: restaurantCategory, expectedVersion: 2, payload: categoryPayload)
        XCTAssertFalse(saved); let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(model.isBusy); XCTAssertFalse(model.merchantJournalRestored)
    }
    func testLaterRestaurantRejectionRetainsEarlierUnknownChange() async {
        let functions = RestaurantCommandFunctions(); let store = MerchantJournalTestStore()
        let model = makeModel(functions, storage: store); await model.refreshRestaurantMenu()
        await model.setRestaurantOperatingState(isOpen: false, acceptingOrders: false)
        await functions.enqueue("updateBranchOperationalState", .api(403)); await model.retryRestaurantCommand()
        XCTAssertNotNil(model.merchantJournal); XCTAssertEqual(model.merchantJournal?.attempts, 2)
    }
    func testMenuPayloadCodecRoundTripsAllFourFlatWireShapes() throws {
        let logistics = try JSONDecoder().decode(DastakV1SKULogistics.self, from: Data(#"{"unitWeightGrams":100,"unitVolumeCm3":100,"lengthCm":10,"widthCm":10,"heightCm":1,"handlingTags":[]}"#.utf8))
        let payloads: [DastakV1RestaurantMenuPayload] = [categoryPayload,
            .item(categoryID: restaurantCategory, name: "Dish", description: "", imageKey: "", basePricePaise: 100, taxRateBps: 0, logisticsAttributes: logistics, status: "ACTIVE"),
            .optionGroup(menuItemID: restaurantCategory, name: "Size", selectionType: "SINGLE", minimumSelections: 1, maximumSelections: 1, sortOrder: 0, status: "ACTIVE"),
            .option(optionGroupID: restaurantCategory, name: "Large", priceDeltaPaise: 20, sortOrder: 0, status: "ACTIVE")]
        for payload in payloads {
            let bytes = try JSONEncoder().encode(payload)
            XCTAssertEqual(try JSONDecoder().decode(DastakV1RestaurantMenuPayload.self, from: bytes), payload)
            XCTAssertNil(try object(bytes)["entityType"], "Persistence must not change the existing flat wire schema")
        }
    }
    func testAccountChangeBeforeRetryCannotSendOldMerchantAction() async throws {
        let functions = RestaurantCommandFunctions(); let store = MerchantJournalTestStore(); let identity = MerchantJournalTestIdentity()
        let model = DastakMerchantModel(services: MarketplaceAuthenticatedServices(functions: functions, accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }), journalStorage: store)
        await model.refreshRestaurantMenu(); await model.setRestaurantOperatingState(isOpen: false, acceptingOrders: false)
        let original = try XCTUnwrap(model.merchantJournal); await identity.change()
        await model.retryRestaurantCommand()
        let writes = await functions.writes; XCTAssertEqual(writes.count, 1)
        XCTAssertFalse(model.merchantJournalRestored)
        let retained = try await store.load(original.accountID); XCTAssertEqual(retained, original)
    }
    private func makeModel(_ functions: RestaurantCommandFunctions, storage: any DastakMerchantJournalStorage = DastakMerchantMemoryJournal(), accountID: UUID = UUID()) -> DastakMerchantModel {
        return DastakMerchantModel(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { accountID }, objectUploader: { _, _, _, _, _ in }), journalStorage: storage)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor RestaurantCommandFunctions: FunctionClient {
    enum Reply: Sendable { case data(Data), timeout, api(Int) }
    struct Call: Sendable { let key: String; let body: Data }
    struct Upload: Sendable { let key: String; let fields: [String: String]; let file: FunctionUpload }
    var writes: [Call] = []
    var uploads: [Upload] = []
    private var menu: Data
    private var replies: [String: [Reply]] = [:]
    private var shouldHold = false
    private var held: CheckedContinuation<Reply, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    init(menu: Data = restaurantMenuData()) { self.menu = menu }
    func setMenu(_ menu: Data) { self.menu = menu }
    func enqueue(_ operation: String, _ reply: Reply) { replies[operation, default: []].append(reply) }
    func holdNextWrite() { shouldHold = true }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release(_ reply: Reply) { held?.resume(returning: reply); held = nil }

    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let operation = object?["operation"] as? String ?? name
        let read = operation == "merchantRestaurantMenu"
        if !read { writes.append(Call(key: idempotencyKey.rawValue, body: data)) }
        let reply: Reply
        if !read, shouldHold {
            shouldHold = false
            reply = await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil }
        } else { reply = next(operation, fallback: read ? .data(menu) : .timeout) }
        return try decode(reply)
    }

    func invokeMultipart<Response: Decodable & Sendable>(_ name: String, fields: [String: String],
        file: FunctionUpload, idempotencyKey: IdempotencyKey) async throws -> Response {
        uploads.append(Upload(key: idempotencyKey.rawValue, fields: fields, file: file))
        return try decode(next("uploadGovernedMedia", fallback: .timeout))
    }

    private func next(_ operation: String, fallback: Reply) -> Reply {
        guard replies[operation]?.isEmpty == false else { return fallback }
        return replies[operation]!.removeFirst()
    }
    private func decode<Response: Decodable>(_ reply: Reply) throws -> Response {
        switch reply {
        case let .data(data): return try JSONDecoder().decode(Response.self, from: data)
        case .timeout: throw URLError(.timedOut)
        case let .api(status): throw FunctionClientError.api(statusCode: status, code: "rejected", message: "Change rejected")
        }
    }
}

private let restaurantBranch = UUID(uuidString: "93000000-0000-4000-8000-000000000001")!
private let restaurantCategory = UUID(uuidString: "93000000-0000-4000-8000-000000000002")!
private let categoryPayload = DastakV1RestaurantMenuPayload.category(name: "Breakfast", description: "", sortOrder: 0, status: "ACTIVE")

private func restaurantMenuData(operationalVersion: Int? = 4, categoryVersion: Int = 2,
    mediaVersion: Int = 1, open: Bool = true, accepting: Bool = true) -> Data {
    let version = operationalVersion.map { ",\"operationalVersion\":\($0)" } ?? ""
    return Data("""
    {"restaurant":{"organizationId":"93000000-0000-4000-8000-000000000003","branchId":"\(restaurantBranch)",
    "name":"Test Kitchen","branchName":"Test branch","mediaVersion":\(mediaVersion),"isOpen":\(open),"acceptingOrders":\(accepting)\(version),
    "branchStatus":"ACTIVE","merchantType":"RESTAURANT","softActiveOrderThreshold":10,"activeOrderCount":2},
    "categories":[{"id":"\(restaurantCategory)","name":"Breakfast","sortOrder":0,"status":"ACTIVE","version":\(categoryVersion),"items":[]}]}
    """.utf8)
}

private func stateMutation(open: Bool, accepting: Bool, version: Int = 5, branch: UUID = restaurantBranch) -> Data {
    Data("{\"branchId\":\"\(branch)\",\"isOpen\":\(open),\"acceptingOrders\":\(accepting),\"version\":\(version),\"updatedAt\":\"2026-10-11T00:00:00Z\"}".utf8)
}
