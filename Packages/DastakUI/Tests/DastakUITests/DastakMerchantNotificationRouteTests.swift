import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantNotificationRouteTests: XCTestCase {
    private func payload(_ type: String = "merchant.rider_arrived") -> [AnyHashable: Any] {
        ["notificationType": type, "entityType": "dastakV1Order", "entityId": routeOrder.uuidString,
         "orderId": routeOrder.uuidString, "pickupCode": "PRIVATE_SECRET", "branchId": UUID().uuidString]
    }
    private func route(_ type: String = "merchant.rider_arrived") -> DastakMerchantNotificationRoute {
        DastakMerchantNotificationRoute.parse(payload(type))!
    }
    func testEightMerchantRoutesParseAndSelectExpectedQueue() {
        let types: [(String, DastakMerchantQueue)] = [
            ("merchant.opportunity", .incoming), ("merchant.restaurant_request", .incoming),
            ("merchant.recovery_opportunity", .incoming), ("merchant.preparation_started", .all),
            ("merchant.rider_assigned", .all), ("merchant.rider_arrived", .all),
            ("merchant.return_incoming", .returns), ("merchant.order_cancelled", .history)
        ]
        for (type, queue) in types { XCTAssertEqual(route(type).queue, queue) }
    }
    func testOtherRolesMalformedIDsAndConflictingIdentityFailClosed() {
        for patch: [AnyHashable: Any] in [
            ["notificationType": "customer.delivered"], ["notificationType": "rider.assigned"],
            ["notificationType": "merchant.invented"], ["entityType": "delivery"], ["orderId": "bad"],
            ["entityId": UUID().uuidString], ["orderId": 123], ["entityId": 123]
        ] {
            XCTAssertNil(DastakMerchantNotificationRoute.parse(payload().merging(patch) { _, next in next }))
        }
    }
    func testColdLaunchHintIsConsumedOnceAndContainsNoPrivatePayload() throws {
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let inbox = DastakMerchantNotificationInbox(defaults: defaults)
        XCTAssertTrue(inbox.receive(payload: payload(), identifier: "alert-1"))
        let stored = try XCTUnwrap(defaults.data(forKey: "dastak.merchant.pendingNotification.v1"))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("PRIVATE_SECRET"))
        let restored = DastakMerchantNotificationInbox(defaults: defaults)
        XCTAssertEqual(restored.take()?.orderID, routeOrder); XCTAssertNil(restored.take())
        XCTAssertFalse(inbox.receive(payload: payload(), identifier: "alert-1"))
        XCTAssertTrue(inbox.receive(payload: payload(), identifier: "alert-2"))
    }
    func testExpiredAndCorruptDiskHintsAreRemovedWithoutOpening() {
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let inbox = DastakMerchantNotificationInbox(defaults: defaults), now = Date()
        XCTAssertTrue(inbox.receive(payload: payload(), identifier: "old", now: now.addingTimeInterval(-86_401)))
        XCTAssertNil(inbox.take(now: now))
        defaults.set(Data("broken".utf8), forKey: "dastak.merchant.pendingNotification.v1")
        XCTAssertNil(inbox.take()); XCTAssertNil(defaults.data(forKey: "dastak.merchant.pendingNotification.v1"))
    }
    func testFulfilmentLookupOnlyOffersExactOrderAndAuthorizedReadLocations() async {
        let functions = RouteFunctions(), navigator = model(functions)
        await navigator.open(route())
        XCTAssertEqual(navigator.choices.count, 2)
        XCTAssertEqual(Set(navigator.choices.map { $0.target.branchID }), [routeBranch, routeBranch2])
        XCTAssertTrue(navigator.choices.allSatisfy { $0.target.kind == .fulfilment })
        XCTAssertFalse(navigator.loading)
        let calls = await functions.calls
        XCTAssertEqual(Set(calls), ["merchantFulfilments", "restaurantRequests"])
    }
    func testFoodRecoveryAndReturnAlertsResolveTheirOwnRecordKind() async {
        let functions = RouteFunctions(), navigator = model(functions)
        for (type, kind) in [("merchant.restaurant_request", DastakMerchantDetailTarget.Kind.restaurantRequest),
                             ("merchant.recovery_opportunity", .recovery), ("merchant.return_incoming", .returned)] {
            await navigator.open(route(type))
            XCTAssertEqual(navigator.choices.count, 1)
            XCTAssertEqual(navigator.choices.first?.target.kind, kind)
            XCTAssertEqual(navigator.choices.first?.target.branchID, routeBranch)
        }
    }
    func testUnresolvedOrExpiredRetailOfferIsAnExplicitQueueFallbackNotAGuess() async {
        let functions = RouteFunctions(); await functions.empty()
        let navigator = model(functions)
        await navigator.open(route("merchant.opportunity"))
        XCTAssertTrue(navigator.choices.isEmpty)
        XCTAssertTrue(navigator.message?.contains("may have expired") == true)
        XCTAssertEqual(navigator.route?.queue, .incoming)
    }
    func testPartialTransportFailureRetainsOnlySuccessfulReadMatches() async {
        let functions = RouteFunctions(); await functions.fail("restaurantRequests", status: nil)
        let navigator = model(functions)
        await navigator.open(route())
        XCTAssertEqual(navigator.choices.count, 2)
        XCTAssertTrue(navigator.message?.contains("Some records") == true)
    }
    func testAccessFailureInEitherReadCannotBeMaskedByAnotherFailure() async {
        let functions = RouteFunctions()
        await functions.fail("merchantFulfilments", status: nil)
        await functions.fail("restaurantRequests", status: 403)
        let navigator = model(functions)
        await navigator.open(route())
        XCTAssertTrue(navigator.choices.isEmpty)
        XCTAssertTrue(navigator.message?.contains("could not be resolved") == true)
    }
    func testAccountChangeDuringReadCannotPublishPreviousActorsRecords() async {
        let functions = RouteFunctions(), identity = MerchantJournalTestIdentity()
        let navigator = DastakMerchantNotificationNavigator(services: .init(functions: functions,
            accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }))
        await functions.hold()
        let read = Task { await navigator.open(route()) }
        await functions.wait(); await identity.change(); await functions.release(); await read.value
        XCTAssertTrue(navigator.choices.isEmpty); XCTAssertTrue(navigator.message?.contains("current Merchant account") == true)
    }
    func testNewerAlertSupersedesAnOlderInFlightLookup() async {
        let functions = RouteFunctions(), navigator = model(functions)
        await functions.hold()
        let first = Task { await navigator.open(route()) }
        await functions.wait()
        let newer = route("merchant.return_incoming")
        await navigator.open(newer)
        XCTAssertEqual(navigator.route, newer)
        XCTAssertEqual(navigator.choices.map { $0.target.kind }, [.returned])
        await functions.release(); await first.value
        XCTAssertEqual(navigator.route, newer)
        XCTAssertEqual(navigator.choices.map { $0.target.kind }, [.returned])
        XCTAssertFalse(navigator.loading)
    }
    func testTimeoutAndDismissIgnoreLateReadAndDoNotOwnAnOrderLock() async {
        let functions = RouteFunctions(), navigator = model(functions, timeout: .milliseconds(50))
        await functions.hold()
        let read = Task { await navigator.open(route()) }
        await functions.wait(); await read.value
        XCTAssertFalse(navigator.loading); XCTAssertTrue(navigator.choices.isEmpty)
        await functions.release()
        await navigator.open(route()); XCTAssertEqual(navigator.choices.count, 2)
        await functions.hold()
        let next = Task { await navigator.open(route()) }
        await functions.wait(); navigator.cancel(); await functions.release(); await next.value
        XCTAssertTrue(navigator.choices.isEmpty); XCTAssertFalse(navigator.loading)
    }
    private func model(_ functions: RouteFunctions, timeout: Duration = .seconds(1)) -> DastakMerchantNotificationNavigator {
        let actor = UUID()
        return .init(services: .init(functions: functions, accountIDProvider: { actor },
            objectUploader: { _, _, _, _, _ in }), timeout: timeout)
    }
}

