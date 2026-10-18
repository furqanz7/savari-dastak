import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor final class DastakMerchantDiscoveryTests: XCTestCase {
    private func services(_ functions: DiscoveryFunctions, identity: MerchantJournalTestIdentity? = nil) -> MarketplaceAuthenticatedServices {
        .init(functions: functions,accountIDProvider: { if let identity { return await identity.id }; return discoveryID(90) },objectUploader: { _,_,_,_,_ in })
    }
    private func search(_ functions: DiscoveryFunctions, timeout: Duration = .seconds(1), identity: MerchantJournalTestIdentity? = nil) -> DastakMerchantInventoryModel {
        .init(services: services(functions,identity: identity),client: SupabaseDastakMerchantDiscoveryClient(functions: functions),timeout: timeout)
    }
    private func context(_ query: String = "", selected: Bool = false) -> DastakMerchantInventoryContext {
        .init(branch: discoveryID(1),query: query,selectedOnly: selected,revision: discoveryID(99),checkedAt: nil)
    }
    func testPagedInventoryContinuesBeyondInitialRowsAndKeepsStockVersionsAndRichMedia() async throws {
        let functions = DiscoveryFunctions(), model = search(functions)
        await model.load(context()); XCTAssertEqual(model.rows.map(\.id),[discoveryID(10)])
        XCTAssertNotNil(model.cursor)
        await model.load(context(),more: true)
        XCTAssertEqual(model.rows.map(\.id),[discoveryID(10),discoveryID(11)])
        XCTAssertNil(model.cursor); XCTAssertTrue(model.current)
        XCTAssertEqual(model.rows.last?.stockQuantity,7); XCTAssertEqual(model.rows.last?.selectionVersion,4)
        XCTAssertEqual(model.rows.last?.galleryImageKeys,["gallery.png"])
        let calls = try await functions.calls.map { try JSONSerialization.jsonObject(with: $0) as! [String:Any] }
        XCTAssertEqual(calls.count,2); XCTAssertEqual(calls[0]["operation"] as? String,"merchantInventoryPage")
        XCTAssertNil(calls[0]["accountId"]); XCTAssertNotNil(calls[1]["cursor"])
    }
    func testScopeAndQueryChangeResetCursorAndCannotAppendAnOldPage() async throws {
        let functions = DiscoveryFunctions(), model = search(functions)
        await model.load(context())
        await model.load(context("tea",selected: true))
        let calls = try await functions.calls.map { try JSONSerialization.jsonObject(with: $0) as! [String:Any] }
        XCTAssertNil(calls.last?["cursor"]); XCTAssertEqual(calls.last?["query"] as? String,"tea")
        XCTAssertEqual(calls.last?["selectedOnly"] as? Bool,true)
        await model.load(context(),more: true)
        let count = await functions.count(); XCTAssertEqual(count,2)
    }
    func testWrongBranchAndRepeatedCursorAreRejectedBeforePublishing() async {
        for mode in [DiscoveryFunctions.Mode.wrongBranch,.badCursor,.duplicate] {
            let functions = DiscoveryFunctions(); await functions.mode(mode)
            let model = search(functions); await model.load(context())
            XCTAssertFalse(model.current); XCTAssertTrue(model.rows.isEmpty); XCTAssertNotNil(model.failure)
        }
    }
    func testNewQuerySupersedesSlowReadAndLateResponseCannotReplaceNewRows() async {
        let functions = DiscoveryFunctions(), model = search(functions)
        await functions.hold()
        let first = Task { await model.load(context("old")) }
        await functions.wait()
        await model.load(context("new"))
        await functions.release(); await first.value
        XCTAssertEqual(model.context?.query,"new"); XCTAssertTrue(model.current)
        XCTAssertEqual(model.rows.first?.name,"new")
    }
    func testTimeoutAndDismissReleaseLoadingAndIgnoreLateResults() async {
        let functions = DiscoveryFunctions(), model = search(functions,timeout: .milliseconds(40))
        await functions.hold()
        let first = Task { await model.load(context()) }
        await functions.wait(); await first.value
        XCTAssertFalse(model.loading); XCTAssertFalse(model.current)
        await functions.release()
        await model.load(context()); XCTAssertTrue(model.current)
        await functions.hold()
        let next = Task { await model.load(context("late")) }
        await functions.wait(); model.invalidate(); await functions.release(); await next.value
        XCTAssertFalse(model.current); XCTAssertFalse(model.loading)
    }
    func testAccountChangeDuringReadOrBetweenPagesCannotMixActors() async {
        let functions = DiscoveryFunctions(), identity = MerchantJournalTestIdentity(), model = search(functions,identity: identity)
        await model.load(context()); await identity.change()
        await model.load(context(),more: true)
        XCTAssertFalse(model.current); XCTAssertTrue(model.rows.isEmpty)
        await functions.hold()
        let next = Task { await model.load(context("change")) }
        await functions.wait(); await identity.change(); await functions.release(); await next.value
        XCTAssertFalse(model.current); XCTAssertTrue(model.rows.isEmpty)
    }
    func testFailedNextPageDoesNotClaimAllResultsLoadedOrKeepEditableOldResults() async {
        let functions = DiscoveryFunctions(), model = search(functions)
        await model.load(context()); await functions.mode(.denied)
        await model.load(context(),more: true)
        XCTAssertFalse(model.current); XCTAssertFalse(model.loading); XCTAssertNotNil(model.failure)
        XCTAssertTrue(model.rows.isEmpty)
    }
    func testLongSearchShowsActionableFeedbackWithoutCallingServer() async {
        let functions = DiscoveryFunctions(), model = search(functions)
        await model.load(context(String(repeating: "a",count: 81)))
        XCTAssertFalse(model.loading); XCTAssertFalse(model.current)
        XCTAssertTrue(model.failure?.contains("80 characters") == true)
        let count = await functions.count(); XCTAssertEqual(count,0)
        await model.load(context("tea")); XCTAssertTrue(model.current)
    }
    func testDirectoryFindsQuietLocationsPagesAndFocusedPreferenceOutsideFirstPage() async {
        let functions = DiscoveryFunctions()
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = DastakMerchantLocationPreferences(defaults: defaults)
        prefs.save(discoveryID(3),account: discoveryID(90))
        let model = DastakMerchantModel(services: services(functions),locationPreferences: prefs)
        await model.refreshLocations()
        XCTAssertEqual(model.merchantLocations.count,2,"Focused location is included even before its page is loaded.")
        XCTAssertEqual(model.selectedLocationID,discoveryID(3)); XCTAssertFalse(model.locationDirectoryComplete)
        await model.refreshLocations(loadMore: true)
        XCTAssertTrue(model.locationDirectoryComplete); XCTAssertNil(model.locationDirectoryCursor)
        XCTAssertEqual(model.selectedLocationID,discoveryID(3))
        XCTAssertEqual(model.selectedLocation?.kind,.restaurant)
        let operations = await functions.operations(); XCTAssertEqual(operations,["merchantLocationsPage","merchantLocationsPage"])
    }
    func testRevokedDirectoryAccessClearsLocationsInsteadOfFallingBackToOldIDs() async {
        let functions = DiscoveryFunctions()
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DastakMerchantModel(services: services(functions),locationPreferences: .init(defaults: defaults))
        await model.refreshLocations(); XCTAssertFalse(model.merchantLocations.isEmpty)
        await functions.mode(.denied); await model.refreshLocations()
        XCTAssertTrue(model.merchantLocations.isEmpty); XCTAssertNil(model.selectedLocationID)
        XCTAssertFalse(model.locationDirectoryComplete)
        let operations = await functions.operations(); XCTAssertTrue(operations.allSatisfy { $0=="merchantLocationsPage" })
    }
    func testRevokedFocusedLocationIsRemovedEvenWhenEarlierPagesWereCached() async {
        let functions = DiscoveryFunctions()
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = DastakMerchantLocationPreferences(defaults: defaults)
        prefs.save(discoveryID(3),account: discoveryID(90))
        let model = DastakMerchantModel(services: services(functions),locationPreferences: prefs)
        await model.refreshLocations(); XCTAssertEqual(model.selectedLocationID,discoveryID(3))
        await functions.mode(.focusRevoked); await model.refreshLocations(loadMore: true)
        XCTAssertFalse(model.merchantLocations.contains { $0.id == discoveryID(3) })
        XCTAssertEqual(model.selectedLocationID,discoveryID(1))
        XCTAssertTrue(model.locationDirectoryComplete)
    }
    func testDirectoryAccountChangeDuringReadOrBetweenPagesClearsOldContext() async {
        for duringRead in [true,false] {
            let functions = DiscoveryFunctions(), identity = MerchantJournalTestIdentity()
            let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let model = DastakMerchantModel(services: services(functions,identity: identity),locationPreferences: .init(defaults: defaults))
            await model.refreshLocations()
            if duringRead {
                await functions.hold()
                let read = Task { await model.refreshLocations() }
                await functions.wait(); await identity.change(); await functions.release(); await read.value
            } else {
                await identity.change(); await model.refreshLocations(loadMore: true)
            }
            XCTAssertTrue(model.merchantLocations.isEmpty); XCTAssertNil(model.selectedLocationID)
            XCTAssertFalse(model.isRefreshingLocations); XCTAssertFalse(model.locationDirectoryComplete)
            XCTAssertTrue(model.sessionNeedsAttention)
        }
    }
    func testDirectoryTimeoutReleasesLoadingAndLateResponseCannotReplaceRetry() async {
        let functions = DiscoveryFunctions()
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DastakMerchantModel(services: services(functions),requestTimeout: .milliseconds(40),locationPreferences: .init(defaults: defaults))
        await model.refreshLocations(); await functions.hold()
        let read = Task { await model.refreshLocations(loadMore: true) }
        await functions.wait(); await read.value
        XCTAssertFalse(model.isRefreshingLocations); XCTAssertFalse(model.locationDirectoryComplete)
        XCTAssertNotNil(model.locationDirectoryMessage)
        await model.refreshLocations(); XCTAssertFalse(model.isRefreshingLocations)
        XCTAssertEqual(model.merchantLocations.map(\.id),[discoveryID(1)])
        await functions.release()
        await Task.yield()
        XCTAssertEqual(model.merchantLocations.map(\.id),[discoveryID(1)])
    }
    func testUnavailableDirectoryUsesOnlyLabelledLimitedLegacyDiscovery() async {
        let functions = DiscoveryFunctions(); await functions.mode(.unavailable)
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DastakMerchantModel(services: services(functions),locationPreferences: .init(defaults: defaults))
        await model.refreshLocations()
        XCTAssertFalse(model.locationDirectoryComplete); XCTAssertNil(model.locationDirectoryCursor)
        XCTAssertTrue(model.locationDirectoryMessage?.contains("limited") == true)
        XCTAssertFalse(model.isRefreshingLocations)
        let operations = await functions.operations()
        XCTAssertEqual(operations.first,"merchantLocationsPage")
        XCTAssertTrue(operations.contains("merchantSnapshot"))
    }
    func testDirectoryHonorsSavedCommandLocationWithoutChangingOrReplayingIt() async throws {
        let functions = DiscoveryFunctions(), storage = DastakMerchantMemoryJournal()
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = DastakMerchantLocationPreferences(defaults: defaults)
        prefs.save(discoveryID(3),account: discoveryID(90))
        let command = DastakMerchantRestaurantCommand(branchID: discoveryID(1),key: IdempotencyKey(rawValue: UUID().uuidString)!,operation: .operating(isOpen: false,acceptingOrders: false,expectedVersion: 1))
        let saved = DastakMerchantJournalRecord(accountID: discoveryID(90),command: .restaurant(command))
        try await storage.replace(saved,accountID: discoveryID(90),expectedRevision: nil)
        let model = DastakMerchantModel(services: services(functions),journalStorage: storage,locationPreferences: prefs)
        await model.restoreMerchantCommands(); await model.refreshLocations()
        XCTAssertEqual(model.selectedLocationID,discoveryID(1)); XCTAssertEqual(model.pendingRestaurantCommand,command)
        let switched = await model.selectLocation(discoveryID(3)); XCTAssertFalse(switched)
        let stored = try await storage.load(discoveryID(90)); XCTAssertEqual(stored,saved)
        let operations = await functions.operations(); XCTAssertEqual(operations,["merchantLocationsPage"])
    }
    func testOrderOnlyDirectoryRowDoesNotGrantStoreManagement() throws {
        let row = try JSONDecoder().decode(DastakMerchantDirectoryLocation.self,from: JSONSerialization.data(withJSONObject: location(discoveryID(4),canManage: false)))
        XCTAssertEqual(DastakMerchantLocation(row).kind,.unknown)
    }
    func testCacheMergeCannotDowngradeNewerStockVersion() throws {
        let rows = try JSONDecoder().decode(DastakMerchantInventoryPage.self,from: inventoryData(query: "",after: false)).skus
        var newer = sku(discoveryID(10),name:"Latest")
        newer["selectionVersion"] = 8; newer["stockQuantity"] = 12
        let latest = try JSONDecoder().decode(DastakV1MerchantCatalogueSnapshot.SKU.self,from: JSONSerialization.data(withJSONObject: newer))
        let base = DastakV1MerchantCatalogueSnapshot(branch: .init(branchID: discoveryID(1),branchName:"Store",branchStatus:"ACTIVE",branchVersion:1,
            organizationID: discoveryID(80),organizationName:"Business",merchantType:"RETAIL",
            operationalState:.init(isOpen:true,acceptingOrders:true,version:1,updatedAt:nil),capacity:.init(limit:10,held:0,available:10)),
            categoryTypes:[],categories:[],subcategories:[],skus:[latest],truncated:true)
        let merged = base.mergingInventory(rows)
        XCTAssertEqual(merged.skus.first?.stockQuantity,12); XCTAssertEqual(merged.skus.first?.selectionVersion,8)
    }
}

