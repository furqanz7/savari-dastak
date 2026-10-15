import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakCartTests: XCTestCase {
    func testBasketPhotosSurviveQuantityChangesAndStorageRoundTrip() throws {
        var baskets = DastakCustomerBaskets()
        let product = try fixtureProduct(productID: UUID().uuidString, imageKey: "canonical/products/milk-500ml.webp")
        let menu = try fixtureRestaurant(branchID: UUID().uuidString, imageKey: "restaurants/menu/coffee.webp")
        let item = try XCTUnwrap(menu.categories.first?.items.first)
        baskets[.grocery].add(product)
        baskets[.grocery].add(product)
        baskets[.food].addFood(restaurant: menu.restaurant, item: item, optionIDs: [])
        let foodID = try XCTUnwrap(baskets[.food].foodEntries.first?.id)
        baskets[.food].incrementFood(foodID)
        let restored = try JSONDecoder().decode(DastakCustomerBaskets.self, from: JSONEncoder().encode(baskets))
        XCTAssertEqual(restored[.grocery].entries.first?.product.imageKey, product.imageKey)
        XCTAssertEqual(restored[.food].foodEntries.first?.item.imageKey, item.imageKey)
        XCTAssertEqual(restored[.grocery].itemCount, 2)
        XCTAssertEqual(restored[.food].itemCount, 2)
    }

    func testCanonicalCartAggregatesQuantityAndAuthoritativeSubtotal() throws {
        var cart = DastakCart()
        let product = try fixtureProduct(
            productID: "11111111-1111-4111-8111-111111111111",
            pricePaise: 12_500
        )

        XCTAssertEqual(cart.add(product), .added)
        XCTAssertEqual(cart.add(product), .added)
        XCTAssertEqual(cart.itemCount, 2)
        XCTAssertEqual(cart.subtotal, Money(paise: 25_000))
        XCTAssertEqual(cart.orderLines, [
            DastakV1OrderLineInput(skuID: product.id, quantity: 2)
        ])
    }

    func testCanonicalCartAllowsMixedSKUsWithoutMerchantStoreIdentity() throws {
        var cart = DastakCart()
        let first = try fixtureProduct(
            productID: "11111111-1111-4111-8111-111111111111"
        )
        let second = try fixtureProduct(
            productID: "33333333-3333-4333-8333-333333333333"
        )

        XCTAssertEqual(cart.add(first), .added)
        XCTAssertEqual(cart.add(second), .added)
        XCTAssertEqual(cart.entries.map(\.product.id), [first.id, second.id])
    }

    func testCanonicalCartCapsOneSKUQuantity() throws {
        var cart = DastakCart()
        let product = try fixtureProduct(
            productID: "11111111-1111-4111-8111-111111111111"
        )

        for _ in 0..<DastakCart.maximumQuantity {
            XCTAssertEqual(cart.add(product), .added)
        }
        XCTAssertEqual(cart.add(product), .quantityLimit)
        XCTAssertEqual(cart.itemCount, DastakCart.maximumQuantity)
    }

    func testMixedFoodAndRetailCartKeepsOneParentSubmissionAndServerIdentities() throws {
        var cart = DastakCart()
        let product = try fixtureProduct(productID: "11111111-1111-4111-8111-111111111111", pricePaise: 10_000)
        let restaurant = try fixtureRestaurant(branchID: "77777777-7777-4777-8777-777777777777")
        let item = try XCTUnwrap(restaurant.categories.first?.items.first)
        let option = try XCTUnwrap(item.optionGroups.first?.options.first)

        XCTAssertEqual(cart.add(product), .added)
        XCTAssertEqual(cart.addFood(restaurant: restaurant.restaurant, item: item, optionIDs: [option.id]), .added)
        XCTAssertEqual(cart.itemCount, 2)
        XCTAssertEqual(cart.subtotal, Money(paise: 15_000))
        XCTAssertEqual(cart.restaurantBranchID, restaurant.restaurant.branchID)
        XCTAssertEqual(cart.orderLines.map(\.lineType), ["RETAIL_SKU", "FOOD_MENU_ITEM"])
    }

    func testFoodCartRejectsASecondRestaurantWithoutMerging() throws {
        var cart = DastakCart()
        let first = try fixtureRestaurant(branchID: "77777777-7777-4777-8777-777777777777")
        let second = try fixtureRestaurant(branchID: "88888888-8888-4888-8888-888888888888")
        let firstItem = try XCTUnwrap(first.categories.first?.items.first)
        let secondItem = try XCTUnwrap(second.categories.first?.items.first)

        XCTAssertEqual(cart.addFood(restaurant: first.restaurant, item: firstItem, optionIDs: []), .added)
        XCTAssertEqual(cart.addFood(restaurant: second.restaurant, item: secondItem, optionIDs: []), .differentRestaurant)
        XCTAssertEqual(cart.foodEntries.count, 1)
        XCTAssertEqual(cart.restaurantBranchID, first.restaurant.branchID)
    }

    @MainActor
    func testModelKeepsIndependentBasketsAndClearsOnlySelectedService() throws {
        let model = DastakCustomerModel(functions: BasketFunctionsStub())
        let product = try fixtureProduct(productID: UUID().uuidString)
        let restaurant = try fixtureRestaurant(branchID: UUID().uuidString)
        let item = try XCTUnwrap(restaurant.categories.first?.items.first)
        model.addToCart(product)
        model.addFoodToCart(restaurant: restaurant, item: item, optionIDs: [])
        XCTAssertEqual(model.cartService, .food)
        XCTAssertTrue(model.cart.entries.isEmpty)
        XCTAssertEqual(model.baskets[.grocery].itemCount, 1)
        model.clearCart()
        XCTAssertTrue(model.baskets[.food].isEmpty)
        XCTAssertEqual(model.baskets[.grocery].itemCount, 1)
        model.cartService = .grocery
        XCTAssertEqual(model.cart.orderLines.map(\.lineType), ["RETAIL_SKU"])
    }

    @MainActor
    func testAccountScopedBasketsSurviveRelaunchWithoutLeakingToAnotherAccount() async throws {
        let suite = "DastakBasketTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountID = UUID()
        let storage = BasketJournalStub()
        let model = DastakCustomerModel(functions: BasketFunctionsStub(), accountIDProvider: { accountID }, basketDefaults: defaults, checkoutJournalStorage: storage, enforcesAreaChecks: false)
        let product = try fixtureProduct(productID: UUID().uuidString)
        model.addToCart(product)
        XCTAssertTrue(model.cart.isEmpty, "Do not edit before the account-scoped restore finishes")
        await model.restoreCartStorage()
        model.addToCart(product)
        let restaurant = try fixtureRestaurant(branchID: UUID().uuidString)
        let item = try XCTUnwrap(restaurant.categories.first?.items.first)
        let option = try XCTUnwrap(item.optionGroups.first?.options.first)
        model.addFoodToCart(restaurant: restaurant, item: item, optionIDs: [option.id])
        let relaunched = DastakCustomerModel(functions: BasketFunctionsStub(), accountIDProvider: { accountID }, basketDefaults: defaults, checkoutJournalStorage: storage)
        await relaunched.restoreCartStorage()
        XCTAssertEqual(relaunched.baskets, model.baskets)
        XCTAssertEqual(relaunched.baskets[.food].foodEntries.first?.optionIDs, [option.id])
        let otherAccount = DastakCustomerModel(functions: BasketFunctionsStub(), accountIDProvider: { UUID() }, basketDefaults: defaults, checkoutJournalStorage: storage)
        await otherAccount.restoreCartStorage()
        XCTAssertTrue(otherAccount.baskets[.grocery].isEmpty)
        XCTAssertTrue(otherAccount.baskets[.food].isEmpty)
        // Repeated bootstrap must not overwrite edits with stale cached state.
        relaunched.cartService = .grocery
        relaunched.clearCart()
        await relaunched.restoreCartStorage()
        XCTAssertTrue(relaunched.cart.isEmpty)
        XCTAssertFalse(relaunched.baskets[.food].isEmpty)
    }

    @MainActor
    func testInvalidIdentityNeverFallsBackToSharedBasketStorage() async throws {
        let model = DastakCustomerModel(functions: BasketFunctionsStub(), accountIDProvider: { throw URLError(.userAuthenticationRequired) })
        await model.restoreCartStorage()
        model.addToCart(try fixtureProduct(productID: UUID().uuidString))
        XCTAssertFalse(model.isCartStorageReady)
        XCTAssertTrue(model.cart.isEmpty)
        XCTAssertNotNil(model.cartErrorMessage)
    }

    @MainActor
    func testCorruptUnsupportedAndInvalidCachedBasketsFailClosed() throws {
        let suite = "DastakBasketTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountID = UUID()
        let key = "dastak.customer.\(accountID.uuidString.lowercased()).baskets.v1"
        let store = DastakBasketStore(defaults: defaults)
        var baskets = DastakCustomerBaskets()
        baskets[.grocery].add(try fixtureProduct(productID: UUID().uuidString))
        store.save(baskets, accountID: accountID)
        let valid = try XCTUnwrap(defaults.data(forKey: key))
        for change in ["version", "accountID", "quantity", "sellingPricePaise"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            if change == "version" { object[change] = 999 }
            else if change == "accountID" { object[change] = UUID().uuidString }
            else {
                var savedBaskets = object["baskets"] as! [String: Any]
                var grocery = savedBaskets["grocery"] as! [String: Any]
                var entries = grocery["entries"] as! [[String: Any]]
                if change == "quantity" { entries[0][change] = 100 }
                else {
                    var product = entries[0]["product"] as! [String: Any]
                    product[change] = -1
                    entries[0]["product"] = product
                }
                grocery["entries"] = entries
                savedBaskets["grocery"] = grocery
                object["baskets"] = savedBaskets
            }
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
            XCTAssertTrue(store.load(accountID: accountID)[.grocery].isEmpty, change)
        }
        defaults.set(Data("not JSON".utf8), forKey: key)
        XCTAssertTrue(store.load(accountID: accountID)[.grocery].isEmpty)
    }

    @MainActor
    func testSubmissionLocksItsSnapshotAndPreservesOtherServiceEdits() async throws {
        let functions = BasketFunctionsStub()
        let model = DastakCustomerModel(functions: functions, checkoutCustomerProvider: {
            MarketplaceCheckoutCustomer(displayName: "Test", email: nil, phoneNumber: "+919999999999")
        })
        await model.bootstrap()
        XCTAssertTrue(model.hasCompleteDeliveryAddress)
        let product = try fixtureProduct(productID: UUID().uuidString)
        let restaurant = try fixtureRestaurant(branchID: UUID().uuidString)
        let item = try XCTUnwrap(restaurant.categories.first?.items.first)
        model.addToCart(product)
        let submission = Task { await model.submitV1Order() }
        await functions.waitForSubmission()
        XCTAssertFalse(model.canEditCurrentCart)
        model.addToCart(product)
        model.decrementCartItem(product.id)
        model.clearCart()
        XCTAssertEqual(model.baskets[.grocery].itemCount, 1, "Model must enforce the lock, not just buttons")
        model.addFoodToCart(restaurant: restaurant, item: item, optionIDs: [])
        XCTAssertTrue(model.canEditCurrentCart)
        XCTAssertEqual(model.cartService, .food)
        await functions.finishSubmission()
        let success = await submission.value
        XCTAssertTrue(success)
        XCTAssertTrue(model.baskets[.grocery].isEmpty)
        XCTAssertEqual(model.baskets[.food].itemCount, 1)
        let lines = await functions.submittedLineTypes
        XCTAssertEqual(lines, ["RETAIL_SKU"])
    }

    @MainActor
    func testFailedSubmissionPreservesCartAndRetryKeyDespiteOtherServiceEdits() async throws {
        let functions = BasketFunctionsStub()
        let model = DastakCustomerModel(functions: functions, checkoutCustomerProvider: {
            MarketplaceCheckoutCustomer(displayName: "Test", email: nil, phoneNumber: "+919999999999")
        })
        await model.bootstrap()
        model.addToCart(try fixtureProduct(productID: UUID().uuidString))
        let first = Task { await model.submitV1Order() }
        await functions.waitForSubmission()
        await functions.finishSubmission(fail: true)
        let failed = await first.value
        XCTAssertFalse(failed)
        XCTAssertEqual(model.cart.itemCount, 1)
        let restaurant = try fixtureRestaurant(branchID: UUID().uuidString)
        model.addFoodToCart(restaurant: restaurant, item: try XCTUnwrap(restaurant.categories.first?.items.first), optionIDs: [])
        model.cartService = .grocery
        let retry = Task { await model.submitV1Order() }
        await functions.waitForSubmission()
        await functions.finishSubmission()
        let success = await retry.value
        XCTAssertTrue(success)
        let keys = await functions.submissionKeys
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.first, keys.last)
        XCTAssertEqual(model.baskets[.food].itemCount, 1)
    }

    @MainActor
    func testLostSubmitResponseRecoversExactPayloadAndKeyAfterRelaunch() async throws {
        let account = UUID()
        let storage = BasketJournalStub()
        let functions = BasketFunctionsStub()
        let first = recoveryModel(account: account, storage: storage, functions: functions)
        await first.bootstrap()
        let product = try fixtureProduct(productID: UUID().uuidString)
        first.addToCart(product)
        let sending = Task { await first.submitV1Order() }
        await functions.waitForSubmission()
        await functions.finishSubmission(fail: true)
        let lost = await sending.value
        XCTAssertFalse(lost)
        first.clearCart()
        first.addToCart(product)
        XCTAssertEqual(first.cart.itemCount, 1)
        XCTAssertFalse(first.canEditCurrentCart)

        let reopened = recoveryModel(account: account, storage: storage, functions: functions)
        await reopened.restoreCartStorage() // No current recipient/address is loaded.
        XCTAssertFalse(reopened.hasCompleteDeliveryAddress)
        XCTAssertNotNil(reopened.pendingCheckout)
        let recovering = Task { await reopened.submitV1Order() }
        await functions.waitForSubmission()
        await functions.finishSubmission()
        let recovered = await recovering.value
        XCTAssertTrue(recovered)
        let keys = await functions.submissionKeys
        let payloads = await functions.submittedPayloads
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.first, keys.last)
        XCTAssertEqual(payloads.first, payloads.last)
        let afterAcknowledgement = recoveryModel(account: account, storage: storage, functions: functions)
        await afterAcknowledgement.restoreCartStorage()
        XCTAssertTrue(afterAcknowledgement.cart.isEmpty)
        XCTAssertNil(afterAcknowledgement.pendingCheckout)
    }

    @MainActor
    func testKnownOrderRecoveryOnlyReadsLatestTerminalStateWithoutResubmitting() async throws {
        let account = UUID()
        let storage = BasketJournalStub()
        let functions = BasketFunctionsStub()
        let first = recoveryModel(account: account, storage: storage, functions: functions)
        await first.bootstrap()
        first.addToCart(try fixtureProduct(productID: UUID().uuidString))
        await functions.setReadFailure(true)
        let sending = Task { await first.submitV1Order() }
        await functions.waitForSubmission()
        await functions.finishSubmission()
        let failedRead = await sending.value
        XCTAssertFalse(failedRead)
        XCTAssertNotNil(first.pendingCheckout?.orderID)
        let reopened = recoveryModel(account: account, storage: storage, functions: functions)
        await reopened.restoreCartStorage()
        await functions.setReadFailure(false, status: "CANCELLED")
        let recovered = await reopened.submitV1Order()
        XCTAssertTrue(recovered)
        XCTAssertEqual(reopened.activeV1Order?.status, .cancelled)
        let keys = await functions.submissionKeys
        XCTAssertEqual(keys.count, 1, "Known order IDs are read, never submitted again")
    }

    @MainActor
    func testStorageFailureBeforeSendMakesNoOrderRequest() async throws {
        let account = UUID()
        let storage = BasketJournalStub()
        let functions = BasketFunctionsStub()
        let model = recoveryModel(account: account, storage: storage, functions: functions)
        await model.bootstrap()
        model.addToCart(try fixtureProduct(productID: UUID().uuidString))
        storage.failWrites = true
        let success = await model.submitV1Order()
        XCTAssertFalse(success)
        XCTAssertFalse(model.isCartStorageReady)
        XCTAssertNotNil(model.checkoutRecoveryIssue)
        XCTAssertEqual(model.cart.itemCount, 1)
        let keys = await functions.submissionKeys
        XCTAssertTrue(keys.isEmpty)
    }

    @MainActor
    func testAcknowledgementWriteFailureRetainsRecoveryAndConsumesCartOnceAfterRestart() async throws {
        let account = UUID()
        let storage = BasketJournalStub()
        let functions = BasketFunctionsStub()
        let model = recoveryModel(account: account, storage: storage, functions: functions)
        await model.bootstrap() // write 1: migrate
        model.addToCart(try fixtureProduct(productID: UUID().uuidString)) // write 2
        storage.failOnWrite = 5 // prepare 3, order ID 4, atomic acknowledgement 5
        let sending = Task { await model.submitV1Order() }
        await functions.waitForSubmission()
        await functions.finishSubmission()
        let saved = await sending.value
        XCTAssertFalse(saved)
        XCTAssertEqual(model.cart.itemCount, 1)
        XCTAssertNotNil(model.checkoutRecoveryIssue)
        let reopened = recoveryModel(account: account, storage: storage, functions: functions)
        await reopened.restoreCartStorage()
        XCTAssertNotNil(reopened.pendingCheckout?.orderID)
        let success = await reopened.submitV1Order()
        XCTAssertTrue(success)
        let keys = await functions.submissionKeys
        XCTAssertEqual(keys.count, 1)
        let again = recoveryModel(account: account, storage: storage, functions: functions)
        await again.restoreCartStorage()
        XCTAssertTrue(again.cart.isEmpty)
        XCTAssertNil(again.pendingCheckout)
    }

    @MainActor
    func testCorruptJournalBlocksCheckoutAndStaleModelCannotOverwritePendingAttempt() async throws {
        let account = UUID()
        let storage = BasketJournalStub()
        let functions = BasketFunctionsStub()
        let first = recoveryModel(account: account, storage: storage, functions: functions)
        await first.bootstrap()
        first.addToCart(try fixtureProduct(productID: UUID().uuidString))
        let stale = recoveryModel(account: account, storage: storage, functions: functions)
        await stale.restoreCartStorage()
        let sending = Task { await first.submitV1Order() }
        await functions.waitForSubmission()
        stale.clearCart()
        XCTAssertFalse(stale.isCartStorageReady)
        XCTAssertNotNil(stale.checkoutRecoveryIssue)
        await functions.finishSubmission(fail: true)
        _ = await sending.value
        XCTAssertEqual(try storage.load(accountID: account)?.pending.count, 1)
        storage.corrupt = true
        let reopened = recoveryModel(account: account, storage: storage, functions: functions)
        await reopened.restoreCartStorage()
        XCTAssertFalse(reopened.isCartStorageReady)
        let success = await reopened.submitV1Order()
        XCTAssertFalse(success)
        let keys = await functions.submissionKeys
        XCTAssertEqual(keys.count, 1)
    }

    @MainActor
    func testProtectedFileJournalRoundTripRejectsCorruptionAndStaleRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dastak-journal-test-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = DastakFileCheckoutJournalStorage(directory: directory)
        let account = UUID()
        var baskets = DastakCustomerBaskets()
        baskets[.grocery].add(try fixtureProduct(productID: UUID().uuidString))
        let record = DastakCheckoutJournal(accountID: account, baskets: baskets, pending: [])
        try storage.save(record, replacing: nil)
        XCTAssertEqual(try storage.load(accountID: account), record)
        XCTAssertNil(try storage.load(accountID: UUID()))
        XCTAssertThrowsError(try storage.save(record, replacing: nil))
        let url = directory.appendingPathComponent(account.uuidString.lowercased() + ".json")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try storage.load(accountID: account))
    }

    @MainActor
    private func recoveryModel(account: UUID, storage: BasketJournalStub, functions: BasketFunctionsStub) -> DastakCustomerModel {
        DastakCustomerModel(functions: functions, checkoutCustomerProvider: {
            MarketplaceCheckoutCustomer(displayName: "Original recipient", email: nil, phoneNumber: "+919999999999")
        }, accountIDProvider: { account }, checkoutJournalStorage: storage, enforcesAreaChecks: false)
    }

    private func fixtureProduct(
        productID: String,
        pricePaise: Int = 10_000,
        imageKey: String? = nil
    ) throws -> DastakV1CatalogueSKU {
        let imageJSON = try XCTUnwrap(String(data: JSONEncoder().encode(imageKey), encoding: .utf8))
        let json = """
        {
          "id":"\(productID)",
          "categoryId":"55555555-5555-4555-8555-555555555555",
          "subcategoryId":"66666666-6666-4666-8666-666666666666",
          "brand":null,
          "name":"Market item",
          "slug":"market-item-\(productID.prefix(4))",
          "variant":null,
          "packSize":"1 unit",
          "description":"Freshly stocked",
          "imageKey":\(imageJSON),
          "barcode":null,
          "listPricePaise":\(pricePaise),
          "sellingPricePaise":\(pricePaise),
          "currencyCode":"INR",
          "logisticsAttributes":{}
        }
        """
        return try JSONDecoder().decode(DastakV1CatalogueSKU.self, from: Data(json.utf8))
    }

    private func fixtureRestaurant(branchID: String, imageKey: String? = nil) throws -> DastakV1RestaurantMenu {
        let imageJSON = try XCTUnwrap(String(data: JSONEncoder().encode(imageKey), encoding: .utf8))
        let json = """
        {
          "restaurant":{
            "organizationId":"99999999-9999-4999-8999-999999999999",
            "branchId":"\(branchID)","name":"Dastak Cafe","branchName":"Main Road",
            "imageKey":null,"description":null,"serviceZoneId":null,
            "acceptingOrders":true,"isOpen":true,"branchStatus":"ACTIVE",
            "merchantType":"RESTAURANT_CAFE","softActiveOrderThreshold":5,"activeOrderCount":0
          },
          "categories":[{
            "id":"55555555-5555-4555-8555-555555555555","name":"Drinks",
            "description":null,"sortOrder":1,"status":"ACTIVE","version":1,
            "items":[{
              "id":"66666666-6666-4666-8666-666666666666","name":"Coffee",
              "description":null,"imageKey":\(imageJSON),"basePricePaise":4500,
              "currencyCode":"INR","taxRateBps":0,"logisticsAttributes":{},
              "status":"ACTIVE","version":1,"optionGroups":[{
                "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Size",
                "selectionType":"SINGLE","minimumSelections":0,"maximumSelections":1,
                "sortOrder":1,"status":"ACTIVE","version":1,"options":[{
                  "id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","name":"Large",
                  "priceDeltaPaise":500,"sortOrder":1,"status":"ACTIVE","version":1
                }]
              }]
            }]
          }]
        }
        """
        return try JSONDecoder().decode(DastakV1RestaurantMenu.self, from: Data(json.utf8))
    }
}

