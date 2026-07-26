import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class CatalogueClientTests: XCTestCase {
    func testStoreUpsertUsesTypedLocationAndNoClientAccountIdentity() async throws {
        let functions = RecordingCatalogueFunctionClient()
        let client = SupabaseCatalogueClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "store-key-1"))
        let location = GeoPoint(latitude: 12.6819, longitude: 78.6201)

        let store = try await client.upsertStore(
            name: "Corner Store",
            address: "12 Main Road",
            location: location,
            isPublished: true,
            acceptingOrders: true,
            idempotencyKey: key
        )

        XCTAssertEqual(store.location, location)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, "catalogue")
        XCTAssertEqual(call.idempotencyKey, key)
        let request = try JSONDecoder().decode(CapturedCatalogueRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "upsertStore")
        XCTAssertEqual(request.name, "Corner Store")
        XCTAssertEqual(request.location, location)
        XCTAssertEqual(request.isPublished, true)
        XCTAssertEqual(request.acceptingOrders, true)
        XCTAssertNil(request.accountId)
        XCTAssertNil(request.storeId)
    }

    func testCategoryUpsertUsesOptionalServerScopedIdentifier() async throws {
        let functions = RecordingCatalogueFunctionClient()
        let client = SupabaseCatalogueClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "category-key-1"))

        let category = try await client.upsertCategory(
            categoryID: categoryID,
            name: "Snacks and Drinks",
            displayOrder: 4,
            isActive: true,
            idempotencyKey: key
        )

        XCTAssertEqual(category.categoryID, categoryID)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedCatalogueRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "upsertCategory")
        XCTAssertEqual(request.categoryId, categoryID)
        XCTAssertEqual(request.displayOrder, 4)
        XCTAssertEqual(request.isActive, true)
        XCTAssertNil(request.storeId)
    }

    func testProductUpsertSendsIntegerPaiseWithoutRestrictionOverride() async throws {
        let functions = RecordingCatalogueFunctionClient()
        let client = SupabaseCatalogueClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "product-key-1"))

        let product = try await client.upsertProduct(
            productID: productID,
            categoryID: categoryID,
            name: "Lime Soda",
            description: "Freshly bottled",
            unitLabel: "750 ml",
            price: Money(paise: 12_500),
            imageObjectPath: "merchant/account/lime-soda.jpg",
            availability: .inStock,
            catalogueKind: .general,
            isActive: true,
            idempotencyKey: key
        )

        XCTAssertEqual(product.price, Money(paise: 12_500))
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedCatalogueRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "upsertProduct")
        XCTAssertEqual(request.price, Money(paise: 12_500))
        XCTAssertEqual(request.availability, .inStock)
        XCTAssertEqual(request.catalogueKind, .general)
        XCTAssertNil(request.restrictedApprovalState)
        XCTAssertNil(request.storeId)
        XCTAssertNil(request.accountId)
    }

    func testMerchantSnapshotDecodesServerCatalogue() async throws {
        let functions = RecordingCatalogueFunctionClient()
        let client = SupabaseCatalogueClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "snapshot-key-1"))

        let snapshot = try await client.merchantSnapshot(idempotencyKey: key)

        XCTAssertEqual(snapshot.stores.count, 1)
        XCTAssertEqual(snapshot.categories.count, 1)
        XCTAssertEqual(snapshot.products.first?.restrictedApprovalState, .notApplicable)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedCatalogueRequest.self, from: call.body).operation,
            "merchantSnapshot"
        )
    }

    func testBrowseSendsCustomerLocationAndDiscoveryRadiusAndDecodesServerPrices() async throws {
        let functions = RecordingCatalogueFunctionClient()
        let client = SupabaseCatalogueClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "browse-key-1"))
        let location = GeoPoint(latitude: 12.6819, longitude: 78.6201)

        let snapshot = try await client.browse(
            at: location,
            discoveryRadiusKilometres: 20,
            idempotencyKey: key
        )

        XCTAssertEqual(snapshot.products.first?.price, Money(paise: 12_500))
        XCTAssertEqual(snapshot.discoveryRadiusMeters, 20_000)
        let recordedCall = await functions.lastCall()
        let call = try XCTUnwrap(recordedCall)
        let request = try JSONDecoder().decode(CapturedCatalogueRequest.self, from: call.body)
        XCTAssertEqual(request.operation, "browse")
        XCTAssertEqual(request.location, location)
        XCTAssertEqual(request.discoveryRadiusMeters, 20_000)
        XCTAssertNil(request.accountId)
    }
}

