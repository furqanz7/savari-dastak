import MarketplaceFoundation
import XCTest

@testable import MarketplaceInfrastructure

final class DastakReviewDemoTests: XCTestCase, @unchecked Sendable {
  private func key() -> IdempotencyKey { .init(rawValue: UUID().uuidString)! }
  private func submit(
    _ demo: DastakReviewDemoClient, food: Bool = false, key: IdempotencyKey? = nil
  ) async throws -> DastakV1OrderSnapshot {
    let client = SupabaseDastakV1CustomerClient(functions: demo)
    let line =
      food
      ? DastakV1OrderLineInput(
        menuItemID: UUID(uuidString: "de000000-0000-4000-8000-000000000103")!, optionIDs: [],
        quantity: 1)
      : .init(skuID: UUID(uuidString: "de000000-0000-4000-8000-000000000020")!, quantity: 2)
    return try await client.submit(
      .init(
        deliveryAddress: .init(
          label: "Sample", line1: "24 Sample Street", line2: nil, landmark: nil,
          city: "Vaniyambadi", state: nil, postalCode: nil, latitude: 12.6819, longitude: 78.6201,
          instructions: nil), recipient: .init(name: "Sample", phoneNumber: "+12025550123"),
        restaurantBranchID: food ? UUID(uuidString: "de000000-0000-4000-8000-000000000101") : nil,
        lines: [line]), idempotencyKey: key ?? self.key())
  }
  func testGroceryAndFoodRemainPreparingUntilExplicitMerchantProgress() async throws {
    for food in [false, true] {
      let demo = DastakReviewDemoClient()
      let client = SupabaseDastakV1CustomerClient(functions: demo)
      let initial = try await submit(demo, food: food)
      XCTAssertEqual(initial.status, .awaitingPayment)
      XCTAssertEqual(initial.launchPayment?.state, .readyToConfirm)
      let order = try await client.commitLaunchPayment(
        id: initial.id, expectedVersion: initial.version, idempotencyKey: key())
      XCTAssertEqual(order.status, .preparing)
      XCTAssertEqual(order.fulfilmentProgress?.state, "PREPARING")
      let delivery = SupabaseDastakV1DeliveryClient(functions: demo)
      let before = try await delivery.snapshot(idempotencyKey: key())
      XCTAssertNil(before.offer)
      await demo.advanceMerchant()
      let after = try await delivery.snapshot(idempotencyKey: key())
      XCTAssertNotNil(after.offer)
      XCTAssertTrue(after.deliveryLaneCurrent)
      XCTAssertTrue(after.returnLaneCurrent)
      let addresses = try await SupabaseCustomerAddressClient(functions: demo).snapshot(
        idempotencyKey: key())
      let address = try XCTUnwrap(addresses.addresses.first)
      let context = DastakV1AreaContext(addressID: address.id, addressVersion: address.updatedAt)
      let area = try await client.areaAvailability(context: context, idempotencyKey: key())
      XCTAssertEqual(
        area.quantity(for: UUID(uuidString: "de000000-0000-4000-8000-000000000024")!), 0)
      _ = try await client.restaurantAreaPage(context: context, cursor: nil, idempotencyKey: key())
      _ = try await client.checkoutQuote(
        context: context,
        lines: [
          .init(skuID: UUID(uuidString: "de000000-0000-4000-8000-000000000020")!, quantity: 1)
        ], branchID: nil, idempotencyKey: key())
    }
  }

