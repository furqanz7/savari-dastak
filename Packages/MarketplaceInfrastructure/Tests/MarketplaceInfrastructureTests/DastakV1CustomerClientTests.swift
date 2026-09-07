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
        XCTAssertEqual(snapshot.categoryTypes?.first?.previewImageKeys, ["catalogue/milk.webp"])
        XCTAssertEqual(snapshot.categoryTypes?.first?.navigationSection?.name, "Grocery & Kitchen")
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

    func testRestaurantDiscoveryAndMixedSubmitCarryExactIdentityWithoutClientPrice() async throws {
        let functions = RecordingV1FunctionClient()
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "restaurant-read"))
        let restaurants = try await client.restaurants(
            query: nil,
            limit: 50,
            idempotencyKey: key
        )
        let restaurant = try XCTUnwrap(restaurants.first)
        let item = try XCTUnwrap(restaurant.categories.first?.items.first)
        let option = try XCTUnwrap(item.optionGroups.first?.options.first)
        XCTAssertEqual(restaurant.restaurant.name, "Dastak Cafe")

        _ = try await client.submit(
            DastakV1OrderSubmission(
                deliveryAddress: DastakV1DeliveryAddressInput(
                    label: "Home", line1: "1 Launch Road", line2: nil,
                    landmark: nil, city: "Vaniyambadi", state: "Tamil Nadu",
                    postalCode: "635751", latitude: 12.6819, longitude: 78.6201,
                    instructions: nil
                ),
                recipient: DastakV1RecipientInput(
                    name: "Launch Customer", phoneNumber: "+919700000002"
                ),
                restaurantBranchID: restaurant.restaurant.branchID,
                lines: [
                    DastakV1OrderLineInput(skuID: skuID, quantity: 1),
                    DastakV1OrderLineInput(menuItemID: item.id, optionIDs: [option.id], quantity: 2),
                ]
            ),
            idempotencyKey: try XCTUnwrap(IdempotencyKey(rawValue: "mixed-submit"))
        )
        let recorded = await functions.lastCall()
        let call = try XCTUnwrap(recorded)
        let source = String(decoding: call.body, as: UTF8.self)
        XCTAssertTrue(source.contains(#""restaurantBranchId""#))
        XCTAssertTrue(source.contains(#""lineType":"FOOD_MENU_ITEM""#))
        XCTAssertTrue(source.contains(#""optionIds""#))
        XCTAssertFalse(source.contains("pricePaise"))
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
        XCTAssertEqual(request?["supportsConfirmedCancellation"] as? Bool, true)
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

    func testOrderDecodesParentDeliveryCodeWithoutMerchantIdentityOrRecipientAccount() throws {
        var source = try XCTUnwrap(JSONSerialization.jsonObject(with: orderJSON) as? [String: Any])
        source["status"] = "OUT_FOR_DELIVERY"
        source["customerState"] = "ON_THE_WAY"
        source["delivery"] = [
            "state": "ON_THE_WAY",
            "verificationStatus": "ACTIVE",
            "deliveryCode": "654321",
            "riderArrivedAt": NSNull(),
            "outForDeliveryAt": "2026-08-22T10:20:00Z",
            "deliveredAt": NSNull(),
            "recipientAccountRequired": false,
            "riderLocation": ["latitude": 12.6822, "longitude": 78.6210],
            "riderLocationUpdatedAt": "2026-08-22T10:21:00Z",
            "distanceToDestinationMeters": 640,
        ]

        let data = try JSONSerialization.data(withJSONObject: source)
        let order = try JSONDecoder().decode(DastakV1OrderSnapshot.self, from: data)

        XCTAssertEqual(order.status, .outForDelivery)
        XCTAssertEqual(order.delivery?.deliveryCode, "654321")
        XCTAssertEqual(order.delivery?.verificationStatus, .active)
        XCTAssertEqual(order.delivery?.recipientAccountRequired, false)
        XCTAssertEqual(order.delivery?.riderLocation?.latitude, 12.6822)
        XCTAssertEqual(order.delivery?.distanceToDestinationMeters, 640)
        XCTAssertEqual(order.deliveryAddress?.instructions, "Ring once")
        XCTAssertEqual(order.recipient?.name, "Launch Customer")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("merchant"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("branch"))
    }

    func testOrderDecodesPreparationETAAndCustomerVisibleRestaurantSelections() throws {
        var source = try XCTUnwrap(JSONSerialization.jsonObject(with: orderJSON) as? [String: Any])
        source["orderType"] = "MIXED"
        source["status"] = "PREPARING"
        source["fulfilmentProgress"] = [
            "state": "PREPARING",
            "estimatedReadyAt": "2026-08-22T10:30:00Z",
            "runningLate": false,
        ]
        source["restaurant"] = [
            "organizationId": "77777777-7777-4777-8777-777777777777",
            "branchId": "88888888-8888-4888-8888-888888888888",
            "name": "Dastak Cafe",
            "branchName": "Main Road",
            "imageKey": NSNull(),
        ]
        var lines = try XCTUnwrap(source["lines"] as? [[String: Any]])
        lines.append([
            "id": "99999999-9999-4999-8999-999999999999",
            "lineType": "FOOD_MENU_ITEM",
            "menuItemId": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "name": "Filter Coffee",
            "quantity": 1,
            "unitPricePaise": 5000,
            "lineTotalPaise": 5000,
            "status": "ORDERED",
            "foodSelection": [
                "options": [[
                    "id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                    "groupId": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                    "groupName": "Size",
                    "name": "Large",
                    "priceDeltaPaise": 500,
                ]],
            ],
        ])
        source["lines"] = lines

        let data = try JSONSerialization.data(withJSONObject: source)
        let order = try JSONDecoder().decode(DastakV1OrderSnapshot.self, from: data)

        XCTAssertEqual(order.fulfilmentProgress?.estimatedReadyAt, "2026-08-22T10:30:00Z")
        XCTAssertEqual(order.fulfilmentProgress?.runningLate, false)
        XCTAssertEqual(order.restaurant?.name, "Dastak Cafe")
        XCTAssertEqual(order.lines.last?.foodSelection?.options.first?.name, "Large")
    }

    func testIssueReportCarriesOptionalImmutableEvidenceWithoutFinancialInput() async throws {
        let functions = RecordingV1FunctionClient()
        let client = SupabaseDastakV1CustomerClient(functions: functions)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "issue-1"))
        let evidencePath = "customer-issue/\(orderID.uuidString.lowercased())/photo.jpg"

        let result = try await client.reportIssue(
            orderID: orderID,
            orderLineID: lineID,
            category: .damaged,
            description: "  The package seal was damaged.  ",
            objectPath: evidencePath,
            contentType: "image/jpeg",
            idempotencyKey: key
        )

        XCTAssertEqual(result.issueID, subcategoryID)
        let recorded = await functions.lastCall()
        let call = try XCTUnwrap(recorded)
        let request = try XCTUnwrap(
            JSONSerialization.jsonObject(with: call.body) as? [String: Any]
        )
        XCTAssertEqual(request["operation"] as? String, "reportCustomerIssue")
        XCTAssertEqual(request["description"] as? String, "The package seal was damaged.")
        XCTAssertEqual(request["objectPath"] as? String, evidencePath)
        XCTAssertEqual(request["contentType"] as? String, "image/jpeg")
        XCTAssertNil(request["refundAmountPaise"])
        XCTAssertNil(request["merchantId"])
    }

    func testOrderDecodesRecoveryReturnAndOriginalMethodRefundWithoutMerchantIdentity() throws {
        var source = try XCTUnwrap(JSONSerialization.jsonObject(with: orderJSON) as? [String: Any])
        source["support"] = [
            "canReportIssue": true,
            "recovery": [[
                "id": categoryID.uuidString,
                "type": "EXACT_SKU",
                "status": "RECOVERED",
                "orderLineId": lineID.uuidString,
                "openedAt": "2026-08-22T10:03:00Z",
                "resolvedAt": "2026-08-22T10:04:00Z",
                "customerMessage": "We secured the exact item.",
            ]],
            "issues": [],
            "returns": [[
                "id": subcategoryID.uuidString,
                "source": "CUSTOMER_ISSUE",
                "status": "CUSTOMER_PICKUP",
                "physicalReturnRequired": true,
                "reason": "Approved return",
                "requestedAt": "2026-08-22T10:05:00Z",
                "completedAt": NSNull(),
                "packageCount": 1,
                "mission": [
                    "id": skuID.uuidString,
                    "status": "ASSIGNED",
                    "assignedAt": "2026-08-22T10:06:00Z",
                    "arrivedCustomerAt": NSNull(),
                    "pickupCompletedAt": NSNull(),
                    "completedAt": NSNull(),
                    "pickupVerificationStatus": "ACTIVE",
                    "pickupCode": "123456",
                ],
            ]],
            "refunds": [[
                "id": categoryID.uuidString,
                "orderLineId": lineID.uuidString,
                "status": "PROCESSING",
                "destination": "ORIGINAL_PAYMENT_METHOD",
                "amountPaise": 900,
                "currency": "INR",
                "reason": "Approved return",
                "createdAt": "2026-08-22T10:07:00Z",
                "completedAt": NSNull(),
            ]],
        ]

        let data = try JSONSerialization.data(withJSONObject: source)
        let order = try JSONDecoder().decode(DastakV1OrderSnapshot.self, from: data)

        XCTAssertEqual(order.support?.recovery.first?.customerMessage, "We secured the exact item.")
        XCTAssertEqual(order.support?.returns.first?.mission?.pickupCode, "123456")
        XCTAssertEqual(order.support?.refunds.first?.destination, "ORIGINAL_PAYMENT_METHOD")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("merchantId"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("branchId"))
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
        let response: Data
        switch operation {
        case "customerCatalogue": response = catalogueJSON
        case "customerRestaurants": response = restaurantJSON
        case "reportCustomerIssue": response = issueResultJSON
        default: response = orderJSON
        }
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
  "categoryTypes":[{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Dairy, Bread & Eggs","slug":"dairy-bread-eggs","imageKey":null,"previewImageKeys":["catalogue/milk.webp"],"navigationSection":{"key":"grocery-kitchen","name":"Grocery & Kitchen","sortOrder":10},"sortOrder":1}],
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

private let restaurantJSON = """
{
  "restaurants":[{
    "restaurant":{
      "organizationId":"77777777-7777-4777-8777-777777777777",
      "branchId":"88888888-8888-4888-8888-888888888888",
      "name":"Dastak Cafe","branchName":"Main Road","imageKey":null,
      "description":"Fresh food","serviceZoneId":null,
      "acceptingOrders":true,"isOpen":true,"operationalVersion":1,
      "branchStatus":"ACTIVE","merchantType":"RESTAURANT_CAFE",
      "softActiveOrderThreshold":5,"activeOrderCount":6
    },
    "categories":[{
      "id":"11111111-1111-4111-8111-111111111111","name":"Drinks","description":null,
      "sortOrder":1,"status":"ACTIVE","version":1,
      "items":[{
        "id":"99999999-9999-4999-8999-999999999999","name":"Filter Coffee",
        "description":null,"imageKey":null,"basePricePaise":4500,"currencyCode":"INR",
        "taxRateBps":0,"logisticsAttributes":{},"status":"ACTIVE","version":1,
        "optionGroups":[{
          "id":"22222222-2222-4222-8222-222222222222","name":"Size","selectionType":"SINGLE",
          "minimumSelections":1,"maximumSelections":1,"sortOrder":1,
          "status":"ACTIVE","version":1,
          "options":[{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Large","priceDeltaPaise":500,"sortOrder":1,"status":"ACTIVE","version":1}]
        }]
      }]
    }]
  }]
}
""".data(using: .utf8)!

private let orderJSON = """
{
  "id":"\(orderID)","displayOrderNumber":"DSK-260822-00000001","orderType":"RETAIL_ONLY",
  "status":"MATCHING","version":2,"fulfilmentProgress":{"state":"FINDING_ITEMS"},
  "deliveryAddress":{"label":"Home","line1":"1 Launch Road","line2":null,"landmark":null,"city":"Vaniyambadi","state":"Tamil Nadu","postalCode":"635751","countryCode":"IN","latitude":12.6819,"longitude":78.6201,"instructions":"Ring once"},
  "recipient":{"name":"Launch Customer","phoneNumber":"+919700000002"},
  "price":{"snapshotKind":"SUBMITTED","subtotalPaise":13800,"deliveryFeePaise":0,"platformFeePaise":0,"discountPaise":0,"taxPaise":0,"totalPaise":13800,"currencyCode":"INR"},
  "lines":[{"id":"\(lineID)","lineType":"RETAIL_SKU","skuId":"\(skuID)","name":"Whole Milk","variant":"Full cream","packSize":"1 litre","quantity":2,"unitPricePaise":6900,"lineTotalPaise":13800,"status":"ORDERED"}],
  "submittedAt":"2026-08-22T10:00:00Z","fullySecuredAt":null,"paymentExpiresAt":null,"paidAt":null,"deliveredAt":null,
  "createdAt":"2026-08-22T10:00:00Z","updatedAt":"2026-08-22T10:00:00Z"
}
""".data(using: .utf8)!

private let issueResultJSON = """
{
  "issueId":"\(subcategoryID)","orderId":"\(orderID)","orderLineId":"\(lineID)",
  "category":"DAMAGED","status":"OPEN","reportedAt":"2026-08-22T10:20:00Z",
  "evidenceId":"\(categoryID)"
}
""".data(using: .utf8)!
