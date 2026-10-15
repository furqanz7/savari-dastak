import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakCustomerReorderParityTests: XCTestCase {
    func testReviewsTargetBasketNotCurrentlySelectedBasketAndRequiresConsent() async throws {
        let model = DastakCustomerModel(functions: ReorderFunctions())
        model.addToCart(try ReorderFixtures.product())
        model.cartService = .food
        let order = try ReorderFixtures.order()
        let review = try XCTUnwrap(model.reviewReorder(order))
        XCTAssertEqual(review.service, .grocery)
        XCTAssertTrue(review.requiresReplacement)
        let unreviewed = await model.reorderWithCurrentCatalogue(order)
        XCTAssertFalse(unreviewed.openedBasket)
        XCTAssertEqual(model.baskets[.grocery].itemCount, 1)
        let result = await model.reorderWithCurrentCatalogue(review)
        XCTAssertTrue(result.openedBasket)
        XCTAssertEqual(model.cartService, .grocery)
        XCTAssertEqual(model.cart.itemCount, 2)
    }

    func testMixedHistoryRequiresChoiceAndReplacesOnlyChosenService() async throws {
        let model = DastakCustomerModel(functions: ReorderFunctions())
        model.addToCart(try ReorderFixtures.product())
        let other = model.baskets[.grocery]
        let order = try ReorderFixtures.order(mixed: true)
        XCTAssertEqual(DastakReorderReview.services(for: order), [.grocery, .food])
        XCTAssertNil(model.reviewReorder(order))
        let review = try XCTUnwrap(model.reviewReorder(order, service: .food))
        XCTAssertFalse(review.requiresReplacement)
        let result = await model.reorderWithCurrentCatalogue(review)
        XCTAssertTrue(result.openedBasket)
        XCTAssertEqual(model.baskets[.grocery], other)
        XCTAssertEqual(model.baskets[.food].itemCount, 2)
    }

    func testGroceryReplacementPreservesFoodIncludingOptions() async throws {
        let model = DastakCustomerModel(functions: ReorderFunctions())
        let menu = try ReorderFixtures.menu()
        model.addFoodToCart(restaurant: menu, item: menu.categories[0].items[0], optionIDs: [ReorderFixtures.option])
        let other = model.baskets[.food]
        let review = try XCTUnwrap(model.reviewReorder(try ReorderFixtures.order()))
        let result = await model.reorderWithCurrentCatalogue(review)
        XCTAssertTrue(result.openedBasket)
        XCTAssertEqual(model.baskets[.food], other)
    }

    func testConsentExpiresEvenWhenBasketIsEditedThenRestored() async throws {
        let model = DastakCustomerModel(functions: ReorderFunctions())
        let review = try XCTUnwrap(model.reviewReorder(try ReorderFixtures.order()))
        model.addToCart(try ReorderFixtures.product())
        model.decrementCartItem(ReorderFixtures.sku)
        XCTAssertEqual(model.baskets, review.baskets)
        let result = await model.reorderWithCurrentCatalogue(review)
        XCTAssertFalse(result.openedBasket)
        XCTAssertTrue(model.cart.isEmpty)
    }

    func testOtherBasketEditDuringReadAbortsWithoutLosingEitherBasket() async throws {
        let functions = ReorderFunctions()
        let heldModel = DastakCustomerModel(functions: functions)
        let review = try XCTUnwrap(heldModel.reviewReorder(try ReorderFixtures.order()))
        await functions.hold()
        let work = Task { await heldModel.reorderWithCurrentCatalogue(review) }
        await functions.waitUntilHeld()
        let menu = try ReorderFixtures.menu()
        heldModel.addFoodToCart(restaurant: menu, item: menu.categories[0].items[0], optionIDs: [ReorderFixtures.option])
        let changed = heldModel.baskets
        await functions.release()
        let result = await work.value
        XCTAssertFalse(result.openedBasket)
        XCTAssertEqual(heldModel.baskets, changed)
        XCTAssertFalse(heldModel.isReordering)
    }

    func testDiscontinuedCachedSKUDoesNotReplaceBasket() async throws {
        let functions = ReorderFunctions()
        let customer = DastakCustomerModel(functions: functions)
        customer.addToCart(try ReorderFixtures.product())
        let review = try XCTUnwrap(customer.reviewReorder(try ReorderFixtures.order()))
        await functions.configure(missing: true)
        let result = await customer.reorderWithCurrentCatalogue(review)
        XCTAssertFalse(result.openedBasket)
        XCTAssertEqual(customer.baskets, review.baskets)
    }

    func testInvalidOrAggregatedExcessiveQuantitiesAreNotCoerced() async throws {
        for quantity in [0, -1, 100] {
            let model = DastakCustomerModel(functions: ReorderFunctions())
            let result = await model.reorderWithCurrentCatalogue(try ReorderFixtures.order(quantity: quantity))
            XCTAssertFalse(result.openedBasket)
            XCTAssertTrue(model.cart.isEmpty)
        }
        let model = DastakCustomerModel(functions: ReorderFunctions())
        let result = await model.reorderWithCurrentCatalogue(try ReorderFixtures.order(quantity: 60, duplicate: true))
        XCTAssertFalse(result.openedBasket)
        XCTAssertTrue(model.cart.isEmpty)
    }

    func testFreshPricesReplaceHistoricalAndCachedPrices() async throws {
        let functions = ReorderFunctions()
        let customer = DastakCustomerModel(functions: functions)
        customer.addToCart(try ReorderFixtures.product())
        let review = try XCTUnwrap(customer.reviewReorder(try ReorderFixtures.order()))
        await functions.configure(price: 6300)
        let result = await customer.reorderWithCurrentCatalogue(review)
        XCTAssertTrue(result.openedBasket)
        XCTAssertEqual(customer.cart.entries.first?.product.sellingPricePaise, 6300)
        XCTAssertEqual(customer.cart.itemCount, 2)
    }

    func testExactDishOptionsIncludingRequiredInactiveUnknownAndDuplicateAreChecked() throws {
        let item = try ReorderFixtures.menu().categories[0].items[0]
        XCTAssertTrue(DastakCustomerModel.validReorderOptions(item: item, ids: [ReorderFixtures.option]))
        for ids in [[], [UUID()], [ReorderFixtures.option, ReorderFixtures.option]] {
            XCTAssertFalse(DastakCustomerModel.validReorderOptions(item: item, ids: ids))
        }
        let inactive = try ReorderFixtures.menu(optionActive: false).categories[0].items[0]
        XCTAssertFalse(DastakCustomerModel.validReorderOptions(item: inactive, ids: [ReorderFixtures.option]))
    }

    func testClosedRestaurantOrChangedOptionsLeavesFoodBasketUntouched() async throws {
        for closed in [true, false] {
            let functions = ReorderFunctions()
            let model = DastakCustomerModel(functions: functions)
            let menu = try ReorderFixtures.menu()
            model.addFoodToCart(restaurant: menu, item: menu.categories[0].items[0], optionIDs: [ReorderFixtures.option])
            let review = try XCTUnwrap(model.reviewReorder(try ReorderFixtures.order(food: true)))
            await functions.configure(closed: closed, optionActive: closed)
            let result = await model.reorderWithCurrentCatalogue(review)
            XCTAssertFalse(result.openedBasket)
            XCTAssertEqual(model.baskets, review.baskets)
        }
    }

    func testOfflineFailureKeepsBasketAndExplicitRetryCanSucceed() async throws {
        let functions = ReorderFunctions()
        let customer = DastakCustomerModel(functions: functions)
        customer.addToCart(try ReorderFixtures.product())
        let review = try XCTUnwrap(customer.reviewReorder(try ReorderFixtures.order()))
        await functions.configure(offline: true)
        let first = await customer.reorderWithCurrentCatalogue(review)
        XCTAssertFalse(first.openedBasket)
        XCTAssertEqual(customer.baskets, review.baskets)
        XCTAssertFalse(customer.isReordering)
        await functions.configure(offline: false)
        let retry = await customer.reorderWithCurrentCatalogue(review)
        XCTAssertTrue(retry.openedBasket)
    }

    func testCurrentLocalQuantityCheckedButRiderAbsenceDoesNotBlockBasket() async throws {
        let functions = ReorderFunctions()
        let model = try await localModel(functions)
        let order = try ReorderFixtures.order()
        await functions.configure(stock: 1)
        let insufficient = await model.reorderWithCurrentCatalogue(order)
        XCTAssertFalse(insufficient.openedBasket)
        await functions.configure(stock: 2, delivery: false)
        let available = await model.reorderWithCurrentCatalogue(order)
        XCTAssertTrue(available.openedBasket)
        XCTAssertEqual(model.cart.itemCount, 2)
        XCTAssertEqual(model.currentAreaAvailability?.deliveryAvailable, false)
        let writes = await functions.writes
        XCTAssertEqual(writes, 0)
    }

    func testUnserviceableStaleOrFailedAreaKeepsBasket() async throws {
        for mode in [0, 1, 2] {
            let functions = ReorderFunctions()
            let customer = try await localModel(functions)
            customer.addToCart(try ReorderFixtures.product())
            let review = try XCTUnwrap(customer.reviewReorder(try ReorderFixtures.order()))
            await functions.configure(serviceable: mode != 0, age: mode == 1 ? 60 : 0, offline: mode == 2)
            let result = await customer.reorderWithCurrentCatalogue(review)
            XCTAssertFalse(result.openedBasket)
            XCTAssertEqual(customer.baskets, review.baskets)
        }
    }

    func testAreaClosedOverridesOpenMenu() async throws {
        let functions = ReorderFunctions()
        let customer = try await localModel(functions)
        await functions.configure(areaOpen: false)
        let result = await customer.reorderWithCurrentCatalogue(try ReorderFixtures.order(food: true))
        XCTAssertFalse(result.openedBasket)
        XCTAssertTrue(customer.cart.isEmpty)
    }

    func testSelectedServiceRecoveryBlocksOnlyThatService() async throws {
        let functions = ReorderFunctions(), storage = ReorderStorage(), account = UUID()
        var baskets = DastakCustomerBaskets()
        baskets[.grocery].add(try ReorderFixtures.product())
        let submission = DastakV1OrderSubmission(
            deliveryAddress: .init(label: "Home", line1: "Test Road", line2: nil, landmark: nil, city: nil,
                                   state: nil, postalCode: nil, latitude: 12, longitude: 78, instructions: nil),
            recipient: .init(name: "Test", phoneNumber: "+919999999999"), lines: baskets[.grocery].orderLines)
        let pending = DastakPendingCheckout(service: .grocery, key: IdempotencyKey(rawValue: UUID().uuidString)!, submission: submission)
        storage.value = .init(accountID: account, baskets: baskets, pending: [pending])
        let model = DastakCustomerModel(functions: functions, accountIDProvider: { account }, checkoutJournalStorage: storage, enforcesAreaChecks: false)
        await model.restoreCartStorage()
        XCTAssertNil(model.reviewReorder(try ReorderFixtures.order()))
        let foodReview = try XCTUnwrap(model.reviewReorder(try ReorderFixtures.order(food: true)))
        let result = await model.reorderWithCurrentCatalogue(foodReview)
        XCTAssertTrue(result.openedBasket)
        XCTAssertEqual(model.baskets[.grocery], baskets[.grocery])
        XCTAssertEqual(model.pendingCheckouts[.grocery], pending)
    }

    func testFailedBasketPersistenceDoesNotReportSuccess() async throws {
        let storage = ReorderStorage(), account = UUID()
        let model = DastakCustomerModel(functions: ReorderFunctions(), accountIDProvider: { account }, checkoutJournalStorage: storage, enforcesAreaChecks: false)
        await model.restoreCartStorage()
        let review = try XCTUnwrap(model.reviewReorder(try ReorderFixtures.order()))
        storage.failSave = true
        let result = await model.reorderWithCurrentCatalogue(review)
        XCTAssertFalse(result.openedBasket)
        XCTAssertEqual(model.baskets, review.baskets)
        XCTAssertFalse(model.isCartStorageReady)
    }

    func testAccountChangeOrCancellationDuringReadCannotCommit() async throws {
        for cancel in [false, true] {
            let functions = ReorderFunctions(), identity = ReorderIdentity(), storage = ReorderStorage()
            let model = DastakCustomerModel(functions: functions, accountIDProvider: { await identity.id }, checkoutJournalStorage: storage, enforcesAreaChecks: false)
            await model.restoreCartStorage()
            let review = try XCTUnwrap(model.reviewReorder(try ReorderFixtures.order()))
            await functions.hold()
            let work = Task { await model.reorderWithCurrentCatalogue(review) }
            await functions.waitUntilHeld()
            if cancel { work.cancel() } else { await identity.change() }
            await functions.release()
            let result = await work.value
            XCTAssertFalse(result.openedBasket)
            XCTAssertEqual(model.baskets, review.baskets)
        }
    }

    func testServiceSwitchAndBackInvalidatesReview() async throws {
        let model = DastakCustomerModel(functions: ReorderFunctions())
        let review = try XCTUnwrap(model.reviewReorder(try ReorderFixtures.order()))
        model.cartService = .food
        model.cartService = .grocery
        let result = await model.reorderWithCurrentCatalogue(review)
        XCTAssertFalse(result.openedBasket)
        XCTAssertEqual(model.baskets, review.baskets)
    }

    func testReloadedJournalInvalidatesOldReviewEvenIfContentsAreEqual() async throws {
        let account = UUID(), storage = ReorderStorage()
        let model = DastakCustomerModel(functions: ReorderFunctions(), accountIDProvider: { account }, checkoutJournalStorage: storage, enforcesAreaChecks: false)
        await model.restoreCartStorage()
        let review = try XCTUnwrap(model.reviewReorder(try ReorderFixtures.order()))
        await model.restoreCartStorage(force: true)
        let result = await model.reorderWithCurrentCatalogue(review)
        XCTAssertFalse(result.openedBasket)
        XCTAssertEqual(model.baskets, review.baskets)
    }

    func testUnresolvedConfirmationForSourceOrderBlocksReorder() async throws {
        let account = UUID(), storage = ReorderStorage(), order = try ReorderFixtures.order()
        storage.value = .init(accountID: account, baskets: .init(), pending: [],
                              confirmations: [.init(orderID: order.id, expectedVersion: 1, key: IdempotencyKey(rawValue: UUID().uuidString)!)])
        let model = DastakCustomerModel(functions: ReorderFunctions(), accountIDProvider: { account }, checkoutJournalStorage: storage, enforcesAreaChecks: false)
        await model.restoreCartStorage()
        XCTAssertNil(model.reviewReorder(order))
        XCTAssertEqual(model.pendingConfirmations.count, 1)
        XCTAssertTrue(model.cart.isEmpty)
    }

    func testUnsupportedAmbiguousAndEmptyHistoryCannotReplaceBasket() throws {
        let source = try ReorderFixtures.order()
        let data = try JSONEncoder().encode(source)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for mode in [0, 1, 2] {
            var lines = try XCTUnwrap(json["lines"] as? [[String: Any]])
            if lines.isEmpty { lines = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])["lines"] as! [[String: Any]] }
            if mode == 0 { lines[0]["lineType"] = "UNSUPPORTED" }
            if mode == 1 { lines[0]["lineType"] = "RETAIL_SKU"; lines[0]["menuItemId"] = ReorderFixtures.item.uuidString }
            json["lines"] = mode == 2 ? [] : lines
            let order: DastakV1OrderSnapshot = try ReorderFixtures.decode(json)
            XCTAssertTrue(DastakReorderReview.services(for: order).isEmpty)
            let model = DastakCustomerModel(functions: ReorderFunctions())
            model.addToCart(try ReorderFixtures.product())
            let before = model.baskets
            XCTAssertNil(model.reviewReorder(order))
            XCTAssertEqual(model.baskets, before)
        }
    }

    private func localModel(_ functions: ReorderFunctions) async throws -> DastakCustomerModel {
        let account = UUID()
        let model = DastakCustomerModel(functions: functions, accountIDProvider: { account }, checkoutJournalStorage: ReorderStorage())
        await model.bootstrap()
        XCTAssertNotNil(model.currentAreaAvailability)
        return model
    }
}