private let routeOrder = UUID(uuidString: "92000000-0000-4000-8000-000000000001")!
private let routeBranch = UUID(uuidString: "92000000-0000-4000-8000-000000000002")!
private let routeBranch2 = UUID(uuidString: "92000000-0000-4000-8000-000000000003")!
private func routeID(_ value: Int) -> String { String(format: "92000000-0000-4000-8000-%012d", value + 100) }
private func branch(_ id: UUID) -> [String: Any] { ["id": id.uuidString, "displayName": id == routeBranch ? "Store A" : "Store B"] }
private func routeFeeds(empty: Bool) -> Data {
    let fulfilments = (0..<3).map { value -> [String: Any] in
        ["id": routeID(value), "orderId": value == 2 ? UUID().uuidString : routeOrder.uuidString,
         "displayOrderNumber": "DSK-test", "orderStatus": "PREPARING", "status": "PREPARING", "version": 1,
         "branch": branch(value == 1 ? routeBranch2 : routeBranch), "promisedPrepMinutes": 10,
         "secondsRemaining": 100, "runningLate": false, "evidence": [], "lines": [],
         "canDeclarePackages": true, "canAddEvidence": true, "canMarkReady": false]
    }
    let recovery: [String: Any] = ["id": routeID(10), "recoveryCaseId": routeID(11), "orderId": routeOrder.uuidString,
        "orderLineId": routeID(12), "status": "OFFERED", "requestedQuantity": 1,
        "startedAt": "2026-10-18T00:00:00Z", "expiresAt": "2026-10-18T00:01:00Z", "version": 1,
        "branch": branch(routeBranch), "sku": ["id": routeID(13), "name": "Tea", "packSize": "100 g"]]
    let receipt: [String: Any] = ["returnId": routeID(20), "returnMissionId": routeID(21), "returnStopId": routeID(22),
        "orderId": routeOrder.uuidString, "status": "ASSIGNED", "packageCount": 1, "branch": branch(routeBranch)]
    return try! JSONSerialization.data(withJSONObject: ["fulfilments": empty ? [] : fulfilments,
        "recoveryOpportunities": empty ? [] : [recovery], "returnReceipts": empty ? [] : [receipt], "settlements": []])
}
private actor RouteFunctions: FunctionClient {
    var calls: [String] = []
    private var failures: [String: Int] = [:], isEmpty = false, holding = false
    private var continuation: CheckedContinuation<Void, Never>?, started: CheckedContinuation<Void, Never>?
    func empty() { isEmpty = true }
    func fail(_ operation: String, status: Int?) { failures[operation] = status ?? 0 }
    func hold() { holding = true }
    func wait() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func release() { continuation?.resume(); continuation = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        let operation = body["operation"] as! String; calls.append(operation)
        if operation == "merchantFulfilments", holding {
            holding = false
            await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
        }
        if let status = failures[operation] {
            if status == 0 { throw URLError(.notConnectedToInternet) }
            throw FunctionClientError.api(statusCode: status, code: "denied", message: "Denied")
        }
        let data: Data
        if operation == "merchantFulfilments" { data = routeFeeds(empty: isEmpty) }
        else if operation == "restaurantRequests" {
            let requests: [[String: Any]] = isEmpty ? [] : [
                ["id": routeID(30), "orderId": routeOrder.uuidString, "displayOrderNumber": "DSK-test",
                 "status": "OFFERED", "version": 1, "branch": branch(routeBranch), "offeredAt": "2026-10-18T00:00:00Z",
                 "softThresholdWarning": false, "lines": []]]
            data = try JSONSerialization.data(withJSONObject: ["requests": requests])
        } else { throw URLError(.badURL) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
