import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakCatalogueLoadingTests: XCTestCase {
    @MainActor
    func testStartupFetchesOneGlobalPageAndBrowseLoadsOnlySelectedCategory() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        XCTAssertEqual(model.v1Catalogue?.skus.count, 1)
        XCTAssertNotNil(model.v1Catalogue?.nextCursor)
        XCTAssertEqual(model.categories(forBrowseNode: "milk"), [CatalogueLoadingFunctions.categoryID])
        let initial = await functions.requests
        XCTAssertEqual(initial.filter { $0 == "global" }.count, 1)
        XCTAssertFalse(initial.contains("category"))
        XCTAssertFalse(initial.contains("customerRestaurants"))
        await model.loadV1BrowseNode("milk")
        XCTAssertEqual(model.v1CategoryProducts[CatalogueLoadingFunctions.categoryID]?.count, 2)
        XCTAssertEqual(model.v1BrowseProducts.count, 2)
        XCTAssertEqual(model.products(forBrowseNode: "milk").count, 2)
        XCTAssertTrue(model.products(forBrowseNode: "missing").isEmpty)
        XCTAssertEqual(DastakGroceryPresentation.families(model.v1BrowseProducts).first?.packs.count, 2)
        let loaded = await functions.requests
        XCTAssertEqual(loaded.filter { $0 == "global" }.count, 1)
        XCTAssertEqual(loaded.filter { $0 == "category" }.count, 2)
        await model.loadV1BrowseNode("milk")
        let cached = await functions.requests
        XCTAssertEqual(cached, loaded)
    }

    @MainActor
    func testCategoryFailureRetriesWithoutPoisoningGlobalCatalogue() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        await functions.configureCategory(.offline)
        await model.loadV1BrowseNode("milk")
        XCTAssertTrue(model.failedV1CategoryIDs.contains(CatalogueLoadingFunctions.categoryID))
        XCTAssertNil(model.v1CategoryProducts[CatalogueLoadingFunctions.categoryID])
        XCTAssertNil(model.v1CatalogueRefreshFailure)
        XCTAssertEqual(model.v1Catalogue?.skus.count, 1)
        await functions.configureCategory(.normal)
        await model.loadV1BrowseNode("milk", force: true)
        XCTAssertTrue(model.failedV1CategoryIDs.isEmpty)
        XCTAssertEqual(model.v1CategoryProducts[CatalogueLoadingFunctions.categoryID]?.count, 2)
    }

    @MainActor
    func testRepeatedCursorAndChangedVersionCannotPublishIncompleteCategory() async throws {
        for mode in [CatalogueLoadingFunctions.CategoryMode.repeatedCursor, .changedVersion, .endless] {
            let functions = CatalogueLoadingFunctions()
            let model = DastakCustomerModel(functions: functions)
            await model.refreshV1Catalogue()
            await functions.configureCategory(mode)
            await model.loadV1BrowseNode("milk")
            XCTAssertNil(model.v1CategoryProducts[CatalogueLoadingFunctions.categoryID])
            XCTAssertTrue(model.failedV1CategoryIDs.contains(CatalogueLoadingFunctions.categoryID))
            XCTAssertTrue(model.loadingV1CategoryIDs.isEmpty)
            XCTAssertEqual(model.v1BrowseProducts.count, 1)
            let requests = await functions.requests
            XCTAssertLessThanOrEqual(requests.filter { $0 == "category" }.count, 20)
        }
    }

    @MainActor
    func testLateCategoryResponseCannotRepopulateRefreshedCatalogueCache() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        await functions.hold("category")
        let loading = Task { await model.loadV1BrowseNode("milk") }
        await functions.waitUntilHeld()
        await model.refreshV1Catalogue()
        await functions.release()
        await loading.value
        XCTAssertTrue(model.v1CategoryProducts.isEmpty)
        XCTAssertTrue(model.loadingV1CategoryIDs.isEmpty)
        XCTAssertTrue(model.failedV1CategoryIDs.isEmpty)
        XCTAssertEqual(model.v1BrowseProducts.count, 1)
    }

    @MainActor
    func testLatestSearchWinsAndFailureDoesNotChangeCatalogueState() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        model.searchText = "old"
        await functions.hold("old")
        let old = Task { await model.searchV1Catalogue() }
        await functions.waitUntilHeld()
        model.searchText = "new"
        await model.searchV1Catalogue()
        XCTAssertEqual(model.v1SearchResults.first?.packSize, "1 L")
        await functions.release()
        await old.value
        XCTAssertEqual(model.v1SearchResults.first?.packSize, "1 L")
        XCTAssertFalse(model.isSearchingV1Catalogue)
        model.searchText = "offline"
        XCTAssertTrue(model.v1SearchResults.isEmpty)
        XCTAssertTrue(model.isSearchingV1Catalogue)
        await model.searchV1Catalogue()
        XCTAssertNotNil(model.v1SearchRefreshFailure)
        XCTAssertTrue(model.v1SearchResults.isEmpty)
        XCTAssertNil(model.v1CatalogueRefreshFailure)
        XCTAssertEqual(model.v1Catalogue?.skus.count, 1)
        model.searchText = ""
        await model.searchV1Catalogue()
        XCTAssertNil(model.v1SearchRefreshFailure)
        XCTAssertFalse(model.isSearchingV1Catalogue)
    }

    @MainActor
    func testClearingQueryRejectsLateSearchResult() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        model.searchText = "old"
        await functions.hold("old")
        let loading = Task { await model.searchV1Catalogue() }
        await functions.waitUntilHeld()
        model.searchText = ""
        await model.searchV1Catalogue()
        await functions.release()
        await loading.value
        XCTAssertTrue(model.v1SearchResults.isEmpty)
        XCTAssertNil(model.v1SearchRefreshFailure)
        XCTAssertFalse(model.isSearchingV1Catalogue)
    }

    @MainActor
    func testSearchCanSucceedAndPageWhenInitialCatalogueFailed() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await functions.failGlobalPages(true)
        await model.refreshV1Catalogue()
        XCTAssertNil(model.v1Catalogue)
        XCTAssertNotNil(model.v1CatalogueRefreshFailure)
        model.searchText = "paged"
        await model.searchV1Catalogue()
        XCTAssertEqual(model.activeProducts.count, 100)
        XCTAssertTrue(model.hasMoreV1SearchResults)
        await model.loadMoreV1SearchResults()
        XCTAssertEqual(model.activeProducts.count, 101)
        XCTAssertNil(model.v1SearchRefreshFailure)
        XCTAssertNotNil(model.v1CatalogueRefreshFailure)
    }

    @MainActor
    func testSearchLoadsBeyondOneHundredAndDeduplicatesWithoutLosingExactPacks() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        model.searchText = "paged"
        await model.searchV1Catalogue()
        XCTAssertEqual(model.v1SearchResults.count, 100)
        XCTAssertTrue(model.hasMoreV1SearchResults)
        await model.loadMoreV1SearchResults()
        XCTAssertEqual(model.v1SearchResults.count, 101)
        XCTAssertEqual(model.v1SearchResults.last?.packSize, "1 L")
        XCTAssertEqual(Set(model.v1SearchResults.map(\.id)).count, 101)
        XCTAssertFalse(model.hasMoreV1SearchResults)
        XCTAssertFalse(model.isLoadingMoreV1SearchResults)
        await model.loadMoreV1SearchResults()
        let cursors = await functions.searchCursors
        XCTAssertEqual(cursors, [nil, "00000000-0000-4000-8000-000000000100"])
    }

    @MainActor
    func testSearchNextPageFailureKeepsResultsAndRetriesSameCursor() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        model.searchText = "paged"
        await model.searchV1Catalogue()
        await functions.configureSearch(.offlineNext)
        await model.loadMoreV1SearchResults()
        XCTAssertEqual(model.v1SearchResults.count, 100)
        XCTAssertTrue(model.hasMoreV1SearchResults)
        XCTAssertNotNil(model.v1SearchRefreshFailure)
        XCTAssertNil(model.v1CatalogueRefreshFailure)
        await functions.configureSearch(.normal)
        await model.loadMoreV1SearchResults()
        XCTAssertEqual(model.v1SearchResults.count, 101)
        XCTAssertNil(model.v1SearchRefreshFailure)
        let cursors = await functions.searchCursors
        XCTAssertEqual(cursors.count, 3)
        XCTAssertEqual(cursors[1], cursors[2])
    }

    @MainActor
    func testInvalidSearchFeedsKeepPriorPageAndRequireFreshSearch() async throws {
        for mode in [CatalogueLoadingFunctions.SearchMode.repeatedCursor, .changedVersion, .missingVersion, .oversized] {
            let functions = CatalogueLoadingFunctions()
            let model = DastakCustomerModel(functions: functions)
            model.searchText = "paged"
            await model.searchV1Catalogue()
            await functions.configureSearch(mode)
            await model.loadMoreV1SearchResults()
            XCTAssertEqual(model.v1SearchResults.count, 100)
            XCTAssertFalse(model.hasMoreV1SearchResults)
            XCTAssertNotNil(model.v1SearchRefreshFailure)
            XCTAssertFalse(model.isLoadingMoreV1SearchResults)
            await functions.configureSearch(.normal)
            await model.searchV1Catalogue()
            XCTAssertTrue(model.hasMoreV1SearchResults)
            XCTAssertNil(model.v1SearchRefreshFailure)
            await model.loadMoreV1SearchResults()
            XCTAssertEqual(model.v1SearchResults.count, 101)
        }
    }

    @MainActor
    func testLateSearchPageCannotReplaceNewQueryAndDuplicateLoadMoreIsIgnored() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        model.searchText = "paged"
        await model.searchV1Catalogue()
        await functions.hold("paged")
        let loading = Task { await model.loadMoreV1SearchResults() }
        await functions.waitUntilHeld()
        XCTAssertTrue(model.isLoadingMoreV1SearchResults)
        await model.loadMoreV1SearchResults()
        model.searchText = "new"
        XCTAssertTrue(model.v1SearchResults.isEmpty)
        XCTAssertFalse(model.hasMoreV1SearchResults)
        XCTAssertFalse(model.isLoadingMoreV1SearchResults)
        await model.searchV1Catalogue()
        await functions.release()
        await loading.value
        XCTAssertEqual(model.v1SearchResults.count, 1)
        XCTAssertEqual(model.v1SearchResults.first?.packSize, "1 L")
        XCTAssertNil(model.v1SearchRefreshFailure)
        let cursors = await functions.searchCursors
        XCTAssertEqual(cursors.count, 2)
    }

    @MainActor
    func testCancelledSearchNextPageCanRetryWithoutDiscardingResults() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        model.searchText = "paged"
        await model.searchV1Catalogue()
        await functions.hold("paged")
        let loading = Task { await model.loadMoreV1SearchResults() }
        await functions.waitUntilHeld()
        loading.cancel()
        await functions.release()
        await loading.value
        XCTAssertEqual(model.v1SearchResults.count, 100)
        XCTAssertTrue(model.hasMoreV1SearchResults)
        XCTAssertFalse(model.isLoadingMoreV1SearchResults)
        XCTAssertNil(model.v1SearchRefreshFailure)
        await model.loadMoreV1SearchResults()
        XCTAssertEqual(model.v1SearchResults.count, 101)
    }

    @MainActor
    func testRefreshingSameSearchRejectsOlderNextPageAndRestartsCursor() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        model.searchText = "paged"
        await model.searchV1Catalogue()
        await functions.hold("paged")
        let loading = Task { await model.loadMoreV1SearchResults() }
        await functions.waitUntilHeld()
        await model.searchV1Catalogue()
        await functions.release()
        await loading.value
        XCTAssertEqual(model.v1SearchResults.count, 100)
        XCTAssertTrue(model.hasMoreV1SearchResults)
        XCTAssertFalse(model.isLoadingMoreV1SearchResults)
        await model.loadMoreV1SearchResults()
        XCTAssertEqual(model.v1SearchResults.count, 101)
        let cursors = await functions.searchCursors
        XCTAssertEqual(cursors.count, 4)
        XCTAssertNil(cursors[2])
        XCTAssertEqual(cursors[1], cursors[3])
    }

    @MainActor
    func testEmptySearchPageWithCursorStillAllowsNextPage() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await functions.configureSearch(.emptyFirst)
        model.searchText = "paged"
        await model.searchV1Catalogue()
        XCTAssertTrue(model.v1SearchResults.isEmpty)
        XCTAssertTrue(model.hasMoreV1SearchResults)
        await model.loadMoreV1SearchResults()
        XCTAssertEqual(model.v1SearchResults.count, 2)
        XCTAssertFalse(model.hasMoreV1SearchResults)
        XCTAssertNil(model.v1SearchRefreshFailure)
    }

    @MainActor
    func testSearchResourceBoundReportsIncompleteFeedInsteadOfSilentSuccess() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await functions.configureSearch(.endless)
        model.searchText = "paged"
        await model.searchV1Catalogue()
        for _ in 0..<100 { await model.loadMoreV1SearchResults() }
        XCTAssertNotNil(model.v1SearchRefreshFailure)
        XCTAssertFalse(model.hasMoreV1SearchResults)
        XCTAssertFalse(model.isLoadingMoreV1SearchResults)
        let cursors = await functions.searchCursors
        XCTAssertEqual(cursors.count, 100)
        XCTAssertLessThanOrEqual(model.v1SearchResults.count, 10_000)
    }

    @MainActor
    func testCataloguePublishesWhileSavedAddressIsPendingAndLegacyResourcesAreDeferred() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await functions.hold("customer-addresses")
        let startup = Task { await model.bootstrap() }
        await functions.waitUntilHeld()
        // Allow the independent catalogue task to publish while the address is held.
        for _ in 0..<1000 {
            if model.v1Catalogue != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(model.v1Catalogue)
        await functions.release()
        await startup.value
        let requests = await functions.requests
        XCTAssertFalse(requests.contains("merchant-orders"))
        XCTAssertFalse(requests.contains("parcel-deliveries"))
        XCTAssertEqual(requests.filter { $0 == "global" }.count, 1)
    }

    @MainActor
    func testCancelledCategoryDoesNotBecomeAnEmptySuccessfulCache() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        await functions.hold("category")
        let loading = Task { await model.loadV1BrowseNode("milk") }
        await functions.waitUntilHeld()
        loading.cancel()
        await functions.release()
        await loading.value
        XCTAssertNil(model.v1CategoryProducts[CatalogueLoadingFunctions.categoryID])
        XCTAssertTrue(model.loadingV1CategoryIDs.isEmpty)
        XCTAssertTrue(model.failedV1CategoryIDs.isEmpty)
        await model.loadV1BrowseNode("milk")
        XCTAssertEqual(model.v1CategoryProducts[CatalogueLoadingFunctions.categoryID]?.count, 2)
    }

    @MainActor
    func testNewRailWaitsForCancelledSharedCategoryThenRetriesInsteadOfStalling() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        await functions.hold("category")
        let previousRail = Task { await model.loadV1BrowseNode("milk") }
        await functions.waitUntilHeld()
        previousRail.cancel()
        let newRail = Task { await model.loadV1BrowseNode("milk") }
        await Task.yield()
        await functions.release()
        await previousRail.value
        await newRail.value
        XCTAssertEqual(model.v1CategoryProducts[CatalogueLoadingFunctions.categoryID]?.count, 2)
        XCTAssertTrue(model.loadingV1CategoryIDs.isEmpty)
        XCTAssertTrue(model.failedV1CategoryIDs.isEmpty)
    }

    @MainActor
    func testWishlistResolvesMissingProductOnDemandWithoutLoadingAllProductsAtStartup() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        await model.refreshWishlist()
        XCTAssertTrue(model.wishlistRetailProducts.isEmpty)
        await model.resolveWishlistContents()
        XCTAssertEqual(model.wishlistRetailProducts.first?.packSize, "1 L")
        XCTAssertEqual(model.unresolvedWishlistItemCount, 0)
        let requests = await functions.requests
        XCTAssertEqual(requests.filter { $0 == "global" }.count, 2)
        await model.resolveWishlistContents()
        let cached = await functions.requests
        XCTAssertEqual(cached, requests)
    }

    @MainActor
    func testSavedProductLookupFailureIsRetryableAndDoesNotPoisonCatalogue() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        await model.refreshWishlist()
        await functions.failGlobalPages(true)
        await model.resolveWishlistContents()
        XCTAssertNotNil(model.savedItemsRefreshFailure)
        XCTAssertNil(model.v1CatalogueRefreshFailure)
        XCTAssertEqual(model.v1Catalogue?.skus.count, 1)
        await functions.failGlobalPages(false)
        await model.resolveWishlistContents()
        XCTAssertNil(model.savedItemsRefreshFailure)
        XCTAssertEqual(model.wishlistRetailProducts.count, 1)
    }

    @MainActor
    func testLateSavedProductLookupCannotRepopulateRefreshedCache() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        await model.refreshWishlist()
        await functions.hold("global")
        let resolving = Task { await model.resolveWishlistContents() }
        await functions.waitUntilHeld()
        await model.refreshV1Catalogue()
        await functions.release()
        await resolving.value
        XCTAssertTrue(model.wishlistRetailProducts.isEmpty)
        XCTAssertFalse(model.isResolvingSavedItems)
    }

    @MainActor
    func testOrderAgainResolvesExactPackOutsideStartupPage() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        let result = await model.reorderWithCurrentCatalogue(try order())
        XCTAssertTrue(result.openedBasket)
        XCTAssertEqual(model.cart.entries.first?.product.packSize, "1 L")
        XCTAssertEqual(model.cart.itemCount, 2)
    }

    @MainActor
    func testOrderAgainCannotOverwriteBasketEditedDuringLookup() async throws {
        let functions = CatalogueLoadingFunctions()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshV1Catalogue()
        let order = try order()
        await functions.hold("global")
        let reordering = Task { await model.reorderWithCurrentCatalogue(order) }
        await functions.waitUntilHeld()
        model.addToCart(try XCTUnwrap(model.v1Catalogue?.skus.first))
        await functions.release()
        let result = await reordering.value
        XCTAssertFalse(result.openedBasket)
        XCTAssertEqual(model.cart.itemCount, 1)
        XCTAssertEqual(model.cart.entries.first?.product.packSize, "500 ml")
    }

    private func order() throws -> DastakV1OrderSnapshot {
        try JSONDecoder().decode(DastakV1OrderSnapshot.self, from: Data("""
        {"id":"99999999-9999-4999-8999-999999999999","displayOrderNumber":"TEST-1","orderType":"RETAIL",
        "status":"DELIVERED","version":1,"createdAt":"2026-10-10T00:00:00Z","updatedAt":"2026-10-10T00:00:00Z",
        "price":{"snapshotKind":"FINAL","subtotalPaise":9000,"deliveryFeePaise":1500,"platformFeePaise":210,"taxPaise":0,"discountPaise":0,"totalPaise":10710,"currencyCode":"INR"},
        "lines":[{"id":"88888888-8888-4888-8888-888888888888","lineType":"RETAIL_SKU",
        "skuId":"55555555-5555-4555-8555-555555555555","name":"Test Milk","packSize":"1 L","quantity":2,
        "unitPricePaise":4500,"lineTotalPaise":9000,"status":"DELIVERED"}]}
        """.utf8))
    }
}

