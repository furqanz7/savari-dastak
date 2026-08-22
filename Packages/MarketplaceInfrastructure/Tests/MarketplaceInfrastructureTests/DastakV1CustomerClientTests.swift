import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakV1CustomerClientTests: XCTestCase {
    func testCatalogueUsesCanonicalEndpointWithoutMerchantLocationOrIdentity() async throws {
        let functions = RecordingV1FunctionClient()
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "catalogue-read-1"))

        let snapshot = try await client.catalogue(
            query: "milk",
            categoryID: categoryID,
            subcategoryID: nil,
            limit: 100,
            cursor: nil,
            idempotencyKey: key
        )

        XCTAssertEqual(snapshot.skus.first?.name, "Whole Milk")
        XCTAssertEqual(snapshot.skus.first?.price, Money(paise: 6_900))
        let recorded = await functions.lastCall()
        let call = try XCTUnwrap(recorded)
        XCTAssertEqual(call.name, "dastak-v1-catalogue")
        let request = try JSONSerialization.jsonObject(with: call.body) as? [String: Any]
        XCTAssertEqual(request?["operation"] as? String, "customerCatalogue")
        XCTAssertEqual(request?["query"] as? String, "milk")
        XCTAssertNil(request?["storeId"])
        XCTAssertNil(request?["merchantId"])
        XCTAssertNil(request?["location"])
    }

    func testSubmitSendsCanonicalSKUQuantityAndStartsWithoutClientPrice() async throws {
        let functions = RecordingV1FunctionClient()
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "submit-1"))
        let submission = DastakV1OrderSubmission(
            deliveryAddress: DastakV1DeliveryAddressInput(
                label: "Home",
                line1: "1 Launch Road",
                line2: nil,
                landmark: nil,
                city: "Vaniyambadi",
                state: "Tamil Nadu",
                postalCode: "635751",
                latitude: 12.6819,
                longitude: 78.6201,
                instructions: nil
            ),
            recipient: DastakV1RecipientInput(
                name: "Launch Customer",
                phoneNumber: "+919700000002"
            ),
            lines: [DastakV1OrderLineInput(skuID: skuID, quantity: 2)]
        )

        let order = try await client.submit(submission, idempotencyKey: key)

        XCTAssertEqual(order.status, .matching)
        let recorded = await functions.lastCall()
        let call = try XCTUnwrap(recorded)
        XCTAssertEqual(call.name, "dastak-v1-orders")
        let source = String(decoding: call.body, as: UTF8.self)
        XCTAssertTrue(source.contains(#""expectedVersion":0"#))
        XCTAssertTrue(source.contains(#""lineType":"RETAIL_SKU""#))
        XCTAssertFalse(source.contains("pricePaise"))
        XCTAssertFalse(source.contains("storeId"))
        XCTAssertFalse(source.contains("merchantId"))
    }

    func testCancelCarriesServerVersionAndStableIdentity() async throws {
        let functions = RecordingV1FunctionClient()
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "cancel-1"))

        _ = try await client.cancel(id: orderID, expectedVersion: 2, idempotencyKey: key)

        let recorded = await functions.lastCall()
        let call = try XCTUnwrap(recorded)
        let request = try JSONSerialization.jsonObject(with: call.body) as? [String: Any]
        XCTAssertEqual(request?["operation"] as? String, "cancel")
        XCTAssertEqual(request?["expectedVersion"] as? Int, 2)
        XCTAssertEqual(request?["orderId"] as? String, orderID.uuidString)
    }

    func testOrderDecodesPaymentReservationWithoutMerchantOrWaveDetails() throws {
        var source = try XCTUnwrap(JSONSerialization.jsonObject(with: orderJSON) as? [String: Any])
        source["status"] = "AWAITING_PAYMENT"
        source["customerState"] = "PAYMENT_READY"
        source["payment"] = [
            "status": "RESERVED",
            "amountPaise": 13_800,
            "currencyCode": "INR",
            "reservedAt": "2026-08-22T10:01:00Z",
            "expiresAt": "2026-08-22T10:06:00Z",
            "secondsRemaining": 299,
            "canAttempt": true,
            "canRetry": true,
            "latestAttempt": [
                "id": "77777777-7777-4777-8777-777777777777",
                "status": "FAILED",
                "failureCode": "CHECKOUT_FAILED",
                "createdAt": "2026-08-22T10:02:00Z",
                "failedAt": "2026-08-22T10:02:30Z",
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: source)
        let order = try JSONDecoder().decode(DastakV1OrderSnapshot.self, from: data)

        XCTAssertEqual(order.status, .awaitingPayment)
        XCTAssertEqual(order.customerState, "PAYMENT_READY")
        XCTAssertEqual(order.payment?.amount, Money(paise: 13_800))
        XCTAssertEqual(order.payment?.latestAttempt?.status, "FAILED")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("merchant"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("wave"))
    }
}

private actor RecordingV1FunctionClient: FunctionClient {
    struct Call: Sendable {
        let name: String
        let body: Data
    }

    private var call: Call?

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let body = try JSONEncoder().encode(request)
        call = Call(name: name, body: body)
        let operation = try JSONDecoder().decode(Operation.self, from: body).operation
        let response = operation == "customerCatalogue" ? catalogueJSON : orderJSON
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? { call }
}

private struct Operation: Decodable { let operation: String }
private let categoryID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let subcategoryID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
private let skuID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private let orderID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
private let lineID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!

private let catalogueJSON = """
{
  "catalogueVersion":"2026-08-22T10:00:00Z",
  "categories":[{"id":"\(categoryID)","name":"Groceries","slug":"groceries","imageKey":null,"sortOrder":1}],
  "subcategories":[{"id":"\(subcategoryID)","categoryId":"\(categoryID)","name":"Dairy","slug":"dairy","imageKey":null,"sortOrder":1}],
  "skus":[{
    "id":"\(skuID)","categoryId":"\(categoryID)","subcategoryId":"\(subcategoryID)",
    "brand":{"id":"66666666-6666-4666-8666-666666666666","name":"Dastak Daily","slug":"dastak-daily"},
    "name":"Whole Milk","slug":"whole-milk","variant":"Full cream","packSize":"1 litre",
    "description":"Fresh milk","imageKey":null,"barcode":"8901000000001",
    "listPricePaise":7200,"sellingPricePaise":6900,"currencyCode":"INR",
    "logisticsAttributes":{"weightGrams":1030,"temperatureClass":"CHILLED","fragile":false,"bulky":false}
  }],
  "nextCursor":null
}
""".data(using: .utf8)!

private let orderJSON = """
{
  "id":"\(orderID)","displayOrderNumber":"DSK-260822-00000001","orderType":"RETAIL_ONLY",
  "status":"MATCHING","version":2,"fulfilmentProgress":{"state":"FINDING_ITEMS"},
  "price":{"snapshotKind":"SUBMITTED","subtotalPaise":13800,"deliveryFeePaise":0,"platformFeePaise":0,"discountPaise":0,"taxPaise":0,"totalPaise":13800,"currencyCode":"INR"},
  "lines":[{"id":"\(lineID)","lineType":"RETAIL_SKU","skuId":"\(skuID)","name":"Whole Milk","variant":"Full cream","packSize":"1 litre","quantity":2,"unitPricePaise":6900,"lineTotalPaise":13800,"status":"ORDERED"}],
  "submittedAt":"2026-08-22T10:00:00Z","fullySecuredAt":null,"paymentExpiresAt":null,"paidAt":null,"deliveredAt":null,
  "createdAt":"2026-08-22T10:00:00Z","updatedAt":"2026-08-22T10:00:00Z"
}
""".data(using: .utf8)!