  func testDeliveryHappyPathRequiresPickupPINHandoffPhotoAndCollection() async throws {
    let demo = DastakReviewDemoClient()
    let customer = SupabaseDastakV1CustomerClient(functions: demo)
    let initial = try await submit(demo)
    _ = try await customer.commitLaunchPayment(
      id: initial.id, expectedVersion: initial.version, idempotencyKey: key())
    await demo.advanceMerchant()
    let delivery = SupabaseDastakV1DeliveryClient(functions: demo)
    let offered = try await delivery.snapshot(idempotencyKey: key())
    let offer = try XCTUnwrap(offered.offer)
    var snapshot = try await delivery.accept(offerID: offer.id, idempotencyKey: key())
    XCTAssertEqual(snapshot.currentMission?.status, .assigned)
    let missionID = try XCTUnwrap(snapshot.currentMission?.id)
    let stopID = try XCTUnwrap(snapshot.currentMission?.pickupStops.first?.id)
    for operation in [
      "v1StartPickups", "v1ArriveAtPickup", "v1VerifyPickup", "v1StartFinalDelivery",
      "v1ArriveAtCustomer",
    ] {
      snapshot = try await delivery.advance(
        operation: operation, missionID: missionID,
        stopID: operation.contains("Pickup") && operation != "v1StartPickups" ? stopID : nil,
        accountedPackageCount: operation == "v1VerifyPickup" ? 1 : nil,
        verificationCode: operation == "v1VerifyPickup" ? "123456" : nil, reason: nil,
        idempotencyKey: key())
      XCTAssertTrue(snapshot.deliveryLaneCurrent)
    }
    XCTAssertEqual(snapshot.currentMission?.status, .arrived)
    XCTAssertEqual(snapshot.currentMission?.canCompleteDelivery, false)
    snapshot = try await delivery.advance(
      operation: "v1VerifyCustomerPIN", missionID: missionID, verificationCode: "123456",
      idempotencyKey: key())
    struct Evidence: Encodable, Sendable {
      let operation = "v1AddDeliveryEvidence"
      let objectPath = "demo/sample.jpg"
    }
    snapshot = try await demo.invoke("courier-dispatch", request: Evidence(), idempotencyKey: key())
    XCTAssertEqual(snapshot.currentMission?.canCompleteDelivery, false)
    snapshot = try await delivery.recordCollection(
      missionID: missionID, outcome: .collected, method: .cash, reference: nil, failureReason: nil,
      expectedMissionVersion: try XCTUnwrap(snapshot.currentMission?.version), idempotencyKey: key()
    )
    XCTAssertEqual(snapshot.currentMission?.canCompleteDelivery, true)
    snapshot = try await delivery.advance(
      operation: "v1CompleteDelivery", missionID: missionID, idempotencyKey: key())
    XCTAssertNil(snapshot.currentMission)
    XCTAssertEqual(snapshot.completedMission?.status, "DELIVERED")
    XCTAssertTrue(snapshot.completedLaneCurrent)
    let final = try await customer.order(id: initial.id, idempotencyKey: key())
    XCTAssertEqual(final.status, .delivered)
    let detail = try await DastakDeliveryOrderDetailClient(functions: demo).detail(
      kind: "V1_DELIVERY", workID: missionID)
    XCTAssertTrue(detail.terminal)
    XCTAssertNil(detail.order.recipient)
    XCTAssertNil(detail.order.deliveryAddress)
  }

  func testUnknownRequestsFailClosedAndSessionsAreIndependent() async throws {
    let first = DastakReviewDemoClient()
    let second = DastakReviewDemoClient()
    XCTAssertTrue(first.services.isDemonstration)
    _ = try await submit(first)
    let orders = try await SupabaseDastakV1CustomerClient(functions: second).orders(
      limit: 20, cursor: nil, idempotencyKey: key())
    XCTAssertTrue(orders.orders.isEmpty)
    struct Request: Encodable, Sendable { let operation = "requestRoyaltyWithdrawal" }
    struct Reply: Decodable, Sendable {}
    do {
      let _: Reply = try await first.invoke("earnings", request: Request(), idempotencyKey: key())
      XCTFail("Demo must never dispatch a real withdrawal")
    } catch let FunctionClientError.api(statusCode, code, _) {
      XCTAssertEqual(statusCode, 403)
      XCTAssertEqual(code, "DEMO_ISOLATED")
    }
  }
  func testIdempotentSubmitAndCancellation() async throws {
    let demo = DastakReviewDemoClient()
    let requestKey = key()
    let first = try await submit(demo, key: requestKey)
    let replay = try await submit(demo, key: requestKey)
    XCTAssertEqual(first.id, replay.id)
    let customer = SupabaseDastakV1CustomerClient(functions: demo)
    let cancelled = try await customer.cancel(
      id: first.id, expectedVersion: first.version, idempotencyKey: key())
    XCTAssertEqual(cancelled.status, .cancelled)
    let collection = try await customer.orders(limit: 20, cursor: nil, idempotencyKey: key())
    XCTAssertEqual(collection.orders.count, 1)
  }
}
