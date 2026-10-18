import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantLocationTests: XCTestCase {
    private let account = UUID()
    private func preferences() -> DastakMerchantLocationPreferences {
        let name = "dastak.location.fixture.\(UUID())"
        return .init(defaults: UserDefaults(suiteName: name)!)
    }
    private func model(_ functions: LocationFunctions, preferences: DastakMerchantLocationPreferences? = nil,
        store: any DastakMerchantJournalStorage = DastakMerchantMemoryJournal(), account: UUID? = nil) -> DastakMerchantModel {
        let identity = account ?? self.account
        return .init(services: MarketplaceAuthenticatedServices(functions: functions, accountIDProvider: { identity },
            objectUploader: { _, _, _, _, _ in }), journalStorage: store,
            requestTimeout: .seconds(2), locationPreferences: preferences ?? self.preferences())
    }

    func testSingleLocationIsChosenWithoutAskingForAnotherName() async throws {
        let functions = LocationFunctions(); await functions.disableFood()
        let merchant = model(functions); await merchant.bootstrap()
        XCTAssertEqual(merchant.merchantLocations.count, 1)
        XCTAssertEqual(merchant.selectedLocationID, locationRetail)
        XCTAssertEqual(merchant.selectedLocation?.name, "Essentials")
        XCTAssertEqual(merchant.canonicalCatalogue?.branch.branchID, locationRetail)
        XCTAssertNil(merchant.restaurantMenu)
    }

    func testOrdersAndStoreUseSameSelectedLocationAndService() async throws {
        let merchant = model(LocationFunctions()); await merchant.bootstrap()
        XCTAssertEqual(merchant.merchantLocations.count, 2)
        let selected = await merchant.selectLocation(locationFood); XCTAssertTrue(selected)
        XCTAssertEqual(merchant.selectedLocation?.kind, .restaurant)
        XCTAssertEqual(merchant.restaurantMenu?.restaurant.branchID, locationFood)
        XCTAssertNil(merchant.canonicalCatalogue)
        XCTAssertEqual(merchant.scopedFulfilments.count, 1)
        XCTAssertEqual(merchant.scopedFulfilments.first?.branch.id, locationFood)
        XCTAssertTrue(merchant.scopedOpportunities.isEmpty)
        let back = await merchant.selectLocation(locationRetail); XCTAssertTrue(back)
        XCTAssertNil(merchant.restaurantMenu)
        XCTAssertEqual(merchant.canonicalCatalogue?.branch.branchID, locationRetail)
        XCTAssertEqual(merchant.scopedOpportunities.count, 1)
    }

    func testSelectionPersistsPerAccountAndIsReverifiedOnRelaunch() async {
        let functions = LocationFunctions(), preferences = preferences()
        let first = model(functions, preferences: preferences); await first.bootstrap()
        _ = await first.selectLocation(locationFood)
        let restored = model(functions, preferences: preferences); await restored.bootstrap()
        XCTAssertEqual(restored.selectedLocationID, locationFood)
        let other = model(functions, preferences: preferences, account: UUID()); await other.bootstrap()
        XCTAssertEqual(other.selectedLocationID, locationRetail, "Another account must not inherit the saved Food preference.")
    }

    func testForeignSavedCandidateIsNotAddedOrUsedForStoreWrites() async {
        let functions = LocationFunctions(), preferences = preferences(), foreign = UUID()
        preferences.save(foreign, account: account)
        let merchant = model(functions, preferences: preferences); await merchant.bootstrap()
        XCTAssertFalse(merchant.merchantLocations.contains { $0.id == foreign })
        XCTAssertNotEqual(merchant.selectedLocationID, foreign)
        let accepted = await merchant.selectLocation(foreign); XCTAssertFalse(accepted)
        let probes = await functions.requestedIDs
        XCTAssertTrue(probes.contains(foreign), "A preference must be verified, not trusted as permission.")
    }

    func testAnotherLocationsOldActionCannotBeStartedAfterSwitch() async throws {
        let functions = LocationFunctions(), merchant = model(functions)
        await merchant.bootstrap()
        let request = try XCTUnwrap(merchant.opportunities.first)
        _ = await merchant.selectLocation(locationFood)
        await merchant.respondToOpportunity(request, accept: true, prepMinutes: 15)
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
    }

    func testPendingCommandPinsOriginalLocationAndPreventsSwitching() async throws {
        let functions = LocationFunctions(), store = MerchantJournalTestStore(), preferences = preferences()
        preferences.save(locationFood, account: account)
        let target = try JSONDecoder().decode(DastakV1MerchantOpportunity.self, from: locationOpportunity())
        let command = DastakMerchantOperationCommand(operation: .retailResponse(target, accept: true, minutes: 15), key: IdempotencyKey(rawValue: UUID().uuidString)!)
        try await store.replace(.init(accountID: account, command: .operation(command)), accountID: account, expectedRevision: nil)
        let merchant = model(functions, preferences: preferences, store: store); await merchant.bootstrap()
        XCTAssertEqual(merchant.selectedLocationID, locationRetail)
        let changed = await merchant.selectLocation(locationFood); XCTAssertFalse(changed)
        await merchant.retryMerchantJournal()
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 1); XCTAssertEqual(writes.first?.key, command.key.rawValue)
        XCTAssertEqual(merchant.pendingOperationCommand, command)
    }

    func testOperationalLocationSurvivesStoreServiceOutageWithoutClaimingManagementAccess() async throws {
        let functions = LocationFunctions(); await functions.failStores()
        let merchant = model(functions); await merchant.bootstrap()
        XCTAssertEqual(merchant.merchantLocations.count, 2)
        XCTAssertEqual(merchant.selectedLocation?.kind, .unknown)
        XCTAssertFalse(merchant.scopedOpportunities.isEmpty)
        XCTAssertNil(merchant.canonicalCatalogue); XCTAssertNil(merchant.restaurantMenu)
        XCTAssertTrue(merchant.restaurantChangesDisabled); XCTAssertNotNil(merchant.locationMessage)
    }

    func testWrongBranchReplyCannotAuthorizeSavedLocation() async {
        let functions = LocationFunctions(), preferences = preferences(), foreign = UUID()
        preferences.save(foreign, account: account); await functions.returnWrongBranch()
        let merchant = model(functions, preferences: preferences); await merchant.bootstrap()
        XCTAssertFalse(merchant.merchantLocations.contains { $0.id == foreign })
        XCTAssertNotEqual(merchant.selectedLocationID, foreign)
    }

    func testDirtyRetailSelectionsPreventLocationChangeAndRefreshDiscard() async throws {
        let merchant = model(LocationFunctions()); await merchant.bootstrap()
        let sku = try XCTUnwrap(merchant.canonicalCatalogue?.skus.first)
        merchant.stageCanonicalSelection(sku)
        XCTAssertTrue(merchant.locationSwitchDisabled)
        let changed = await merchant.selectLocation(locationFood); XCTAssertFalse(changed)
        await merchant.refreshLocations()
        XCTAssertTrue(merchant.hasPendingCanonicalSelections)
        XCTAssertEqual(merchant.selectedLocationID, locationRetail)
        merchant.discardCanonicalSelections()
        let allowed = await merchant.selectLocation(locationFood); XCTAssertTrue(allowed)
    }

    func testLateRestaurantReadCannotReplaceNewRetailLocation() async {
        let functions = LocationFunctions(), merchant = model(functions)
        await merchant.bootstrap(); _ = await merchant.selectLocation(locationFood)
        await functions.suspendFood()
        let old = Task { await merchant.refreshRestaurantMenu(reportFailure: false) }
        await functions.waitForFood()
        _ = await merchant.selectLocation(locationRetail)
        await functions.releaseFood(); _ = await old.value
        XCTAssertEqual(merchant.selectedLocationID, locationRetail)
        XCTAssertNil(merchant.restaurantMenu)
        XCTAssertEqual(merchant.canonicalCatalogue?.branch.branchID, locationRetail)
        XCTAssertFalse(merchant.isRefreshingRestaurant)
    }

    func testAccountChangeClearsLocationContextWithoutReplayingSavedWork() async throws {
        let functions = LocationFunctions(), identity = MerchantJournalTestIdentity()
        let merchant = DastakMerchantModel(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }),
            journalStorage: DastakMerchantMemoryJournal(), locationPreferences: preferences())
        await merchant.bootstrap(); await identity.change(); await merchant.refreshLocations()
        XCTAssertTrue(merchant.merchantLocations.isEmpty); XCTAssertNil(merchant.selectedLocationID)
        XCTAssertTrue(merchant.scopedFulfilments.isEmpty); XCTAssertTrue(merchant.sessionNeedsAttention)
    }

    func testOutageDoesNotSilentlyChangeLocationOrLeaveStockWritesEnabled() async throws {
        let functions = LocationFunctions(), merchant = model(functions)
        await merchant.bootstrap()
        let sku = try XCTUnwrap(merchant.canonicalCatalogue?.skus.first)
        await functions.failStores(); await merchant.refreshLocations()
        XCTAssertEqual(merchant.selectedLocationID, locationRetail)
        XCTAssertEqual(merchant.selectedLocation?.kind, .unknown)
        let changed = await merchant.saveStockCount(sku, quantity: 5)
        XCTAssertFalse(changed)
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
    }

    func testAccountSwitchDuringDiscoveryDiscardsAllOldLocationResults() async {
        let functions = LocationFunctions(), identity = MerchantJournalTestIdentity()
        let merchant = DastakMerchantModel(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }),
            journalStorage: DastakMerchantMemoryJournal(), locationPreferences: preferences())
        await merchant.bootstrap(); await functions.suspendFood()
        let probe = Task { await merchant.refreshLocations() }
        await functions.waitForFood(); await identity.change(); await functions.releaseFood(); await probe.value
        XCTAssertTrue(merchant.merchantLocations.isEmpty); XCTAssertNil(merchant.selectedLocationID)
        XCTAssertTrue(merchant.sessionNeedsAttention)
    }

    func testDelayedStockAndMenuButtonsCannotRetargetAnEarlierEditor() async throws {
        let functions = LocationFunctions(), merchant = model(functions)
        await merchant.bootstrap()
        let sku = try XCTUnwrap(merchant.canonicalCatalogue?.skus.first)
        let stockSaved = await merchant.saveStockCount(sku, quantity: 4, branchID: locationFood)
        XCTAssertFalse(stockSaved); XCTAssertNil(merchant.merchantJournal)
        _ = await merchant.selectLocation(locationFood)
        let categorySaved = await merchant.saveRestaurantEntity(entityID: nil, expectedVersion: 0,
            payload: .category(name: "Old editor draft", description: "", sortOrder: 0, status: "ACTIVE"), branchID: locationRetail)
        XCTAssertFalse(categorySaved); XCTAssertNil(merchant.merchantJournal)
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
    }
}