private actor BasketFunctionsStub: FunctionClient {
    private var release: CheckedContinuation<Void, any Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var submissionKeys: [IdempotencyKey] = []
    private(set) var submittedLineTypes: [String] = []
    private(set) var submittedPayloads: [Data] = []
    private var failReads = false
    private var readStatus = "MATCHING"

    func setReadFailure(_ value: Bool, status: String = "MATCHING") {
        failReads = value
        readStatus = status
    }

    func waitForSubmission() async {
        if release != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finishSubmission(fail: Bool = false) {
        if fail { release?.resume(throwing: URLError(.timedOut)) }
        else { release?.resume() }
        release = nil
    }

    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Input, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        if name == "customer-addresses" {
            return try JSONDecoder().decode(Result.self, from: Data("""
            {"addresses":[{"addressId":"00000000-0000-4000-8000-000000000001","label":"Home",
            "address":"Test Road","building":"1","details":"1","displayAddress":"1 Test Road",
            "location":{"latitude":12.68,"longitude":78.62},"isDefault":true,"updatedAt":"2026-10-10T00:00:00Z"}]}
            """.utf8))
        }
        if name == "dastak-v1-orders", body?["operation"] as? String == "get" {
            if failReads { throw URLError(.notConnectedToInternet) }
            return try JSONDecoder().decode(Result.self, from: Data(Self.orderJSON.replacingOccurrences(of: "MATCHING", with: readStatus).utf8))
        }
        guard name == "dastak-v1-orders", body?["operation"] as? String == "submit" else {
            throw URLError(.notConnectedToInternet)
        }
        submissionKeys.append(idempotencyKey)
        let order = body?["order"] as? [String: Any]
        submittedPayloads.append(try JSONSerialization.data(withJSONObject: order ?? [:], options: .sortedKeys))
        submittedLineTypes = (order?["lines"] as? [[String: Any]] ?? []).compactMap { $0["lineType"] as? String }
        try await withCheckedThrowingContinuation {
            release = $0
            started?.resume()
            started = nil
        }
        return try JSONDecoder().decode(Result.self, from: Data(Self.orderJSON.utf8))
    }

    private static let orderJSON = """
        {"id":"00000000-0000-4000-8000-000000000002","displayOrderNumber":"TEST-1",
        "orderType":"RETAIL_ONLY","status":"MATCHING","version":1,
        "price":{"snapshotKind":"ESTIMATED","subtotalPaise":10000,"deliveryFeePaise":1500,
        "platformFeePaise":230,"discountPaise":0,"taxPaise":0,"totalPaise":11730,"currencyCode":"INR"},
        "lines":[],"createdAt":"2026-10-10T00:00:00Z","updatedAt":"2026-10-10T00:00:00Z"}
        """
}

@MainActor
private final class BasketJournalStub: DastakCheckoutJournalStorage {
    var failWrites = false
    var failOnWrite: Int?
    var corrupt = false
    private var writes = 0
    private var records: [UUID: Data] = [:]

    func load(accountID: UUID) throws -> DastakCheckoutJournal? {
        if corrupt { throw DastakCheckoutStorageError.invalidJournal }
        guard let data = records[accountID] else { return nil }
        let record = try JSONDecoder().decode(DastakCheckoutJournal.self, from: data)
        guard record.accountID == accountID, record.isValid else { throw DastakCheckoutStorageError.invalidJournal }
        return record
    }

    func save(_ journal: DastakCheckoutJournal, replacing revision: UUID?) throws {
        writes += 1
        if failWrites || writes == failOnWrite { throw DastakCheckoutStorageError.unavailable }
        guard try load(accountID: journal.accountID)?.revision == revision else {
            throw DastakCheckoutStorageError.changedJournal
        }
        guard journal.isValid else { throw DastakCheckoutStorageError.invalidJournal }
        records[journal.accountID] = try JSONEncoder().encode(journal)
    }
}