private actor CatalogueLoadingFunctions: FunctionClient {
    enum CategoryMode { case normal, offline, repeatedCursor, changedVersion, endless }
    enum SearchMode { case normal, offlineNext, repeatedCursor, changedVersion, missingVersion, oversized, emptyFirst, endless }
    static let categoryID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let typeID = "11111111-1111-4111-8111-111111111111"
    private let subcategoryID = "33333333-3333-4333-8333-333333333333"
    private let smallID = "44444444-4444-4444-8444-444444444444"
    private let largeID = "55555555-5555-4555-8555-555555555555"
    private var mode: CategoryMode = .normal
    private var searchMode: SearchMode = .normal
    private(set) var searchCursors: [String?] = []
    private var globalPagesFail = false
    private var heldKey: String?
    private var blocked: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var requests: [String] = []

    func configureCategory(_ mode: CategoryMode) { self.mode = mode }
    func configureSearch(_ mode: SearchMode) { searchMode = mode }
    func failGlobalPages(_ fail: Bool) { globalPagesFail = fail }
    func hold(_ key: String) { heldKey = key }
    func waitUntilHeld() async {
        if blocked != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { blocked?.resume(); blocked = nil }

    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Input, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let operation = body["operation"] as? String ?? name
        let key = operation == "customerCatalogue" ? (body["query"] as? String ?? (body["categoryId"] == nil ? "global" : "category")) : name == "customer-addresses" ? name : operation
        requests.append(key)
        let response: Any
        if name == "customer-wishlist" {
            response = ["items": [["kind": "RETAIL_SKU", "itemId": largeID, "createdAt": "2026-10-10T00:00:00Z"]]]
        } else if operation == "catalogueBrowseMap" {
            response = ["version": 1, "nodes": [
                ["key": "fresh", "kind": "SECTION", "label": "Fresh", "sortOrder": 0, "sources": []],
                ["key": "milk", "parentKey": "fresh", "kind": "DESTINATION", "label": "Milk", "sortOrder": 0,
                 "sources": [["typeSlug": "grocery", "categorySlug": "dairy", "excludedCategorySlugs": [], "excludedSubcategorySlugs": []]]]
            ]]
        } else if operation == "customerCatalogue" {
            if key == "offline" || (key == "category" && mode == .offline) || (key == "global" && globalPagesFail) { throw URLError(.notConnectedToInternet) }
            let second = body["cursor"] != nil
            let product: [String: Any] = ["id": second || key == "new" ? largeID : smallID,
                "categoryId": Self.categoryID.uuidString, "subcategoryId": subcategoryID,
                "brand": ["id": typeID, "name": "Test", "slug": "test"], "name": "Test Milk", "slug": "test-milk",
                "packSize": second || key == "new" ? "1 L" : "500 ml", "listPricePaise": 5000,
                "sellingPricePaise": 4500, "currencyCode": "INR", "logisticsAttributes": [:]]
            var value: [String: Any] = ["catalogueVersion": key == "category" && mode == .changedVersion ? "2" : "1",
                "categoryTypes": [["id": typeID, "name": "Grocery", "slug": "grocery", "sortOrder": 0]],
                "categories": [["id": Self.categoryID.uuidString, "categoryTypeId": typeID, "name": "Dairy", "slug": "dairy", "sortOrder": 0]],
                "subcategories": [["id": subcategoryID, "categoryId": Self.categoryID.uuidString, "name": "Milk", "slug": "milk", "sortOrder": 0]],
                "skus": [product]]
            if (key == "global" && !second) || (key == "category" && (!second || mode == .repeatedCursor || mode == .endless)) {
                value["nextCursor"] = ["name": "Test Milk", "skuId": mode == .endless ? UUID().uuidString : smallID]
            }
            if key == "paged" {
                XCTAssertEqual(body["limit"] as? Int, 100)
                searchCursors.append((body["cursor"] as? [String: Any])?["skuId"] as? String)
                if second && searchMode == .offlineNext { throw URLError(.notConnectedToInternet) }
                let ids = second ? (100...101) : (1...100)
                value["skus"] = ids.map { index in
                    var item = product
                    item["id"] = String(format: "00000000-0000-4000-8000-%012d", index)
                    return item
                }
                if !second || searchMode == .repeatedCursor || searchMode == .endless {
                    value["nextCursor"] = ["name": "Test Milk", "skuId": searchMode == .endless ? UUID().uuidString : "00000000-0000-4000-8000-000000000100"]
                }
                if second && searchMode == .changedVersion { value["catalogueVersion"] = "2" }
                if second && searchMode == .missingVersion { value.removeValue(forKey: "catalogueVersion") }
                if second && searchMode == .oversized { value["skus"] = Array(repeating: product, count: 101) }
                if !second && searchMode == .emptyFirst { value["skus"] = [[String: Any]]() }
            }
            response = value
        } else if name == "customer-addresses" {
            response = ["addresses": []]
        } else {
            requests.append(name)
            throw URLError(.notConnectedToInternet)
        }
        let data = try JSONSerialization.data(withJSONObject: response)
        if heldKey == key {
            heldKey = nil
            await withCheckedContinuation { blocked = $0; started?.resume(); started = nil }
        }
        return try JSONDecoder().decode(Result.self, from: data)
    }
}