private let locationRetail = UUID(uuidString: "98000000-0000-4000-8000-000000000001")!
private let locationFood = UUID(uuidString: "98000000-0000-4000-8000-000000000002")!

private actor LocationFunctions: FunctionClient {
    struct Write: Sendable { let key: String; let body: Data }
    var writes: [Write] = [], requestedIDs: [UUID] = []
    private var foodEnabled = true, storesFailed = false, wrongBranch = false, suspendNextFood = false
    private var foodContinuation: CheckedContinuation<Data, Never>?, foodStarted: CheckedContinuation<Void, Never>?
    func disableFood() { foodEnabled = false }
    func failStores() { storesFailed = true }
    func returnWrongBranch() { wrongBranch = true }
    func suspendFood() { suspendNextFood = true }
    func waitForFood() async { if foodContinuation == nil { await withCheckedContinuation { foodStarted = $0 } } }
    func releaseFood() { foodContinuation?.resume(returning: locationMenu()); foodContinuation = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let operation = object?["operation"] as? String ?? name
        let id = (object?["branchId"] as? String).flatMap(UUID.init(uuidString:))
        if let id { requestedIDs.append(id) }
        let result: Data
        switch (name, operation) {
        case ("dastak-v1-catalogue", "merchantSnapshot"):
            if storesFailed { throw URLError(.notConnectedToInternet) }
            guard id == nil || id == locationRetail || wrongBranch else { throw Self.missing }
            result = locationCatalogue()
        case (_, "merchantRestaurantMenu"):
            if storesFailed { throw URLError(.notConnectedToInternet) }
            guard foodEnabled, id == nil || id == locationFood || wrongBranch else { throw Self.missing }
            if suspendNextFood {
                suspendNextFood = false
                result = await withCheckedContinuation { foodContinuation = $0; foodStarted?.resume(); foodStarted = nil }
            } else { result = locationMenu() }
        case (_, "merchantOpportunities"): result = Data("{\"opportunities\":[\(String(decoding: locationOpportunity(), as: UTF8.self))]}".utf8)
        case (_, "restaurantRequests"): result = Data("{\"requests\":[]}".utf8)
        case (_, "merchantFulfilments"):
            let fulfilments = ([locationFulfilment(locationRetail)] + (foodEnabled ? [locationFulfilment(locationFood)] : [])).map { String(decoding: $0, as: UTF8.self) }.joined(separator: ",")
            result = Data("{\"fulfilments\":[\(fulfilments)],\"recoveryOpportunities\":[],\"returnReceipts\":[],\"settlements\":[]}".utf8)
        case (_, "catalogueBrowseMap"): result = Data("null".utf8)
        case (_, "acceptMerchantOpportunity"), (_, "declineMerchantOpportunity"), (_, "upsertRestaurantMenuEntity"), (_, "updateMerchantSelections"), (_, "updateBranchOperationalState"):
            writes.append(.init(key: idempotencyKey.rawValue, body: data)); throw URLError(.timedOut)
        default: throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: result)
    }
    private static var missing: FunctionClientError { .api(statusCode: 404, code: "not_found", message: "Fixture location not applicable") }
}

