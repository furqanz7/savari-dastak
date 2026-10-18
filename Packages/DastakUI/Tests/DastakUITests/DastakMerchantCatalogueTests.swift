import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor final class DastakMerchantCatalogueTests: XCTestCase {
    func testSearchAtMapRootAndStorefrontRootSelectProductResults() {
        XCTAssertTrue(DastakMerchantCataloguePresentation.showsResults(query: "tea", selectedOnly: false, hasDestination: false))
        XCTAssertTrue(DastakMerchantCataloguePresentation.showsResults(query: "tea", selectedOnly: false, hasDestination: true))
        XCTAssertTrue(DastakMerchantCataloguePresentation.showsResults(query: "", selectedOnly: true, hasDestination: false))
        XCTAssertFalse(DastakMerchantCataloguePresentation.showsResults(query: "  ", selectedOnly: false, hasDestination: false))
        XCTAssertFalse(DastakMerchantCataloguePresentation.showsResults(query: "", selectedOnly: true, hasDestination: true))
    }
    func testSearchUsesBrandPackVariantTaxonomyDescriptionAndSearchTerms() throws {
        let snapshot = try fixture()
        for query in ["tea", "ACME", "  100 g ", "assam", "aromatic", "beverages", "hot drinks", "tea leaves", "chai"] {
            XCTAssertEqual(products(snapshot, query: query).map(\.id), [catalogueTea], query)
        }
        XCTAssertTrue(products(snapshot, query: "No match").isEmpty)
    }
    func testSearchIsGlobalWithinScopeEvenWhenAnotherCategoryWasOpen() throws {
        let result = DastakMerchantCataloguePresentation.products(try fixture(), query: "Tea", selectedOnly: false,
            categoryID: catalogueBreadCategory, map: try browseMap(), nodeKey: "bread")
        XCTAssertEqual(result.map(\.id), [catalogueTea])
    }
    func testStorefrontIncludesStagedAddsAndExcludesStagedRemovals() throws {
        let snapshot = try fixture()
        XCTAssertEqual(products(snapshot, selectedOnly: true).map(\.id), [catalogueBread])
        let pending = [catalogueTea: true, catalogueBread: false]
        XCTAssertEqual(products(snapshot, selectedOnly: true, pending: pending).map(\.id), [catalogueTea])
        XCTAssertTrue(products(snapshot, query: "Bread", selectedOnly: true, pending: pending).isEmpty)
    }
    func testMapAndTaxonomyRoutesShareScopeAndLoadedMatching() throws {
        let snapshot = try fixture(), map = try browseMap()
        let mapped = DastakMerchantCataloguePresentation.products(snapshot, query: "", selectedOnly: false, map: map, nodeKey: "drinks")
        let taxonomy = DastakMerchantCataloguePresentation.products(snapshot, query: "", selectedOnly: false, categoryID: catalogueTeaCategory)
        XCTAssertEqual(mapped.map(\.id), taxonomy.map(\.id))
        XCTAssertTrue(DastakMerchantCataloguePresentation.products(snapshot, query: "", selectedOnly: true, map: map, nodeKey: "drinks").isEmpty)
        XCTAssertEqual(DastakMerchantCataloguePresentation.products(snapshot, query: "", selectedOnly: true, pending: [catalogueTea: true], map: map, nodeKey: "drinks").map(\.id), [catalogueTea])
    }
    func testDepartmentFilterFallsBackToCategoryTypeWhenSkuOmitsIt() throws {
        let snapshot = try fixture()
        XCTAssertEqual(DastakMerchantCataloguePresentation.products(snapshot, query: "", selectedOnly: false, typeID: catalogueDrinkType).map(\.id), [catalogueTea])
    }
    func testUnknownBrowseNodeDoesNotAccidentallyShowWholeCatalogue() throws {
        XCTAssertTrue(DastakMerchantCataloguePresentation.products(try fixture(), query: "", selectedOnly: false, map: try browseMap(), nodeKey: "missing").isEmpty)
    }
    func testEmptyCopyDistinguishesStalePartialAndSelectedScope() {
        XCTAssertTrue(DastakMerchantCataloguePresentation.emptyMessage(query: "Tea", selectedOnly: false, truncated: true, current: true).contains("incomplete"))
        XCTAssertTrue(DastakMerchantCataloguePresentation.emptyMessage(query: "", selectedOnly: true, truncated: false, current: false).contains("could not be verified"))
        XCTAssertTrue(DastakMerchantCataloguePresentation.emptyMessage(query: "", selectedOnly: true, truncated: false, current: true).contains("Unsaved selections"))
    }
    func testInvalidDuplicateSnapshotDoesNotPassValidation() throws {
        var object = catalogueObject(); var skus = object["skus"] as! [[String: Any]]; skus.append(skus[0]); object["skus"] = skus
        let snapshot = try JSONDecoder().decode(DastakV1MerchantCatalogueSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(DastakMerchantCataloguePresentation.validSnapshot(snapshot))
    }
    func testMapFailureDoesNotPoisonSuccessfulProductsOrStockControls() async {
        let functions = CatalogueFunctions(); await functions.setMap(.offline)
        let merchant = model(functions); await merchant.restoreMerchantCommands(); await merchant.refreshCanonicalCatalogue()
        XCTAssertNotNil(merchant.canonicalCatalogue); XCTAssertTrue(merchant.canonicalCatalogueCurrent)
        XCTAssertNil(merchant.catalogueRefreshFailure); XCTAssertNotNil(merchant.catalogueBrowseFailure)
        XCTAssertNil(merchant.canonicalBrowseMap); XCTAssertFalse(merchant.canonicalChangesDisabled)
    }
    func testProductsBecomeAvailableBeforeSlowNavigationCompletes() async {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await merchant.restoreMerchantCommands()
        await functions.holdMap()
        let read = Task { await merchant.refreshCanonicalCatalogue() }
        await functions.waitForMap()
        for _ in 0..<2000 { if merchant.canonicalCatalogueCurrent { break }; await Task.yield() }
        XCTAssertTrue(merchant.canonicalCatalogueCurrent); XCTAssertFalse(merchant.isRefreshingCatalogue)
        XCTAssertTrue(merchant.isRefreshingCatalogueMap); XCTAssertFalse(merchant.canonicalChangesDisabled)
        await functions.releaseMap(); await read.value
        XCTAssertFalse(merchant.isRefreshingCatalogueMap)
    }
    func testInvalidOrMissingMapUsesFallbackWithoutEmptyProductClaim() async {
        for reply in [CatalogueFunctions.MapReply.missing, .invalid] {
            let functions = CatalogueFunctions(); await functions.setMap(reply)
            let merchant = model(functions); await merchant.refreshCanonicalCatalogue()
            XCTAssertTrue(merchant.canonicalCatalogueCurrent); XCTAssertNotNil(merchant.catalogueBrowseFailure)
            XCTAssertNil(merchant.canonicalBrowseMap)
        }
    }
    func testTransientProductFailureRetainsStaleDataButBlocksStockSelectionAndOperatingWrites() async throws {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await merchant.refreshCanonicalCatalogue(); let sku = try XCTUnwrap(merchant.canonicalCatalogue?.skus.first)
        await functions.setProducts(.offline); await merchant.refreshCanonicalCatalogue(reportFailure: false)
        XCTAssertNotNil(merchant.canonicalCatalogue); XCTAssertNotNil(merchant.catalogueCheckedAt)
        XCTAssertFalse(merchant.canonicalCatalogueCurrent); XCTAssertTrue(merchant.canonicalChangesDisabled)
        merchant.stageCanonicalSelection(sku)
        let stock = await merchant.saveStockCount(sku, quantity: 5); XCTAssertFalse(stock)
        await merchant.setCanonicalBranch(isOpen: false, acceptingOrders: false)
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty); XCTAssertFalse(merchant.hasPendingCanonicalSelections)
        await functions.setProducts(.data(try catalogueData())); await merchant.refreshCanonicalCatalogue()
        XCTAssertTrue(merchant.canonicalCatalogueCurrent); XCTAssertNil(merchant.catalogueRefreshFailure)
    }
    func testDeniedProductReadClearsCachedAmountsSelectionsAndTimestamp() async throws {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await merchant.restoreMerchantCommands()
        await merchant.refreshCanonicalCatalogue(); merchant.stageCanonicalSelection(try XCTUnwrap(merchant.canonicalCatalogue?.skus.first))
        await functions.setProducts(.denied); await merchant.refreshCanonicalCatalogue(reportFailure: false)
        XCTAssertNil(merchant.canonicalCatalogue); XCTAssertNil(merchant.catalogueCheckedAt)
        XCTAssertTrue(merchant.pendingCanonicalSelections.isEmpty); XCTAssertFalse(merchant.canonicalCatalogueCurrent)
    }
    func testWrongLocationResponseCannotReplacePreviouslyVerifiedCatalogue() async throws {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await merchant.refreshCanonicalCatalogue()
        await functions.setProducts(.data(try catalogueData(branch: UUID()))); await merchant.refreshCanonicalCatalogue(reportFailure: false)
        XCTAssertEqual(merchant.canonicalCatalogue?.branch.branchID, catalogueBranch)
        XCTAssertFalse(merchant.canonicalCatalogueCurrent); XCTAssertNotNil(merchant.catalogueRefreshFailure)
    }
    func testWrongStoreTypeClearsCatalogueAndExplainsHowToRecover() async throws {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await merchant.refreshCanonicalCatalogue()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: catalogueData()) as? [String: Any])
        var branch = object["branch"] as! [String: Any]; branch["merchantType"] = "RESTAURANT_CAFE"; object["branch"] = branch
        await functions.setProducts(.data(try JSONSerialization.data(withJSONObject: object)))
        await merchant.refreshCanonicalCatalogue(reportFailure: false)
        XCTAssertNil(merchant.canonicalCatalogue); XCTAssertFalse(merchant.canonicalCatalogueCurrent)
        XCTAssertTrue(merchant.catalogueRefreshFailure?.contains("business type") == true)
    }
    func testAccountChangeDuringProductsReadCannotPublishOldActorData() async {
        let functions = CatalogueFunctions(), identity = MerchantJournalTestIdentity()
        let merchant = model(functions, identity: identity)
        await functions.holdProducts()
        let read = Task { await merchant.refreshCanonicalCatalogue(reportFailure: false) }
        await functions.waitForProducts(); await identity.change(); await functions.releaseProducts(); await read.value
        XCTAssertNil(merchant.canonicalCatalogue); XCTAssertTrue(merchant.sessionNeedsAttention)
        XCTAssertFalse(merchant.isRefreshingCatalogue); XCTAssertFalse(merchant.canonicalCatalogueCurrent)
    }
    func testChangedAccountCannotReusePreviousActorsCatalogue() async {
        let functions = CatalogueFunctions(), identity = MerchantJournalTestIdentity(), merchant = model(functions, identity: identity)
        await merchant.refreshCanonicalCatalogue(); await identity.change(); await merchant.refreshCanonicalCatalogue(reportFailure: false)
        XCTAssertNil(merchant.canonicalCatalogue); XCTAssertTrue(merchant.sessionNeedsAttention)
    }
    func testStalledProductAndMapReadsReleaseSpinnersAndAllowRetry() async {
        let functions = CatalogueFunctions(), merchant = model(functions, timeout: .milliseconds(80))
        await functions.holdProducts(); await functions.holdMap()
        await merchant.refreshCanonicalCatalogue(reportFailure: false)
        XCTAssertFalse(merchant.isRefreshingCatalogue); XCTAssertFalse(merchant.isRefreshingCatalogueMap)
        XCTAssertNotNil(merchant.catalogueRefreshFailure)
        await merchant.refreshCanonicalCatalogue(reportFailure: false)
        XCTAssertTrue(merchant.canonicalCatalogueCurrent)
        await functions.releaseProducts(); await functions.releaseMap()
    }
    func testOverlappingRefreshesAreCoalesced() async {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await functions.holdProducts()
        let first = Task { await merchant.refreshCanonicalCatalogue() }
        await functions.waitForProducts(); await merchant.refreshCanonicalCatalogue(); await functions.releaseProducts(); await first.value
        let reads = await functions.productReads; XCTAssertEqual(reads, 1)
    }
    func testOmittedPendingSkuIsRetainedAndPartialBatchCannotBeSent() async throws {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await merchant.restoreMerchantCommands()
        await merchant.refreshCanonicalCatalogue(); merchant.stageCanonicalSelection(try XCTUnwrap(merchant.canonicalCatalogue?.skus.first))
        await functions.setProducts(.data(try catalogueData(omitTea: true, truncated: true))); await merchant.refreshCanonicalCatalogue()
        XCTAssertEqual(merchant.pendingCanonicalSelections[catalogueTea], true); XCTAssertEqual(merchant.missingCanonicalSelectionCount, 1)
        await merchant.saveCanonicalSelections()
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty); XCTAssertNotNil(merchant.errorMessage)
        XCTAssertTrue(merchant.hasPendingCanonicalSelections)
    }
    func testFreshSnapshotAcknowledgesOnlyMatchingSelections() async throws {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await merchant.restoreMerchantCommands()
        await merchant.refreshCanonicalCatalogue(); merchant.stageCanonicalSelection(try XCTUnwrap(merchant.canonicalCatalogue?.skus.first))
        await functions.setProducts(.data(try catalogueData(teaSelected: true))); await merchant.refreshCanonicalCatalogue()
        XCTAssertTrue(merchant.pendingCanonicalSelections.isEmpty)
    }
    func testOperatingChangeDoesNotDiscardUnrelatedUnsavedSelections() async throws {
        let functions = CatalogueFunctions(), merchant = model(functions)
        await merchant.restoreMerchantCommands()
        await merchant.refreshCanonicalCatalogue(); merchant.stageCanonicalSelection(try XCTUnwrap(merchant.canonicalCatalogue?.skus.first))
        await merchant.setCanonicalBranch(isOpen: false, acceptingOrders: false)
        XCTAssertEqual(merchant.pendingCanonicalSelections[catalogueTea], true)
        XCTAssertNil(merchant.pendingOperationCommand)
    }
    private func products(_ snapshot: DastakV1MerchantCatalogueSnapshot, query: String = "", selectedOnly: Bool = false, pending: [UUID: Bool] = [:]) -> [DastakV1MerchantCatalogueSnapshot.SKU] {
        DastakMerchantCataloguePresentation.products(snapshot, query: query, selectedOnly: selectedOnly, pending: pending)
    }
    private func fixture() throws -> DastakV1MerchantCatalogueSnapshot { try JSONDecoder().decode(DastakV1MerchantCatalogueSnapshot.self, from: catalogueData()) }
    private func browseMap() throws -> DastakV1CatalogueBrowseMap { try JSONDecoder().decode(DastakV1CatalogueBrowseMap.self, from: catalogueMapData()) }
    private func model(_ functions: CatalogueFunctions, identity: MerchantJournalTestIdentity? = nil, timeout: Duration = .seconds(2)) -> DastakMerchantModel {
        .init(services: .init(functions: functions, accountIDProvider: { if let identity { return await identity.id }; return catalogueActor }, objectUploader: { _, _, _, _, _ in }), journalStorage: DastakMerchantMemoryJournal(), requestTimeout: timeout)
    }
}