private let storeID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private let categoryID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
private let productID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!

private struct CapturedCatalogueRequest: Decodable {
    let operation: String
    let accountId: UUID?
    let storeId: UUID?
    let name: String?
    let address: String?
    let location: GeoPoint?
    let isPublished: Bool?
    let acceptingOrders: Bool?
    let categoryId: UUID?
    let displayOrder: Int?
    let isActive: Bool?
    let productId: UUID?
    let description: String?
    let unitLabel: String?
    let price: Money?
    let imageObjectPath: String?
    let availability: CatalogueAvailability?
    let catalogueKind: CatalogueKind?
    let restrictedApprovalState: RestrictedApprovalState?
    let discoveryRadiusMeters: Int?
}

private actor RecordingCatalogueFunctionClient: FunctionClient {
    struct Call: Sendable {
        let name: String
        let body: Data
        let idempotencyKey: IdempotencyKey
    }

    private var call: Call?

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let body = try JSONEncoder().encode(request)
        call = Call(name: name, body: body, idempotencyKey: idempotencyKey)
        let operation = try JSONDecoder().decode(OperationOnly.self, from: body).operation
        let response: Data
        switch operation {
        case "upsertStore":
            response = storeJSON
        case "upsertCategory":
            response = categoryJSON
        case "upsertProduct":
            response = productJSON
        case "merchantSnapshot", "browse":
            response = snapshotJSON
        default:
            throw FunctionClientError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? {
        call
    }
}

private struct OperationOnly: Decodable {
    let operation: String
}

private let storeJSON = #"{"storeId":"33333333-3333-4333-8333-333333333333","name":"Corner Store","address":"12 Main Road","location":{"latitude":12.6819,"longitude":78.6201},"serviceZoneId":"66666666-6666-4666-8666-666666666666","isPublished":true,"acceptingOrders":true}"#.data(using: .utf8)!
private let categoryJSON = #"{"categoryId":"44444444-4444-4444-8444-444444444444","storeId":"33333333-3333-4333-8333-333333333333","name":"Snacks and Drinks","displayOrder":4,"isActive":true}"#.data(using: .utf8)!
private let productJSON = #"{"productId":"55555555-5555-4555-8555-555555555555","storeId":"33333333-3333-4333-8333-333333333333","categoryId":"44444444-4444-4444-8444-444444444444","name":"Lime Soda","description":"Freshly bottled","unitLabel":"750 ml","price":{"paise":12500},"imageObjectPath":"merchant/account/lime-soda.jpg","availability":"in_stock","catalogueKind":"general","restrictedApprovalState":"not_applicable","isActive":true}"#.data(using: .utf8)!
private let snapshotJSON = #"{"serviceZoneId":"66666666-6666-4666-8666-666666666666","discoveryRadiusMeters":20000,"stores":[{"storeId":"33333333-3333-4333-8333-333333333333","name":"Corner Store","address":"12 Main Road","location":{"latitude":12.6819,"longitude":78.6201},"serviceZoneId":"66666666-6666-4666-8666-666666666666","isPublished":true,"acceptingOrders":true}],"categories":[{"categoryId":"44444444-4444-4444-8444-444444444444","storeId":"33333333-3333-4333-8333-333333333333","name":"Snacks and Drinks","displayOrder":4,"isActive":true}],"products":[{"productId":"55555555-5555-4555-8555-555555555555","storeId":"33333333-3333-4333-8333-333333333333","categoryId":"44444444-4444-4444-8444-444444444444","name":"Lime Soda","description":"Freshly bottled","unitLabel":"750 ml","price":{"paise":12500},"imageObjectPath":"merchant/account/lime-soda.jpg","availability":"in_stock","catalogueKind":"general","restrictedApprovalState":"not_applicable","isActive":true}]}"#.data(using: .utf8)!
