import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakAvailabilityTests: XCTestCase {
    private let sku = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let address = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private let version = "2026-10-10T00:00:00Z"

    @MainActor
    func testLocalTrendingUsesExactServerProductsAndClearsOnFailureOrStaleArea() async throws {
        let functions = AvailabilityFunctions()
        let milk = try product()
        await functions.configureTrending([milk])
        let model = await makeModel(functions)
        XCTAssertEqual(model.localTrendingProducts?.map(\.id), [milk.id])
        XCTAssertEqual(model.knownCatalogueProducts.first(where: { $0.id == milk.id }), milk)
        model.pickUpBasket(.grocery)
        model.addShoppingProduct(milk)
        XCTAssertEqual(model.baskets[.grocery].itemCount, 1)
        await functions.configure(offline: true)
        await model.refreshAreaAvailability(force: true)
        XCTAssertNil(model.localTrendingProducts)
        await functions.configure(age: 60, offline: false)
        await model.refreshAreaAvailability(force: true)
        XCTAssertNil(model.localTrendingProducts)
        await functions.configure(age: 0)
        await functions.configureTrending([])
        await model.refreshAreaAvailability(force: true)
        XCTAssertEqual(model.localTrendingProducts, [], "A successful empty ranking is distinct from unavailable")
    }

    func testLocalTrendingRejectsDuplicateExactSkusInAvailability() async throws {
        let functions = AvailabilityFunctions()
        let milk = try product()
        await functions.configureTrending([milk, milk])
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        do {
            _ = try await client.areaAvailability(context: .init(addressID: address, addressVersion: version), idempotencyKey: IdempotencyKey())
            XCTFail("Duplicate ranking accepted")
        } catch { XCTAssertEqual(error as? FunctionClientError, .invalidResponse) }
    }

    func testReadOnlyPricingRequestAndDistanceBandsMatchWeb() async throws {
        let functions = AvailabilityFunctions()
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        let context = DastakV1AreaContext(addressID: address, addressVersion: version)
        let lines = [DastakV1OrderLineInput(skuID: sku, quantity: 1)]
        for distance in [0, 1000, 1001, 2000, 2001, 3000, 3001, 6000] {
            await functions.configure(distance: distance)
            let quote = try await client.checkoutQuote(context: context, lines: lines, branchID: nil, idempotencyKey: IdempotencyKey())
            let expected = distance <= 1000 ? 1500 : distance <= 2000 ? 2000 : 2000 + 500 * ((distance - 2000 + 999) / 1000)
            XCTAssertEqual(quote.deliveryFeePaise, expected)
            XCTAssertEqual(quote.platformFeePaise, ((10000 + expected) * 200 + 5000) / 10000)
        }
        let recorded = await functions.lastQuoteRequest
        let request = try XCTUnwrap(recorded)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request) as? [String: Any])
        XCTAssertEqual(body["operation"] as? String, "customerCheckoutQuote")
        XCTAssertNil(body["recipient"])
        XCTAssertNil(body["latitude"])
        XCTAssertNil(body["idempotencyKey"])
        XCTAssertEqual(Set(body.keys), ["operation", "addressId", "addressVersion", "lines"])
        for subtotal in [24, 25, 74, 75] {
            await functions.configure(subtotal: subtotal, distance: 1000)
            let quote = try await client.checkoutQuote(context: context, lines: lines, branchID: nil, idempotencyKey: IdempotencyKey())
            XCTAssertEqual(quote.platformFeePaise, ((subtotal + 1500) * 200 + 5000) / 10000)
        }
    }

    func testRejectsMismatchedContextAmountsAndExpiredDuration() async throws {
        let functions = AvailabilityFunctions()
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        let context = DastakV1AreaContext(addressID: address, addressVersion: version)
        let lines = [DastakV1OrderLineInput(skuID: sku, quantity: 1)]
        for field in ["platformFeePaise", "deliveryFeePaise", "totalPaise", "pricingVersion"] {
            await functions.setInvalidQuote(field)
            do {
                _ = try await client.checkoutQuote(context: context, lines: lines, branchID: nil, idempotencyKey: IdempotencyKey())
                XCTFail("Accepted invalid \(field)")
            } catch { XCTAssertEqual(error as? FunctionClientError, .invalidResponse) }
        }
        await functions.setInvalidQuote("addressId")
        do {
            _ = try await client.checkoutQuote(context: context, lines: lines, branchID: nil, idempotencyKey: IdempotencyKey())
            XCTFail("Accepted another address")
        } catch { XCTAssertEqual(error as? FunctionClientError, .invalidResponse) }
        await functions.setInvalidQuote("lines")
        do {
            _ = try await client.checkoutQuote(context: context, lines: lines, branchID: nil, idempotencyKey: IdempotencyKey())
            XCTFail("Accepted different lines")
        } catch { XCTAssertEqual(error as? FunctionClientError, .invalidResponse) }
        await functions.setInvalidQuote("validUntil")
        do {
            _ = try await client.checkoutQuote(context: context, lines: lines, branchID: nil, idempotencyKey: IdempotencyKey())
            XCTFail("Accepted oversized lifetime")
        } catch { XCTAssertEqual(error as? FunctionClientError, .invalidResponse) }
    }

    func testFoodQuoteBindsRestaurantAndExactOptions() async throws {
        let functions = AvailabilityFunctions()
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        let context = DastakV1AreaContext(addressID: address, addressVersion: version)
        let lines = [DastakV1OrderLineInput(menuItemID: UUID(), optionIDs: [UUID()], quantity: 2)]
        let branch = UUID()
        let value = try await client.checkoutQuote(context: context, lines: lines, branchID: branch, idempotencyKey: IdempotencyKey())
        XCTAssertEqual(value.restaurantBranchId, branch)
        XCTAssertEqual(value.lines, lines)
        XCTAssertThrowsError(try value.validate(context: context, lines: [.init(menuItemID: lines[0].menuItemID!, optionIDs: [], quantity: 2)], branchID: branch))
        XCTAssertThrowsError(try value.validate(context: context, lines: lines, branchID: UUID()))
    }

    @MainActor
    func testStockLimitsApplyWithoutRidersAndSubmitRemainsBlocked() async throws {
        let functions = AvailabilityFunctions()
        await functions.configure(delivery: false, stock: 2)
        await functions.enableRestaurants()
        let model = await makeModel(functions)
        let product = try product()
        XCTAssertNil(model.browsingAreaMessage)
        model.cartService = .food
        XCTAssertNil(model.browsingAreaMessage)
        XCTAssertTrue(model.checkoutAvailabilityIssue?.contains("No delivery partners") == true)
        model.cartService = .grocery
        model.addToCart(product)
        model.addToCart(product)
        model.addToCart(product)
        XCTAssertEqual(model.cart.itemCount, 2)
        XCTAssertNotNil(model.groceryAddIssue(product.id))
        XCTAssertEqual(model.groceryStockQuantity(product.id), 2, "Basket limit is not an out-of-stock label")
        XCTAssertEqual(model.groceryStockQuantity(UUID()), 0, "A missing SKU in confirmed area stock is out of stock")
        await model.refreshCheckoutEstimate()
        XCTAssertEqual(model.currentCheckoutEstimate?.deliveryFeePaise, 1500)
        XCTAssertEqual(model.currentCheckoutEstimate?.platformFeePaise, 430)
        XCTAssertTrue(model.checkoutAvailabilityIssue?.contains("No delivery partners") == true)
        let submitted = await model.submitV1Order()
        XCTAssertFalse(submitted)
        let writes = await functions.submitCount
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(model.cart.itemCount, 2)
        model.decrementCartItem(product.id)
        XCTAssertEqual(model.cart.itemCount, 1)
    }

    @MainActor
    func testNoMerchantsOrRestaurantsShowsUnavailableAndPreservesBasket() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        model.addToCart(try product())
        await functions.configure(serviceable: false)
        await model.refreshAreaAvailability(force: true)
        XCTAssertEqual(model.areaMessage, "This area is not serviceable yet.")
        XCTAssertEqual(model.browsingAreaMessage, "This area is not serviceable yet.")
        XCTAssertEqual(model.groceryAddIssue(sku), "This area is not serviceable yet.")
        XCTAssertNil(model.groceryStockQuantity(sku), "An unserviceable area does not confirm individual pack stock")
        XCTAssertEqual(model.cart.itemCount, 1)
        model.cartService = .food
        XCTAssertEqual(model.areaMessage, "Food delivery isn’t available in your area yet.")
        XCTAssertEqual(model.browsingAreaMessage, "Food delivery isn’t available in your area yet.")
        XCTAssertTrue(model.v1Restaurants.isEmpty)
    }

    @MainActor
    func testClosedRestaurantsStayVisibleAndPaginationLoadsOnlyRequestedPages() async throws {
        let functions = AvailabilityFunctions()
        await functions.enableRestaurants()
        let model = await makeModel(functions)
        XCTAssertEqual(model.v1Restaurants.count, 1)
        XCTAssertTrue(model.hasMoreV1Restaurants)
        XCTAssertEqual(model.restaurantIssue(model.v1Restaurants[0]), "Store closed")
        await model.refreshV1Restaurants(loadMore: true)
        XCTAssertEqual(model.v1Restaurants.count, 2)
        XCTAssertFalse(model.hasMoreV1Restaurants)
        XCTAssertNil(model.restaurantIssue(model.v1Restaurants[1]))
    }

    @MainActor
    func testFoodFailureDoesNotInvalidateGroceryStockOrFeesAndCanRetry() async throws {
        let functions = AvailabilityFunctions()
        await functions.enableRestaurants()
        await functions.configureRestaurants(failing: true)
        let model = await makeModel(functions)
        XCTAssertNotNil(model.v1RestaurantsRefreshFailure)
        XCTAssertNotNil(model.currentAreaAvailability)
        XCTAssertNil(model.availabilityError)
        XCTAssertNil(model.groceryAddIssue(sku))
        model.addToCart(try product())
        await model.refreshCheckoutEstimate()
        XCTAssertNotNil(model.currentCheckoutEstimate)
        XCTAssertNil(model.checkoutAvailabilityIssue)
        await functions.configureRestaurants(failing: false)
        await model.retryV1Restaurants()
        XCTAssertEqual(model.v1Restaurants.count, 1)
        XCTAssertNil(model.v1RestaurantsRefreshFailure)
    }

    @MainActor
    func testFailedLoadMorePreservesRestaurantsAndRetryContinuesSamePage() async throws {
        let functions = AvailabilityFunctions()
        await functions.enableRestaurants()
        let model = await makeModel(functions)
        await functions.configureRestaurants(failing: true)
        await model.refreshV1Restaurants(loadMore: true)
        XCTAssertEqual(model.v1Restaurants.count, 1)
        XCTAssertTrue(model.hasMoreV1Restaurants)
        XCTAssertNotNil(model.v1RestaurantsRefreshFailure)
        await functions.configureRestaurants(failing: false)
        await model.retryV1Restaurants()
        XCTAssertEqual(model.v1Restaurants.count, 2)
        XCTAssertFalse(model.hasMoreV1Restaurants)
    }

    @MainActor
    func testRepeatedFoodCursorIsRejectedWithoutReplacingLoadedRestaurants() async throws {
        let functions = AvailabilityFunctions()
        await functions.enableRestaurants()
        let model = await makeModel(functions)
        await functions.configureRestaurants(repeatingCursor: true)
        await model.refreshV1Restaurants(loadMore: true)
        XCTAssertEqual(model.v1Restaurants.count, 1)
        XCTAssertNotNil(model.v1RestaurantsRefreshFailure)
        XCTAssertNotNil(model.currentAreaAvailability)
    }

    @MainActor
    func testLateFoodPageCannotRestorePreviousAddressMenus() async throws {
        let functions = AvailabilityFunctions()
        await functions.enableRestaurants()
        let model = await makeModel(functions)
        await functions.holdRestaurants()
        let loading = Task { await model.refreshV1Restaurants(loadMore: true) }
        await functions.waitForRestaurants()
        let changed = await model.setLocation(.init(address: "Second Road", point: .init(latitude: 12, longitude: 78), label: "Work", building: "2"))
        XCTAssertTrue(changed)
        await functions.releaseRestaurants()
        await loading.value
        XCTAssertEqual(model.currentAreaAvailability?.addressVersion, "2026-10-10T00:00:01Z")
        XCTAssertEqual(model.v1Restaurants.map(\.id), [UUID(uuidString: "77777777-7777-4777-8777-777777777777")!])
        XCTAssertFalse(model.isLoadingV1Restaurants)
    }

    @MainActor
    func testMissingSavedMenuChecksRemainingPagesWithoutInvalidatingGrocery() async throws {
        let functions = AvailabilityFunctions()
        await functions.enableRestaurants()
        let model = await makeModel(functions)
        XCTAssertEqual(model.v1Restaurants.count, 1)
        let checked = await model.resolveSavedItems(skuIDs: [], menuIDs: [UUID()])
        XCTAssertTrue(checked) // Exhausted pages prove this item is no longer in the nearby menus.
        XCTAssertEqual(model.v1Restaurants.count, 2)
        XCTAssertFalse(model.hasMoreV1Restaurants)
        XCTAssertNil(model.savedItemsRefreshFailure)
        XCTAssertNotNil(model.currentAreaAvailability)
        XCTAssertNil(model.groceryAddIssue(sku))
    }

    @MainActor
    func testQuoteInvalidatesOnBasketAddressAndServiceChanges() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        model.addToCart(try product())
        await model.refreshCheckoutEstimate()
        XCTAssertNotNil(model.currentCheckoutEstimate)
        model.addToCart(try product())
        XCTAssertNil(model.currentCheckoutEstimate)
        await model.refreshCheckoutEstimate()
        XCTAssertNotNil(model.currentCheckoutEstimate)
        model.cartService = .food
        XCTAssertNil(model.currentCheckoutEstimate)
        model.cartService = .grocery
        let changed = await model.setLocation(.init(address: "Second Road", point: .init(latitude: 12, longitude: 78), label: "Work", building: "2"))
        XCTAssertTrue(changed)
        XCTAssertNil(model.currentCheckoutEstimate)
        await model.refreshCheckoutEstimate()
        XCTAssertEqual(model.currentCheckoutEstimate?.addressVersion, "2026-10-10T00:00:01Z")
    }

    @MainActor
    func testLateQuoteCannotRestoreOldBasketPricing() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        model.addToCart(try product())
        await functions.holdQuote()
        let loading = Task { await model.refreshCheckoutEstimate() }
        await functions.waitForQuote()
        model.addToCart(try product())
        await functions.releaseQuote()
        await loading.value
        XCTAssertNil(model.currentCheckoutEstimate)
        XCTAssertEqual(model.cart.itemCount, 2)
    }

    @MainActor
    func testMissingLocationAndExpiredQuoteCannotSubmit() async throws {
        let functions = AvailabilityFunctions()
        let account = UUID()
        let model = DastakCustomerModel(functions: functions, accountIDProvider: { account }, checkoutJournalStorage: AvailabilityJournal())
        await model.restoreCartStorage()
        model.addToCart(try product())
        XCTAssertTrue(model.cart.isEmpty)
        XCTAssertTrue(model.groceryAddIssue(sku)?.contains("Choose your delivery location") == true)
        let ready = await makeModel(functions)
        ready.addToCart(try product())
        await functions.configure(age: 60)
        await ready.refreshCheckoutEstimate()
        XCTAssertNil(ready.currentCheckoutEstimate)
        XCTAssertNotNil(ready.checkoutAvailabilityIssue)
        let submitted = await ready.submitV1Order()
        XCTAssertFalse(submitted)
        let writes = await functions.submitCount
        XCTAssertEqual(writes, 0)
    }

    @MainActor
    func testPendingRecoveryKeepsOriginalKeyEvenWhenAreaIsNowOffline() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        model.addToCart(try product())
        let submitted = await model.submitV1Order() // Test double loses the submit response.
        XCTAssertFalse(submitted)
        let original = try XCTUnwrap(model.pendingCheckout)
        await functions.configure(offline: true)
        await model.refreshAreaAvailability(force: true)
        XCTAssertNil(model.currentAreaAvailability)
        let recovered = await model.submitV1Order()
        XCTAssertFalse(recovered)
        XCTAssertEqual(model.pendingCheckout, original)
        let keys = await functions.submitKeys
        XCTAssertEqual(keys, [original.key, original.key])
    }

    @MainActor
    func testLateAreaResponseCannotRestorePreviousAddress() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        await functions.holdArea()
        let loading = Task { await model.refreshAreaAvailability(force: true) }
        await functions.waitForArea()
        let changed = await model.setLocation(.init(address: "Second Road", point: .init(latitude: 12, longitude: 78), label: "Work", building: "2"))
        XCTAssertTrue(changed)
        await functions.releaseArea()
        await loading.value
        XCTAssertEqual(model.currentAreaAvailability?.addressVersion, "2026-10-10T00:00:01Z")
    }

    @MainActor
    func testOfflineExpiredOrReducedStockFailsClosed() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        model.addToCart(try product())
        model.addToCart(try product())
        await functions.configure(stock: 1)
        await model.refreshAreaAvailability(force: true)
        await model.refreshCheckoutEstimate()
        XCTAssertTrue(model.checkoutAvailabilityIssue?.contains("out of stock") == true)
        await functions.configure(age: 60)
        await model.refreshAreaAvailability(force: true)
        XCTAssertNil(model.currentAreaAvailability)
        XCTAssertNotNil(model.groceryAddIssue(sku))
        await functions.configure(age: 0, offline: true)
        await model.refreshAreaAvailability(force: true)
        XCTAssertNil(model.currentAreaAvailability)
        XCTAssertNotNil(model.areaMessage)
        XCTAssertEqual(model.cart.itemCount, 2)
    }

    @MainActor
    func testAdjustedAddressSaveSendsExactPointAndRefreshesServerVersion() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        model.addToCart(try product())
        await model.refreshCheckoutEstimate()
        let saved = try XCTUnwrap(model.deliveryAddress)
        let point = GeoPoint(latitude: 12.30896, longitude: 76.65235)
        let draft = DastakDeliveryLocation(addressID: saved.addressID, address: "Second Road", point: point,
                                          label: "Work", building: "Block A", floor: "2", landmark: "Library",
                                          deliveryNotes: "Ring the bell")
        let result = await model.setLocation(draft)
        XCTAssertTrue(result)
        let requestData = await functions.lastAddressSaveRequest
        let request = try XCTUnwrap(requestData)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request) as? [String: Any])
        let coordinates = try XCTUnwrap(body["location"] as? [String: Double])
        XCTAssertEqual(body["addressId"] as? String, saved.addressID?.uuidString)
        XCTAssertEqual(coordinates["latitude"], point.latitude)
        XCTAssertEqual(coordinates["longitude"], point.longitude)
        XCTAssertEqual(body["building"] as? String, "Block A")
        XCTAssertEqual(body["floor"] as? String, "2")
        XCTAssertEqual(body["landmark"] as? String, "Library")
        XCTAssertEqual(body["deliveryNotes"] as? String, "Ring the bell")
        XCTAssertEqual(model.deliveryAddress?.point, point)
        XCTAssertEqual(model.deliveryAddress?.addressID, saved.addressID)
        XCTAssertEqual(model.currentAreaAvailability?.addressVersion, "2026-10-10T00:00:01Z")
        XCTAssertNil(model.currentCheckoutEstimate)
        XCTAssertEqual(model.cart.itemCount, 1)
    }

    @MainActor
    func testFailedAddressSaveDoesNotActivateDraftArea() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        let original = model.deliveryAddress
        let area = model.currentAreaAvailability?.addressVersion
        await functions.failAddressSave()
        let result = await model.setLocation(.init(address: "Second Road", point: .init(latitude: 13, longitude: 77),
                                                   label: "Work", building: "2"))
        XCTAssertFalse(result)
        XCTAssertEqual(model.deliveryAddress, original)
        XCTAssertEqual(model.currentAreaAvailability?.addressVersion, area)
        XCTAssertNotNil(model.addressErrorMessage)
    }

    @MainActor
    func testIncompleteDraftCannotSendAddressSave() async throws {
        let functions = AvailabilityFunctions()
        let model = await makeModel(functions)
        let original = model.deliveryAddress
        let result = await model.setLocation(.init(address: "Pinned location", point: .init(latitude: 13, longitude: 77)))
        XCTAssertFalse(result)
        let request = await functions.lastAddressSaveRequest
        XCTAssertNil(request)
        XCTAssertEqual(model.deliveryAddress, original)
    }

    @MainActor
    private func makeModel(_ functions: AvailabilityFunctions) async -> DastakCustomerModel {
        let account = UUID()
        let model = DastakCustomerModel(functions: functions, checkoutCustomerProvider: {
            .init(displayName: "Test Customer", email: nil, phoneNumber: "+919999999999")
        }, accountIDProvider: { account }, checkoutJournalStorage: AvailabilityJournal())
        await model.bootstrap()
        await model.refreshAreaAvailability(force: true)
        return model
    }

    private func product() throws -> DastakV1CatalogueSKU {
        try JSONDecoder().decode(DastakV1CatalogueSKU.self, from: Data("""
        {"id":"\(sku)","categoryId":"55555555-5555-4555-8555-555555555555",
        "subcategoryId":"66666666-6666-4666-8666-666666666666","name":"Test Milk","slug":"test-milk",
        "packSize":"1 L","listPricePaise":10000,"sellingPricePaise":10000,"currencyCode":"INR","logisticsAttributes":{}}
        """.utf8))
    }
}

