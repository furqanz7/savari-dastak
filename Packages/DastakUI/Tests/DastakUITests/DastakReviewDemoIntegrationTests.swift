import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest

@testable import DastakUI

@MainActor final class DastakReviewDemoIntegrationTests: XCTestCase {
  func testCustomerAndDeliveryUseExistingModelsWithMemoryOnlyJournals() async throws {
    let demo = DastakReviewDemoClient()
    let suite = "dastak.demo.test." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let services = demo.services
    let customer = DastakCustomerModel(
      functions: demo, checkoutCustomerProvider: services.checkoutCustomer,
      accountIDProvider: services.accountID, basketDefaults: defaults,
      checkoutJournalStorage: DastakDemoCheckoutStorage(), demonstration: true)
    await customer.bootstrap()
    XCTAssertTrue(customer.isCartStorageReady)
    XCTAssertNil(customer.cartErrorMessage)
    XCTAssertNotNil(customer.currentAreaAvailability)
    XCTAssertFalse(
      customer.v1Restaurants.isEmpty,
      customer.v1RestaurantsRefreshFailure?.message ?? "Missing sample Food")
    let product = try XCTUnwrap(customer.v1Catalogue?.skus.first)
    customer.pickUpBasket(.grocery)
    customer.addToCart(product)
    let placed = await customer.submitV1Order()
    XCTAssertTrue(placed, customer.v1OrderErrorMessage ?? "Sample checkout failed")
    let order = try XCTUnwrap(customer.activeV1Order)
    let client = SupabaseDastakV1CustomerClient(functions: demo)
    _ = try await client.commitLaunchPayment(
      id: order.id, expectedVersion: order.version, idempotencyKey: key())
    await demo.advanceMerchant()
    let ops = DastakDeliveryOperations(services: services, storage: DastakDemoDeliveryStorage())
    let delivery = DastakDeliveryPartnerModel(functions: demo, operations: ops)
    await ops.restore()
    await delivery.bootstrap()
    XCTAssertNil(delivery.refreshFailure)
    XCTAssertTrue(delivery.v1Current)
    XCTAssertFalse(ops.blocksActions)
    let offer = try XCTUnwrap(delivery.v1Dispatch?.offer)
    await ops.submitOffer(offer, accept: true)
    XCTAssertNil(ops.pending, ops.message ?? "Offer blocked")
    await delivery.actionFinished()
    var mission = try XCTUnwrap(delivery.v1Dispatch?.currentMission)
    for operation: DastakDeliveryCommand.Operation in [
      .start, .arrivePickup, .verifyPickup, .startFinal, .arriveDelivery, .verifyPIN,
      .deliveryEvidence, .collection, .complete,
    ] {
      await ops.submitDelivery(
        operation, mission: mission,
        stopID: [.arrivePickup, .verifyPickup].contains(operation)
          ? mission.pickupStops.first?.id : nil,
        packageCount: operation == .verifyPickup ? 1 : nil,
        code: [.verifyPickup, .verifyPIN].contains(operation) ? "123456" : nil,
        photo: operation == .deliveryEvidence ? Data([1, 2, 3]) : nil,
        contentType: operation == .deliveryEvidence ? "image/jpeg" : nil,
        outcome: operation == .collection ? .collected : nil,
        method: operation == .collection ? .cash : nil)
      XCTAssertNil(ops.pending, "\(operation): \(ops.message ?? "")")
      XCTAssertFalse(ops.blocksActions, "\(operation)")
      await delivery.actionFinished()
      if operation != .complete { mission = try XCTUnwrap(delivery.v1Dispatch?.currentMission) }
    }
    XCTAssertNil(delivery.v1Dispatch?.currentMission)
    await ops.refreshHistory()
    XCTAssertTrue(ops.historyCurrent)
    XCTAssertEqual(ops.history.count, 1)
    await customer.refreshV1Orders()
    XCTAssertEqual(customer.v1Orders.first?.status, .delivered)
    let assigned = await demo.assignSampleReturn()
    XCTAssertTrue(assigned)
    let dispatchClient = SupabaseDastakV1DeliveryClient(functions: demo)
    var returned = try await dispatchClient.snapshot(idempotencyKey: key())
    XCTAssertTrue(returned.returnLaneCurrent)
    for operation: DastakDeliveryCommand.Operation in [
      .arriveCustomer, .evidence, .pickup, .arriveStop, .receipt,
    ] {
      ops.adopt(returned, authoritative: true)
      let mission = try XCTUnwrap(returned.returnMission, "\(operation)")
      XCTAssertTrue(mission.isValid)
      await ops.submitReturn(
        operation, mission: mission,
        stopID: [.arriveStop, .receipt].contains(operation) ? mission.stops.first?.id : nil,
        confirmed: true, code: [.pickup, .receipt].contains(operation) ? "123456" : nil,
        photo: operation == .evidence ? Data([1, 2, 3]) : nil,
        contentType: operation == .evidence ? "image/jpeg" : nil)
      XCTAssertNil(ops.pending, "\(operation): \(ops.message ?? "")")
      returned = try await dispatchClient.snapshot(idempotencyKey: key())
    }
    XCTAssertNil(returned.returnMission)
    await ops.refreshHistory()
    XCTAssertEqual(ops.history.first?.outcome, "RETURNED")
  }
  func testDemoImagesResolveOnlyInsideBundle() throws {
    let known = DastakArtworkURLFactory.request(
      for: "review-demo/rice.png", baseURLString: "https://production.invalid")
    XCTAssertEqual(known?.originalURL.isFileURL, true)
    XCTAssertNil(
      DastakArtworkURLFactory.request(
        for: "review-demo/missing.png", baseURLString: "https://production.invalid"))
    XCTAssertNil(
      DastakArtworkURLFactory.request(
        for: "review-demo/../rice.png", baseURLString: "https://production.invalid"))
  }
  private func key() -> IdempotencyKey { .init(rawValue: UUID().uuidString)! }
}