@MainActor
private final class ReorderStorage: DastakCheckoutJournalStorage {
    var value: DastakCheckoutJournal?
    var failSave = false
    func load(accountID: UUID) throws -> DastakCheckoutJournal? { value }
    func save(_ journal: DastakCheckoutJournal, replacing revision: UUID?) throws {
        if failSave { throw DastakCheckoutStorageError.unavailable }
        guard value?.revision == revision else { throw DastakCheckoutStorageError.changedJournal }
        value = journal
    }
}
private actor ReorderIdentity { var id = UUID(); func change() { id = UUID() } }

private enum ReorderFixtures {
    static let sku = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let branch = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    static let item = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    static let option = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
    static func decode<T: Decodable>(_ value: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
    static func productJSON(price: Int = 4500) -> [String: Any] {
        ["id": sku.uuidString, "categoryId": UUID().uuidString, "subcategoryId": UUID().uuidString,
         "name": "Test Milk", "slug": "test-milk", "packSize": "1 L", "listPricePaise": max(5000, price),
         "sellingPricePaise": price, "currencyCode": "INR", "logisticsAttributes": [:]]
    }
    static func product() throws -> DastakV1CatalogueSKU { try decode(productJSON()) }
    static func menuJSON(closed: Bool = false, optionActive: Bool = true) -> [String: Any] {
        ["restaurant": ["organizationId": UUID().uuidString, "branchId": branch.uuidString, "name": "Test Cafe", "branchName": "Main",
                        "acceptingOrders": !closed, "isOpen": !closed, "branchStatus": "ACTIVE", "merchantType": "RESTAURANT_CAFE", "softActiveOrderThreshold": 5, "activeOrderCount": 0],
         "categories": [["id": UUID().uuidString, "name": "Meals", "sortOrder": 0, "status": "ACTIVE", "version": 1,
                         "items": [["id": item.uuidString, "name": "Meal", "basePricePaise": 3000, "currencyCode": "INR", "taxRateBps": 0, "logisticsAttributes": [:], "status": "ACTIVE", "version": 1,
                                    "optionGroups": [["id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "Size", "selectionType": "SINGLE", "minimumSelections": 1, "maximumSelections": 1, "sortOrder": 0, "status": "ACTIVE", "version": 1,
                                                      "options": [["id": option.uuidString, "name": "Regular", "priceDeltaPaise": 500, "sortOrder": 0, "status": optionActive ? "ACTIVE" : "INACTIVE", "version": 1]]]]]]]]]
    }
    static func menu(optionActive: Bool = true) throws -> DastakV1RestaurantMenu { try decode(menuJSON(optionActive: optionActive)) }
    static func order(food: Bool = false, mixed: Bool = false, quantity: Int = 2, duplicate: Bool = false) throws -> DastakV1OrderSnapshot {
        let retail: [String: Any] = ["id": UUID().uuidString, "lineType": "RETAIL_SKU", "skuId": sku.uuidString, "name": "Test Milk", "packSize": "1 L", "quantity": quantity, "unitPricePaise": 4500, "lineTotalPaise": 9000, "status": "DELIVERED"]
        let dish: [String: Any] = ["id": UUID().uuidString, "lineType": "FOOD_MENU_ITEM", "menuItemId": item.uuidString, "name": "Meal", "quantity": quantity, "unitPricePaise": 3500, "lineTotalPaise": 7000, "status": "DELIVERED",
                                  "foodSelection": ["options": [["id": option.uuidString, "groupId": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "groupName": "Size", "name": "Regular", "priceDeltaPaise": 500]]]]
        var lines = mixed ? [retail, dish] : food ? [dish] : [retail]
        if duplicate { lines += lines }
        return try decode(["id": UUID().uuidString, "displayOrderNumber": "TEST", "orderType": food ? "FOOD" : "RETAIL", "status": "DELIVERED", "version": 1, "createdAt": "2026-10-10T00:00:00Z", "updatedAt": "2026-10-10T00:00:00Z",
                           "price": ["snapshotKind": "FINAL", "subtotalPaise": 9000, "deliveryFeePaise": 1500, "platformFeePaise": 210, "taxPaise": 0, "discountPaise": 0, "totalPaise": 10710, "currencyCode": "INR"], "lines": lines,
                           "restaurant": ["organizationId": UUID().uuidString, "branchId": branch.uuidString, "name": "Test Cafe", "branchName": "Main"]])
    }
}

private actor ReorderFunctions: FunctionClient {
    var missing = false, offline = false, closed = false, optionActive = true
    var stock = 99, delivery = true, serviceable = true, age = 0, areaOpen = true, price = 4500
    private(set) var writes = 0
    private var shouldHold = false
    private var held: CheckedContinuation<Void, Never>?, started: CheckedContinuation<Void, Never>?
    func configure(missing: Bool? = nil, price: Int? = nil, closed: Bool? = nil, optionActive: Bool? = nil,
                   stock: Int? = nil, delivery: Bool? = nil, serviceable: Bool? = nil, age: Int? = nil,
                   offline: Bool? = nil, areaOpen: Bool? = nil) {
        if let missing { self.missing = missing }; if let price { self.price = price }
        if let closed { self.closed = closed }; if let optionActive { self.optionActive = optionActive }
        if let stock { self.stock = stock }; if let delivery { self.delivery = delivery }
        if let serviceable { self.serviceable = serviceable }; if let age { self.age = age }
        if let offline { self.offline = offline }; if let areaOpen { self.areaOpen = areaOpen }
    }
    func hold() { shouldHold = true }
    func waitUntilHeld() async { if held != nil { return }; await withCheckedContinuation { started = $0 } }
    func release() { held?.resume(); held = nil }
    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(_ name: String, request: Input, idempotencyKey: IdempotencyKey) async throws -> Result {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        let operation = name == "customer-addresses" ? name : body["operation"] as? String ?? name
        if offline { throw URLError(.notConnectedToInternet) }
        let response: Any
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(age)))
        switch operation {
        case "customerCatalogue": response = ["catalogueVersion": "1", "categories": [], "subcategories": [], "skus": missing ? [] : [ReorderFixtures.productJSON(price: price)]]
        case "catalogueBrowseMap": response = ["version": 1, "nodes": []]
        case "customerRestaurants": response = ["restaurants": [ReorderFixtures.menuJSON(closed: closed, optionActive: optionActive)]]
        case "customerAreaAvailability": response = ["addressId": body["addressId"]!, "addressVersion": body["addressVersion"]!, "checkedAt": timestamp,
                                                       "groceryServiceable": serviceable, "foodServiceable": serviceable, "deliveryAvailable": delivery,
                                                       "stock": [ReorderFixtures.sku.uuidString.lowercased(): stock], "restaurants": [ReorderFixtures.branch.uuidString.lowercased(): areaOpen]]
        case "customerRestaurantAreaPage": response = ["addressId": body["addressId"]!, "addressVersion": body["addressVersion"]!, "checkedAt": timestamp, "ordering": "NEAREST", "restaurants": [ReorderFixtures.menuJSON(closed: closed, optionActive: optionActive)]]
        case "customer-addresses": response = ["addresses": [["addressId": "00000000-0000-4000-8000-000000000001", "label": "Home", "address": "Test Road", "building": "1", "details": "1", "displayAddress": "1 Test Road", "location": ["latitude": 12, "longitude": 78], "isDefault": true, "updatedAt": "2026-10-10T00:00:00Z"]]]
        default:
            if ["submit", "confirm", "save", "setDefault"].contains(operation) { writes += 1 }
            throw URLError(.notConnectedToInternet)
        }
        if shouldHold, operation == "customerCatalogue" {
            shouldHold = false
            await withCheckedContinuation { held = $0; started?.resume(); started = nil }
        }
        return try ReorderFixtures.decode(response)
    }
}
