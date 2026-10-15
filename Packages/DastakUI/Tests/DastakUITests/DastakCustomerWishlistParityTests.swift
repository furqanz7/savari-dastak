import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakCustomerWishlistParityTests: XCTestCase {
    func testFailedFirstReadDoesNotClaimAnEmptyReadyWishlist() async {
        let functions = WishlistParityFunctions(); await functions.failRead()
        let model = DastakCustomerModel(functions: functions)
        await model.refreshWishlist()
        XCTAssertFalse(model.hasLoadedWishlist)
        XCTAssertEqual(model.wishlistRefreshFailure, .offline)
        XCTAssertTrue(model.wishlistItems.isEmpty)
        XCTAssertFalse(model.isLoadingWishlist)
    }
    func testSuccessfulEmptyReadIsDifferentFromFailedRead() async {
        let model = DastakCustomerModel(functions: WishlistParityFunctions())
        await model.refreshWishlist()
        XCTAssertTrue(model.hasLoadedWishlist)
        XCTAssertNil(model.wishlistRefreshFailure)
        XCTAssertTrue(model.unresolvedWishlistItems.isEmpty)
    }
    func testUnresolvedProductsAndDishesRemainIndividuallyAddressable() async throws {
        let functions = WishlistParityFunctions(items: [entry(first), entry(second, kind: "MENU_ITEM")])
        let model = DastakCustomerModel(functions: functions); await model.refreshWishlist()
        XCTAssertEqual(model.unresolvedWishlistItemCount, 2)
        XCTAssertEqual(Set(model.unresolvedWishlistItems.map(\.itemID)), [first, second])
        await model.removeWishlistItem(kind: .menuItem, itemID: second)
        XCTAssertEqual(model.unresolvedWishlistItems.map(\.itemID), [first])
        XCTAssertTrue(model.cart.isEmpty)
        let calls = await functions.mutations
        XCTAssertEqual(calls.first?.kind, "MENU_ITEM"); XCTAssertEqual(calls.first?.item, second); XCTAssertEqual(calls.first?.wished, false)
    }
    func testExplicitRemoveNeverBecomesSaveAfterAnotherRemoval() async {
        let functions = WishlistParityFunctions(items: [entry(first)])
        let model = DastakCustomerModel(functions: functions); await model.refreshWishlist()
        await functions.replaceItems([]); await model.refreshWishlist()
        await model.removeWishlistItem(kind: .retailSKU, itemID: first)
        let calls = await functions.mutations
        XCTAssertEqual(calls.first?.wished, false)
        XCTAssertTrue(model.wishlistItems.isEmpty)
    }
    func testFailedRemovalKeepsSavedEntryAndReleasesBusyState() async {
        let functions = WishlistParityFunctions(items: [entry(first)]); let model = DastakCustomerModel(functions: functions)
        await model.refreshWishlist(); await functions.failMutation()
        await model.removeWishlistItem(kind: .retailSKU, itemID: first)
        XCTAssertEqual(model.wishlistItems.count, 1)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.wishlistUpdatingIDs.isEmpty)
    }
    func testFailedRefreshRetainsSavedEntriesAndRetryClearsFailure() async {
        let functions = WishlistParityFunctions(items: [entry(first)]); let model = DastakCustomerModel(functions: functions)
        await model.refreshWishlist(); await functions.failRead(); await model.refreshWishlist()
        XCTAssertEqual(model.wishlistItems.count, 1); XCTAssertTrue(model.hasLoadedWishlist)
        XCTAssertEqual(model.wishlistRefreshFailure, .offline)
        await model.refreshWishlist(); XCTAssertNil(model.wishlistRefreshFailure)
    }
    func testDuplicateSnapshotCannotClaimLoadedSuccess() async {
        let functions = WishlistParityFunctions(items: [entry(first), entry(first)])
        let model = DastakCustomerModel(functions: functions); await model.refreshWishlist()
        XCTAssertFalse(model.hasLoadedWishlist); XCTAssertNotNil(model.wishlistRefreshFailure)
    }
    func testSameUUIDAcrossDifferentKindsDoesNotCollideInSavedRows() async {
        let functions = WishlistParityFunctions(items: [entry(first), entry(first, kind: "MENU_ITEM")])
        let model = DastakCustomerModel(functions: functions); await model.refreshWishlist()
        XCTAssertTrue(model.hasLoadedWishlist); XCTAssertEqual(model.unresolvedWishlistItems.count, 2)
        XCTAssertEqual(Set(model.unresolvedWishlistItems.map(\.id)).count, 2)
    }
    func testLateSnapshotCannotRestoreAnExplicitlyRemovedEntry() async {
        let functions = WishlistParityFunctions(items: [entry(first)]); let model = DastakCustomerModel(functions: functions)
        await model.refreshWishlist(); await functions.holdRead()
        let reading = Task { await model.refreshWishlist() }; await functions.waitForHold()
        await model.removeWishlistItem(kind: .retailSKU, itemID: first)
        await functions.release(); await reading.value
        XCTAssertTrue(model.wishlistItems.isEmpty); XCTAssertFalse(model.isLoadingWishlist)
    }
    func testOutOfOrderDifferentItemAdditionsPreserveBothAcknowledgements() async {
        let functions = WishlistParityFunctions(); let model = DastakCustomerModel(functions: functions)
        await model.refreshWishlist(); await functions.holdMutation()
        let adding = Task { await model.toggleWishlist(kind: .retailSKU, itemID: first) }; await functions.waitForHold()
        await model.toggleWishlist(kind: .retailSKU, itemID: second)
        await functions.release(); await adding.value
        XCTAssertEqual(Set(model.wishlistItems.map(\.itemID)), [first, second])
        XCTAssertTrue(model.wishlistUpdatingIDs.isEmpty)
    }
    func testLateAdditionSnapshotCannotUndoAnotherItemsRemoval() async {
        let functions = WishlistParityFunctions(items: [entry(second)]); let model = DastakCustomerModel(functions: functions)
        await model.refreshWishlist(); await functions.holdMutation()
        let adding = Task { await model.toggleWishlist(kind: .retailSKU, itemID: first) }; await functions.waitForHold()
        await model.removeWishlistItem(kind: .retailSKU, itemID: second)
        await functions.release(); await adding.value
        XCTAssertEqual(model.wishlistItems.map(\.itemID), [first])
    }
    func testMutationResponseAlsoIncorporatesRemoteSavedEntries() async {
        let functions = WishlistParityFunctions(); let model = DastakCustomerModel(functions: functions)
        await model.refreshWishlist(); await functions.replaceItems([entry(second)])
        await model.toggleWishlist(kind: .retailSKU, itemID: first)
        XCTAssertEqual(Set(model.wishlistItems.map(\.itemID)), [first, second])
    }
    func testWrongMutationReceiptDoesNotPretendItemWasSaved() async {
        let functions = WishlistParityFunctions(); let model = DastakCustomerModel(functions: functions)
        await model.refreshWishlist(); await functions.wrongReceipt()
        await model.toggleWishlist(kind: .retailSKU, itemID: first)
        XCTAssertTrue(model.wishlistItems.isEmpty); XCTAssertNotNil(model.errorMessage)
    }
    func testUnreadWishlistCannotGuessToggleStateAndSendMutation() async {
        let functions = WishlistParityFunctions(); let model = DastakCustomerModel(functions: functions)
        await model.toggleWishlist(kind: .retailSKU, itemID: first)
        let calls = await functions.mutations; XCTAssertTrue(calls.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }
    func testAccountResetDiscardsLateWishlistRead() async {
        let functions = WishlistParityFunctions(items: [entry(first)])
        let model = DastakCustomerModel(functions: functions, accountIDProvider: { throw MarketplaceAuthenticatedServicesError.authenticationRequired })
        await functions.holdRead()
        let reading = Task { await model.refreshWishlist() }; await functions.waitForHold()
        await model.restoreCartStorage()
        await functions.release(); await reading.value
        XCTAssertFalse(model.hasLoadedWishlist); XCTAssertTrue(model.wishlistItems.isEmpty)
        XCTAssertFalse(model.isLoadingWishlist)
    }
}
private actor WishlistParityFunctions: FunctionClient {
    struct Mutation: Sendable { let kind: String; let item: UUID; let wished: Bool }
    var mutations: [Mutation] = []
    private var items: [[String: String]]
    private var readFails = false; private var mutationFails = false; private var wrong = false
    private var nextReadHeld = false; private var nextMutationHeld = false
    private var continuation: CheckedContinuation<Void, Never>?; private var waiter: CheckedContinuation<Void, Never>?
    init(items: [[String: String]] = []) { self.items = items }
    func replaceItems(_ value: [[String: String]]) { items = value }
    func failRead() { readFails = true }; func failMutation() { mutationFails = true }; func wrongReceipt() { wrong = true }
    func holdRead() { nextReadHeld = true }; func holdMutation() { nextMutationHeld = true }
    func waitForHold() async { if continuation == nil { await withCheckedContinuation { waiter = $0 } } }
    func release() { continuation?.resume(); continuation = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        guard name == "customer-wishlist" else { throw FunctionClientError.invalidResponse }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        let read = object["operation"] as? String == "snapshot"
        if read && readFails { readFails = false; throw URLError(.notConnectedToInternet) }
        if !read {
            let kind = object["itemKind"] as! String, id = UUID(uuidString: object["itemId"] as! String)!, wished = object["wished"] as! Bool
            mutations.append(.init(kind: kind, item: id, wished: wished))
            if mutationFails { mutationFails = false; throw URLError(.timedOut) }
            if !wrong {
                items.removeAll { $0["kind"] == kind && $0["itemId"]?.lowercased() == id.uuidString.lowercased() }
                if wished { items.append(entry(id, kind: kind)) }
            }
            wrong = false
        }
        let response = try JSONSerialization.data(withJSONObject: ["items": items])
        if read ? nextReadHeld : nextMutationHeld {
            nextReadHeld = false; nextMutationHeld = false
            await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }
}
private let first = UUID(uuidString: "99000000-0000-4000-8000-000000000001")!
private let second = UUID(uuidString: "99000000-0000-4000-8000-000000000002")!
private func entry(_ id: UUID, kind: String = "RETAIL_SKU") -> [String: String] { ["itemId": id.uuidString, "kind": kind, "createdAt": "2026-10-11T00:00:00Z"] }