private func discoveryID(_ value: Int) -> UUID { UUID(uuidString:String(format:"96000000-0000-4000-8000-%012d",value))! }
private func sku(_ id: UUID,name: String) -> [String:Any] {
    ["skuId":id.uuidString,"categoryId":discoveryID(50).uuidString,"subcategoryId":discoveryID(51).uuidString,
     "name":name,"packSize":"100 g","galleryImageKeys":["gallery.png"],"searchTerms":["chai"],
     "listPricePaise":100,"sellingPricePaise":90,"currencyCode":"INR","catalogueStatus":"ACTIVE",
     "selected":true,"selectionVersion":4,"stockQuantity":7,"stockReservedQuantity":2]
}
private func inventoryData(query: String,after: Bool,mode: DiscoveryFunctions.Mode = .normal) throws -> Data {
    let row = sku(discoveryID(after ? 11 : 10),name:query.isEmpty ? "Tea" : query)
    return try JSONSerialization.data(withJSONObject:["branchId":discoveryID(mode == .wrongBranch ? 2 : 1).uuidString,
        "skus":mode == .duplicate ? [row,row] : [row],"nextCursor":after ? NSNull() :
            ["name":mode == .badCursor ? "Wrong" : row["name"]!,"skuId":discoveryID(10).uuidString]])
}
private func location(_ id: UUID,canManage: Bool = true) -> [String:Any] {
    ["id":id.uuidString,"displayName":"Quiet store","merchantType":id == discoveryID(3) ? "RESTAURANT_CAFE" : "RETAIL","canManageStore":canManage]
}
private actor DiscoveryFunctions: FunctionClient {
    enum Mode { case normal, wrongBranch, badCursor, duplicate, denied, focusRevoked, unavailable }
    var calls: [Data] = []
    private var behavior: Mode = .normal
    private var holding = false
    private var continuation: CheckedContinuation<Void,Never>?, started: CheckedContinuation<Void,Never>?
    func mode(_ value: Mode) { behavior = value }
    func count() -> Int { calls.count }
    func operations() -> [String] { calls.compactMap { (try? JSONSerialization.jsonObject(with:$0) as? [String:Any])?["operation"] as? String } }
    func hold() { holding = true }
    func wait() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func release() { continuation?.resume(); continuation = nil }
    func invoke<Request: Encodable & Sendable,Response: Decodable & Sendable>(_ name: String,request: Request,idempotencyKey: IdempotencyKey) async throws -> Response {
        let encoded = try JSONEncoder().encode(request)
        let body = try JSONSerialization.jsonObject(with: encoded) as! [String:Any]
        calls.append(encoded)
        if holding { holding = false; await withCheckedContinuation { continuation = $0; started?.resume(); started = nil } }
        if behavior == .denied { throw FunctionClientError.api(statusCode:403,code:"denied",message:"Denied") }
        if behavior == .unavailable { throw FunctionClientError.api(statusCode:503,code:"unavailable",message:"Not activated") }
        let data: Data
        if body["operation"] as? String == "merchantInventoryPage" {
            data = try inventoryData(query: body["query"] as? String ?? "",after: body["cursor"] != nil,mode:behavior)
        } else if body["operation"] as? String == "merchantLocationsPage" {
            let after = body["afterId"] != nil
            let focus = (body["focusId"] as? String).flatMap(UUID.init(uuidString:))
            let focused: Any = behavior == .focusRevoked ? NSNull() : focus.map { location($0) as Any } ?? NSNull()
            let next: Any = after ? NSNull() : discoveryID(1).uuidString as Any
            let rows = behavior == .focusRevoked && after ? [] : [location(discoveryID(after ? 3 : 1))]
            data = try JSONSerialization.data(withJSONObject:["locations":rows,
                "focusedLocation":focused,"nextCursor":next])
        } else { throw FunctionClientError.invalidResponse }
        return try JSONDecoder().decode(Response.self,from:data)
    }
}