private extension IdempotencyKey {
    init() { self = IdempotencyKey(rawValue: UUID().uuidString)! }
}

@MainActor
private final class AvailabilityJournal: DastakCheckoutJournalStorage {
    var values: [UUID: DastakCheckoutJournal] = [:]
    func load(accountID: UUID) throws -> DastakCheckoutJournal? { values[accountID] }
    func save(_ journal: DastakCheckoutJournal, replacing revision: UUID?) throws {
        guard values[journal.accountID]?.revision == revision else { throw DastakCheckoutStorageError.changedJournal }
        values[journal.accountID] = journal
    }
}

private actor AvailabilityFunctions: FunctionClient {
    private var trendingProducts: [DastakV1CatalogueSKU]?
    func configureTrending(_ products: [DastakV1CatalogueSKU]) { trendingProducts = products }
    private var delivery = true, serviceable = true, offline = false, hasRestaurants = false
    private var stock = 99, distance = 1000, subtotal = 10000, age = 0
    private var invalidQuote: String?
    private var holdNext = false
    private var quoteWait: CheckedContinuation<Void, Never>?
    private var quoteStarted: CheckedContinuation<Void, Never>?
    private var holdNextArea = false
    private var areaWait: CheckedContinuation<Void, Never>?
    private var areaStarted: CheckedContinuation<Void, Never>?
    private var restaurantsFail = false, repeatingRestaurantCursor = false, holdNextRestaurants = false
    private var restaurantWait: CheckedContinuation<Void, Never>?
    private var restaurantStarted: CheckedContinuation<Void, Never>?
    private(set) var lastQuoteRequest: Data?
    private(set) var lastAddressSaveRequest: Data?
    private var addressSaveFails = false
    private(set) var submitCount = 0
    private(set) var submitKeys: [IdempotencyKey] = []

    func configure(delivery: Bool? = nil, serviceable: Bool? = nil, stock: Int? = nil, subtotal: Int? = nil, distance: Int? = nil, age: Int? = nil, offline: Bool? = nil) {
        if let delivery { self.delivery = delivery }; if let serviceable { self.serviceable = serviceable }
        if let stock { self.stock = stock }; if let subtotal { self.subtotal = subtotal }
        if let distance { self.distance = distance }; if let age { self.age = age }; if let offline { self.offline = offline }
    }
    func enableRestaurants() { hasRestaurants = true }
    func configureRestaurants(failing: Bool = false, repeatingCursor: Bool = false) {
        restaurantsFail = failing; repeatingRestaurantCursor = repeatingCursor
    }
    func holdRestaurants() { holdNextRestaurants = true }
    func waitForRestaurants() async { if restaurantWait != nil { return }; await withCheckedContinuation { restaurantStarted = $0 } }
    func releaseRestaurants() { restaurantWait?.resume(); restaurantWait = nil }
    func failAddressSave() { addressSaveFails = true }
    func setInvalidQuote(_ field: String) { invalidQuote = field }
    func holdQuote() { holdNext = true }
    func waitForQuote() async { if quoteWait != nil { return }; await withCheckedContinuation { quoteStarted = $0 } }
    func releaseQuote() { quoteWait?.resume(); quoteWait = nil }
    func holdArea() { holdNextArea = true }
    func waitForArea() async { if areaWait != nil { return }; await withCheckedContinuation { areaStarted = $0 } }
    func releaseArea() { areaWait?.resume(); areaWait = nil }

    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(_ name: String, request: Input, idempotencyKey: IdempotencyKey) async throws -> Result {
        let data = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let operation = body["operation"] as? String
        if operation == "submit" { submitCount += 1; submitKeys.append(idempotencyKey) }
        if name == "customer-addresses" {
            let version = body["address"] as? String == "Second Road" ? "2026-10-10T00:00:01Z" : "2026-10-10T00:00:00Z"
            if operation == "save" {
                lastAddressSaveRequest = data
                if addressSaveFails { throw URLError(.notConnectedToInternet) }
                var saved = body
                saved["addressId"] = "00000000-0000-4000-8000-000000000001"
                saved["details"] = body["building"] ?? ""
                saved["displayAddress"] = body["address"] ?? ""
                saved["isDefault"] = true
                saved["updatedAt"] = version
                return try JSONDecoder().decode(Result.self, from: JSONSerialization.data(withJSONObject: ["addresses": [saved]]))
            }
            return try JSONDecoder().decode(Result.self, from: Data("""
            {"addresses":[{"addressId":"00000000-0000-4000-8000-000000000001","label":"Home","address":"Test Road",
            "building":"1","details":"1","displayAddress":"1 Test Road","location":{"latitude":12,"longitude":78},
            "isDefault":true,"updatedAt":"\(version)"}]}
            """.utf8))
        }
        guard !offline else { throw URLError(.notConnectedToInternet) }
        let checked = Date().addingTimeInterval(-Double(age))
        let formatter = ISO8601DateFormatter()
        var result: [String: Any] = ["addressId": body["addressId"] ?? "", "addressVersion": body["addressVersion"] ?? "", "checkedAt": formatter.string(from: checked)]
        switch operation {
        case "customerAreaAvailability":
            result.merge(["groceryServiceable": serviceable, "foodServiceable": serviceable && hasRestaurants, "deliveryAvailable": delivery,
                "stock": stock > 0 ? ["11111111-1111-4111-8111-111111111111": stock] : [:],
                "restaurants": hasRestaurants ? ["77777777-7777-4777-8777-777777777777": false, "88888888-8888-4888-8888-888888888888": true] : [:]]) { _, new in new }
            if let trendingProducts {
                result["trendingSkus"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(trendingProducts))
            }
        case "customerCheckoutQuote":
            lastQuoteRequest = data
            let lines = body["lines"] as? [[String: Any]] ?? []
            let items = subtotal * lines.reduce(0) { $0 + ($1["quantity"] as? Int ?? 0) }
            let fee = distance <= 1000 ? 1500 : distance <= 2000 ? 2000 : 2000 + 500 * ((distance - 2000 + 999) / 1000)
            let platform = ((items + fee) * 200 + 5000) / 10000
            result.merge(["lines": lines, "restaurantBranchId": body["restaurantBranchId"] ?? NSNull(), "kind": "ESTIMATE", "currencyCode": "INR", "pricingVersion": 1,
                "validUntil": formatter.string(from: checked.addingTimeInterval(45)), "subtotalPaise": items, "deliveryDistanceMeters": distance,
                "deliveryFeePaise": fee, "platformFeePaise": platform, "taxPaise": 0, "discountPaise": 0, "totalPaise": items + fee + platform, "deliveryAvailable": delivery]) { _, new in new }
            if let invalidQuote {
                switch invalidQuote {
                case "addressId": result[invalidQuote] = UUID().uuidString
                case "lines": result[invalidQuote] = []
                case "validUntil": result[invalidQuote] = formatter.string(from: checked.addingTimeInterval(60))
                default: result[invalidQuote] = 0
                }
            }
        case "customerRestaurantAreaPage":
            if restaurantsFail { throw URLError(.notConnectedToInternet) }
            let second = body["cursor"] is [String: Any]
            let branch = second ? "88888888-8888-4888-8888-888888888888" : "77777777-7777-4777-8777-777777777777"
            let menu = try JSONSerialization.jsonObject(with: Data("""
            {"restaurant":{"organizationId":"99999999-9999-4999-8999-999999999999","branchId":"\(branch)","name":"Cafe","branchName":"Main",
            "acceptingOrders":\(second),"isOpen":\(second),"branchStatus":"ACTIVE","merchantType":"RESTAURANT_CAFE","softActiveOrderThreshold":5,"activeOrderCount":0},"categories":[]}
            """.utf8))
            result["restaurants"] = [menu]
            result["ordering"] = "NEAREST"
            result["nextCursor"] = second && !repeatingRestaurantCursor ? NSNull() : ["name": "Cafe", "branchId": "77777777-7777-4777-8777-777777777777", "distanceMeters": 1000, "addressId": body["addressId"]!, "addressVersion": body["addressVersion"]!]
        default: throw URLError(.notConnectedToInternet)
        }
        let response = try JSONSerialization.data(withJSONObject: result)
        if operation == "customerRestaurantAreaPage" && holdNextRestaurants {
            holdNextRestaurants = false
            await withCheckedContinuation { restaurantWait = $0; restaurantStarted?.resume(); restaurantStarted = nil }
        }
        if operation == "customerAreaAvailability" && holdNextArea {
            holdNextArea = false
            await withCheckedContinuation { areaWait = $0; areaStarted?.resume(); areaStarted = nil }
        }
        if operation == "customerCheckoutQuote" && holdNext {
            holdNext = false
            await withCheckedContinuation { quoteWait = $0; quoteStarted?.resume(); quoteStarted = nil }
        }
        return try JSONDecoder().decode(Result.self, from: response)
    }
}
