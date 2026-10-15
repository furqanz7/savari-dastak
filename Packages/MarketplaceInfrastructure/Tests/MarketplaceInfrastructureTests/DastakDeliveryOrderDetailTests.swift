import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure

final class DastakDeliveryOrderDetailTests: XCTestCase {
    func testOfferStopsDecodeWithoutAcceptedMissionCustodyFieldsOrCoordinates() throws {
        let value = Data("""
        {"id":"\(detailID)","missionId":"\(detailID)","displayOrderNumber":"DSK-TEST","transportType":"MOTORBIKE","distanceMeters":500,"respondBy":"2099-01-01T00:00:00Z","secondsRemaining":45,"pickupCount":1,
        "orderLoad":{"totalWeightGrams":2500,"totalVolumeCubicMillimetres":9000000,"longestSideMillimetres":250,"containsBulky":false,"eligibleTransportTypes":["MOTORBIKE"]},
        "pickupStops":[{"id":"\(detailID)","sequence":1,"ready":true,"branch":{"displayName":"Merchant","address":{"line1":"Store Road"}}}]}
        """.utf8)
        let offer = try JSONDecoder().decode(DastakV1RiderOffer.self, from: value)
        XCTAssertEqual(offer.pickupStops?.first?.branch.address.display, "Store Road")
        XCTAssertEqual(offer.orderLoad?.totalWeightGrams, 2500)
    }
    func testFullOrderUsesWorkIdentityAndDecodesActiveAndTerminalContracts() async throws {
        let functions = DetailFunctions()
        let client = DastakDeliveryOrderDetailClient(functions: functions)
        let result = try await client.detail(kind: "V1_DELIVERY", workID: detailID)
        XCTAssertEqual(result.order.lines.first?.name, "Milk")
        XCTAssertEqual(result.pickupStops.first?.address, "Store Road")
        XCTAssertEqual(result.order.price.totalPaise, 6426)
        let body = await functions.body
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(body)) as? [String: String])
        XCTAssertEqual(request["operation"], "partnerOrderDetail")
        XCTAssertEqual(request["workId"]?.lowercased(), detailID.uuidString.lowercased())
        XCTAssertNil(request["accountId"])
    }
    func testWrongWorkAndTerminalContactLeakAreRejected() async throws {
        let functions = DetailFunctions()
        for value in [detailFixture().replacingDetail("\"terminal\":false", "\"terminal\":true"),
                      detailFixture().replacingDetail("\"totalPaise\":6426", "\"totalPaise\":-1")] {
            await functions.reply(value)
            do { _ = try await DastakDeliveryOrderDetailClient(functions: functions).detail(kind: "V1_DELIVERY", workID: detailID); XCTFail("Must reject") } catch {}
        }
        await functions.reply(detailFixture())
        do { _ = try await DastakDeliveryOrderDetailClient(functions: functions).detail(kind: "V1_DELIVERY", workID: UUID()); XCTFail("Must bind work identity") } catch {}
    }
    func testDeliveryMutationsDisableInvisibleTransportRetries() {
        let request = DastakDeliveryActionRequest(operation: "v1VerifyPickup", missionId: detailID, verificationCode: "123456")
        XCTAssertFalse(request.allowsAutomaticRetries)
        XCTAssertFalse(DastakDeliveryPayoutRequest(subjectID: detailID, amountPaise: 500).allowsAutomaticRetries)
    }
}
private let detailID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private actor DetailFunctions: FunctionClient {
    var body: Data?
    var data = detailFixture()
    func reply(_ data: Data) { self.data = data }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        body = try JSONEncoder().encode(request)
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
private func detailFixture() -> Data {
    Data("""
    {"kind":"V1_DELIVERY","workId":"\(detailID)","missionStatus":"ARRIVED","terminal":false,
    "order":{"id":"\(detailID)","displayOrderNumber":"DSK-TEST","orderType":"RETAIL","status":"OUT_FOR_DELIVERY","version":2,
    "createdAt":"2026-10-15T00:00:00Z","updatedAt":"2026-10-15T00:05:00Z",
    "recipient":{"name":"Recipient","phoneNumber":"+919700000001"},
    "lines":[{"id":"\(detailID)","lineType":"SKU","name":"Milk","quantity":2,"packSize":"500 ml","unitPricePaise":2400,"lineTotalPaise":4800,"status":"SECURED"}],
    "price":{"snapshotKind":"FINAL_PAYABLE","subtotalPaise":4800,"deliveryFeePaise":1500,"platformFeePaise":126,"discountPaise":0,"taxPaise":0,"totalPaise":6426,"currencyCode":"INR"}},
    "pickupStops":[{"id":"\(detailID)","sequence":1,"name":"Merchant","address":"Store Road","packageCount":1}]}
    """.utf8)
}
private extension Data {
    func replacingDetail(_ old: String, _ new: String) -> Data { Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8) }
}