private func locationCatalogue() -> Data {
    Data("""
    {"branch":{"branchId":"\(locationRetail)","branchName":"Essentials","branchStatus":"ACTIVE","branchVersion":2,"organizationId":"98000000-0000-4000-8000-000000000003","organizationName":"Essentials","merchantType":"RETAIL","operationalState":{"isOpen":true,"acceptingOrders":true,"version":2},"capacity":{"limit":20,"held":0,"available":20}},"categoryTypes":[],"categories":[],"subcategories":[],"truncated":false,"skus":[{"skuId":"98000000-0000-4000-8000-000000000004","categoryId":"98000000-0000-4000-8000-000000000005","subcategoryId":"98000000-0000-4000-8000-000000000006","name":"Tea","packSize":"100 g","galleryImageKeys":[],"searchTerms":[],"listPricePaise":1000,"sellingPricePaise":1000,"currencyCode":"INR","catalogueStatus":"ACTIVE","selected":false,"selectionVersion":1,"stockQuantity":20}]}
    """.utf8)
}
private func locationMenu() -> Data {
    Data("""
    {"restaurant":{"organizationId":"98000000-0000-4000-8000-000000000003","branchId":"\(locationFood)","name":"Kitchen","branchName":"Kitchen","isOpen":true,"acceptingOrders":true,"operationalVersion":3,"branchStatus":"ACTIVE","merchantType":"RESTAURANT_CAFE","softActiveOrderThreshold":10,"activeOrderCount":1},"categories":[]}
    """.utf8)
}
private func locationOpportunity() -> Data {
    Data("""
    {"id":"98000000-0000-4000-8000-000000000007","displayOrderNumber":"DSK-001","requestScope":"REQUESTED_SUBSET","status":"OFFERED","version":2,"branch":{"id":"\(locationRetail)","displayName":"Essentials"},"expiresAt":"2026-10-18T12:00:00Z","secondsRemaining":60,"prepTimeOptionsMinutes":[15,20],"lines":[]}
    """.utf8)
}
private func locationFulfilment(_ branch: UUID) -> Data {
    Data("""
    {"id":"\(branch)","orderId":"98000000-0000-4000-8000-000000000008","displayOrderNumber":"DSK-002","orderStatus":"PREPARING","status":"PREPARING","version":3,"branch":{"id":"\(branch)","displayName":"\(branch == locationRetail ? "Essentials" : "Kitchen")"},"promisedPrepMinutes":15,"secondsRemaining":120,"runningLate":false,"evidence":[],"canDeclarePackages":true,"canAddEvidence":true,"canMarkReady":false,"lines":[]}
    """.utf8)
}