private let catalogueBranch = UUID(uuidString: "95000000-0000-4000-8000-000000000001")!
private let catalogueActor = UUID(uuidString: "95000000-0000-4000-8000-000000000002")!
private let catalogueTea = UUID(uuidString: "95000000-0000-4000-8000-000000000003")!
private let catalogueBread = UUID(uuidString: "95000000-0000-4000-8000-000000000004")!
private let catalogueTeaCategory = UUID(uuidString: "95000000-0000-4000-8000-000000000005")!
private let catalogueBreadCategory = UUID(uuidString: "95000000-0000-4000-8000-000000000006")!
private let catalogueDrinkType = UUID(uuidString: "95000000-0000-4000-8000-000000000007")!
private func catalogueObject(branch: UUID = catalogueBranch, omitTea: Bool = false, truncated: Bool = false, teaSelected: Bool = false) -> [String: Any] {
    let breadType = "95000000-0000-4000-8000-000000000008", teaSub = "95000000-0000-4000-8000-000000000009", breadSub = "95000000-0000-4000-8000-000000000010"
    let tea: [String: Any] = ["skuId": catalogueTea.uuidString, "categoryId": catalogueTeaCategory.uuidString, "subcategoryId": teaSub,
        "name": "Tea", "brandName": "Acme", "variant": "Assam", "packSize": "100 g", "description": "Aromatic leaves", "galleryImageKeys": [], "searchTerms": ["chai"], "listPricePaise": 1000, "sellingPricePaise": 900, "currencyCode": "INR", "catalogueStatus": "ACTIVE", "selected": teaSelected, "selectionVersion": 1, "stockQuantity": 20]
    let bread: [String: Any] = ["skuId": catalogueBread.uuidString, "categoryId": catalogueBreadCategory.uuidString, "subcategoryId": breadSub,
        "name": "Bread", "packSize": "400 g", "galleryImageKeys": [], "searchTerms": [], "listPricePaise": 500, "sellingPricePaise": 500, "currencyCode": "INR", "catalogueStatus": "ACTIVE", "selected": true, "selectionVersion": 1, "stockQuantity": 10]
    return ["branch": ["branchId": branch.uuidString, "branchName": "Essentials", "branchStatus": "ACTIVE", "branchVersion": 1, "organizationId": catalogueActor.uuidString, "organizationName": "Dastak", "merchantType": "RETAIL", "operationalState": ["isOpen": true, "acceptingOrders": true, "version": 1], "capacity": ["limit": 20, "held": 0, "available": 20]],
        "categoryTypes": [["categoryTypeId": catalogueDrinkType.uuidString, "name": "Beverages", "slug": "drinks", "sortOrder": 0], ["categoryTypeId": breadType, "name": "Bakery", "slug": "bread", "sortOrder": 1]],
        "categories": [["categoryId": catalogueTeaCategory.uuidString, "categoryTypeId": catalogueDrinkType.uuidString, "name": "Hot drinks", "slug": "tea", "sortOrder": 0], ["categoryId": catalogueBreadCategory.uuidString, "categoryTypeId": breadType, "name": "Fresh bakery", "slug": "bread", "sortOrder": 1]],
        "subcategories": [["subcategoryId": teaSub, "categoryId": catalogueTeaCategory.uuidString, "name": "Tea leaves", "slug": "leaves", "sortOrder": 0], ["subcategoryId": breadSub, "categoryId": catalogueBreadCategory.uuidString, "name": "Loaves", "slug": "loaves", "sortOrder": 0]],
        "skus": omitTea ? [bread] : [tea, bread], "truncated": truncated]
}
private func catalogueData(branch: UUID = catalogueBranch, omitTea: Bool = false, truncated: Bool = false, teaSelected: Bool = false) throws -> Data {
    try JSONSerialization.data(withJSONObject: catalogueObject(branch: branch, omitTea: omitTea, truncated: truncated, teaSelected: teaSelected))
}
private func catalogueMapData() throws -> Data {
    try JSONSerialization.data(withJSONObject: ["version": 1, "nodes": [
        ["key": "food", "kind": "SECTION", "label": "Food", "sortOrder": 0, "sources": []],
        ["key": "drinks", "parentKey": "food", "kind": "DESTINATION", "label": "Drinks", "sortOrder": 0, "sources": [["typeSlug": "drinks", "excludedCategorySlugs": [], "excludedSubcategorySlugs": []]]],
        ["key": "bread", "parentKey": "food", "kind": "DESTINATION", "label": "Bread", "sortOrder": 1, "sources": [["typeSlug": "bread", "excludedCategorySlugs": [], "excludedSubcategorySlugs": []]]]]])
}
private actor CatalogueFunctions: FunctionClient {
    enum Reply: Sendable { case data(Data), offline, denied }
    enum MapReply: Sendable { case good, missing, invalid, offline }
    var writes: [Data] = []
    var productReads = 0
    private var products: Reply = .data(try! catalogueData()), map: MapReply = .good
    private var holdingProducts = false, holdingMap = false
    private var productWaiter: CheckedContinuation<Void, Never>?, mapWaiter: CheckedContinuation<Void, Never>?
    private var productContinuation: CheckedContinuation<Data, Never>?, mapContinuation: CheckedContinuation<Data, Never>?
    func setProducts(_ value: Reply) { products = value }
    func setMap(_ value: MapReply) { map = value }
    func holdProducts() { holdingProducts = true }
    func holdMap() { holdingMap = true }
    func waitForProducts() async { if productContinuation == nil { await withCheckedContinuation { productWaiter = $0 } } }
    func waitForMap() async { if mapContinuation == nil { await withCheckedContinuation { mapWaiter = $0 } } }
    func releaseProducts() { productContinuation?.resume(returning: try! catalogueData()); productContinuation = nil }
    func releaseMap() { mapContinuation?.resume(returning: try! catalogueMapData()); mapContinuation = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let data = try JSONEncoder().encode(request), body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let result: Data
        switch body["operation"] as? String {
        case "merchantSnapshot":
            productReads += 1
            if holdingProducts { holdingProducts = false; result = await withCheckedContinuation { productContinuation = $0; productWaiter?.resume(); productWaiter = nil } }
            else { switch products { case let .data(value): result = value; case .offline: throw URLError(.notConnectedToInternet); case .denied: throw FunctionClientError.api(statusCode: 403, code: "denied", message: "Denied") } }
        case "catalogueBrowseMap":
            if holdingMap { holdingMap = false; result = await withCheckedContinuation { mapContinuation = $0; mapWaiter?.resume(); mapWaiter = nil } }
            else { switch map { case .good: result = try catalogueMapData(); case .missing: result = Data("null".utf8); case .invalid: result = Data(#"{"version":1,"nodes":[]}"#.utf8); case .offline: throw URLError(.notConnectedToInternet) } }
        case "updateBranchOperationalState":
            writes.append(data)
            result = try JSONSerialization.data(withJSONObject: ["branchId": catalogueBranch.uuidString, "isOpen": body["isOpen"]!, "acceptingOrders": body["acceptingOrders"]!, "version": 2, "updatedAt": "2026-10-18T00:00:00Z"])
        default: writes.append(data); throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: result)
    }
}
