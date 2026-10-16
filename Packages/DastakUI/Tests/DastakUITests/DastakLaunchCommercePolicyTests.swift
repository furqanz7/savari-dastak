import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakLaunchCommercePolicyTests: XCTestCase {
    func testLaunchNeverOffersLegacyOnlinePaymentEvenWhenServerAllowsIt() {
        XCTAssertFalse(DastakLaunchCommercePolicy.canRetryLegacyPayment(serverAllows: true))
        XCTAssertFalse(DastakLaunchCommercePolicy.canRetryLegacyPayment(serverAllows: false))
    }

    func testLegacyOrderRetryDoesNotCreateCheckoutOrSendRequest() async throws {
        let functions = LaunchPaymentRequestSpy()
        let model = DastakCustomerModel(functions: functions)
        let order = try JSONDecoder().decode(MerchantOrderSnapshot.self, from: Data(#"""
        {"orderId":"00000000-0000-4000-8000-000000000001",
         "storeId":"00000000-0000-4000-8000-000000000002",
         "status":"payment_pending","paymentState":"payment_pending","lines":[],
         "itemSubtotal":{"paise":100},"deliveryFee":{"paise":0},
         "deliveryDistanceMeters":0,"total":{"paise":100},
         "dropoff":{"latitude":12.68,"longitude":78.62},"stateVersion":1,
         "createdAt":"2026-10-17T00:00:00Z","updatedAt":"2026-10-17T00:00:00Z"}
        """#.utf8))
        await model.retryPayment(for: order)
        XCTAssertNil(model.checkoutSession)
        XCTAssertFalse(model.isCheckingOut)
        XCTAssertEqual(model.ordersActionMessage, DastakLaunchCommercePolicy.onlinePaymentUnavailableMessage)
        let requests = await functions.count
        XCTAssertEqual(requests, 0)
    }

    func testLegacyParcelRetryDoesNotCreateCheckoutOrSendRequest() async throws {
        let functions = LaunchPaymentRequestSpy()
        let model = DastakCustomerModel(functions: functions)
        let parcel = try JSONDecoder().decode(CustomerParcelDelivery.self, from: Data(#"""
        {"parcelId":"00000000-0000-4000-8000-000000000003",
         "audience":"sender","status":"payment_pending","paymentStatus":"pending",
         "refundStatus":"not_requested","deliveryMethod":"bike",
         "pickup":{"latitude":12.68,"longitude":78.62,"address":"Sample pickup"},
         "dropoff":{"latitude":12.69,"longitude":78.63,"address":"Sample dropoff"},
         "recipient":{"name":"Sample","phoneNumber":"+919999999999"},
         "declaredContents":"Sample","declaredValue":{"paise":100},
         "deliveryFee":{"paise":100},"courierPayout":{"paise":100}}
        """#.utf8))
        await model.retryPayment(for: parcel)
        XCTAssertNil(model.checkoutSession)
        XCTAssertFalse(model.isCheckingOut)
        XCTAssertEqual(model.ordersActionMessage, DastakLaunchCommercePolicy.onlinePaymentUnavailableMessage)
        let requests = await functions.count
        XCTAssertEqual(requests, 0)
    }

    func testParcelBookingCannotCreateAnOrderBeforeDiscoveringOnlinePaymentIsUnavailable() async {
        let functions = LaunchPaymentRequestSpy()
        let model = DastakCustomerModel(functions: functions)
        let parcel = await model.createParcelAndCheckout(
            recipientName: "Sample", recipientPhoneNumber: "+919999999999",
            declaredContents: "Sample", declaredValuePaise: 100
        )
        XCTAssertNil(parcel)
        XCTAssertNil(model.checkoutSession)
        XCTAssertEqual(model.parcelErrorMessage, "Parcel booking is not available in this release.")
        let requests = await functions.count
        XCTAssertEqual(requests, 0)
    }
}

private actor LaunchPaymentRequestSpy: FunctionClient {
    private(set) var count = 0
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        count += 1
        throw FunctionClientError.invalidResponse
    }
}
