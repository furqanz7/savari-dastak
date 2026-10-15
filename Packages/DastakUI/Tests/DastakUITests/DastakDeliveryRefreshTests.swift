import Foundation
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakDeliveryRefreshTests: XCTestCase {
    func testAutomaticRecoveryDoesNotCancelExistingSlowRead() async throws {
        let functions = InterleavedDeliveryFunctions()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.bootstrap()
        await functions.pauseNextRead()
        let read = Task { await model.refreshActiveDelivery() }
        await functions.waitUntilPaused()
        for _ in 0..<4 { await model.recoverDesk(force: false) }
        let readsWhileHeld = await functions.readCount
        XCTAssertEqual(readsWhileHeld, 2, "Routine recovery must leave the pending read alone")
        XCTAssertTrue(model.criticalReadRunning)
        await functions.releaseRead()
        await read.value
        XCTAssertTrue(model.v1Current)
        XCTAssertFalse(model.criticalReadRunning)
    }

    func testActionDuringContinuedReadFailureReportsFailureAndNeverWrites() async throws {
        let functions = InterleavedDeliveryFunctions()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.bootstrap()
        let mission = try XCTUnwrap(model.v1Dispatch?.currentMission)
        await functions.failFutureReads()
        await model.refreshActiveDelivery()
        await model.advanceV1Mission("v1StartPickups", mission: mission)
        let writes = await functions.mutationCount
        XCTAssertEqual(writes, 0)
        XCTAssertNotNil(model.errorMessage, "A failed tap must have an explanation, not silently do nothing")
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.criticalReadRunning)
    }

    func testOnDemandRecheckCannotSendOldActionAfterMissionStageChanges() async throws {
        let functions = InterleavedDeliveryFunctions()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.bootstrap()
        let mission = try XCTUnwrap(model.v1Dispatch?.currentMission)
        await functions.failFutureReads()
        await model.refreshActiveDelivery()
        await functions.allowFutureReads()
        await functions.setMissionStage(status: "OUT_FOR_DELIVERY", version: 8)
        await model.advanceV1Mission("v1StartPickups", mission: mission)
        let writes = await functions.mutationCount
        XCTAssertEqual(writes, 0)
        XCTAssertNotNil(model.noticeMessage)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .outForDelivery)
        XCTAssertFalse(model.isBusy)
    }

    func testRoutineRefreshBurstsJoinOneReadInsteadOfExtendingRecoveryQueue() async throws {
        let functions = InterleavedDeliveryFunctions()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.bootstrap()
        await functions.pauseNextRead()
        let read = Task { await model.refreshActiveDelivery() }
        await functions.waitUntilPaused()
        for _ in 0..<10 { await model.refreshActiveDelivery() }
        await functions.releaseRead()
        await read.value
        let count = await functions.readCount
        XCTAssertEqual(count, 2, "Bootstrap plus one coalesced active read, not a follow-up queue")
        XCTAssertFalse(model.criticalReadRunning)
    }

    func testActionAfterRefreshFailureRechecksInsteadOfSilentlyIgnoringTap() async throws {
        let functions = InterleavedDeliveryFunctions()
        let operations = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(
            functions: functions, accountIDProvider: { UUID(uuidString: "96000000-0000-4000-8000-000000000001")! },
            objectUploader: { _, _, _, _, _ in }), storage: RefreshDeliveryStore())
        await operations.restore()
        let model = DastakDeliveryPartnerModel(functions: functions, operations: operations)
        await model.bootstrap()
        let mission = try XCTUnwrap(model.v1Dispatch?.currentMission)
        await functions.failFutureReads()
        await model.refreshActiveDelivery()
        XCTAssertFalse(model.v1Current)
        await functions.allowFutureReads()
        await model.advanceV1Mission("v1StartPickups", mission: mission)
        let mutations = await functions.mutationCount
        XCTAssertEqual(mutations, 1)
        XCTAssertTrue(model.v1Current)
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(operations.pending)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .enRouteToPickups)
    }

    func testLostMutationResponseAutomaticallyResolvesFromFreshServerState() async throws {
        let functions = InterleavedDeliveryFunctions()
        let operations = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(
            functions: functions, accountIDProvider: { UUID(uuidString: "96000000-0000-4000-8000-000000000001")! },
            objectUploader: { _, _, _, _, _ in }), storage: RefreshDeliveryStore())
        await operations.restore()
        let model = DastakDeliveryPartnerModel(functions: functions, operations: operations)
        await model.bootstrap()
        let mission = try XCTUnwrap(model.v1Dispatch?.currentMission)
        await functions.loseNextActionReply()
        await model.advanceV1Mission("v1StartPickups", mission: mission)
        XCTAssertNil(operations.pending, "The successful fresh read must resolve the saved action without manual retry")
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.v1Current)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .enRouteToPickups)
        let mutations = await functions.mutationCount
        XCTAssertEqual(mutations, 1, "Read proof avoids repeating the mutation")
    }
    func testManualRefreshReplacesStuckReadAndLateResponseCannotRelockDesk() async throws {
        let functions = InterleavedDeliveryFunctions()
        let model = DastakDeliveryPartnerModel(functions: functions, requestTimeout: .seconds(5))
        await model.bootstrap()
        await functions.pauseNextRead()
        let blocked = Task { await model.refreshActiveDelivery() }
        await functions.waitUntilPaused()
        await model.refreshActiveDelivery(force: true)
        XCTAssertTrue(model.v1Current)
        XCTAssertFalse(model.criticalReadRunning)
        await blocked.value
        await functions.releaseRead()
        XCTAssertTrue(model.v1Current)
        XCTAssertFalse(model.criticalReadRunning)
    }

    func testTimedOutActiveReadReleasesSyncAndNextReadRecovers() async {
        let functions = InterleavedDeliveryFunctions()
        let model = DastakDeliveryPartnerModel(functions: functions, requestTimeout: .milliseconds(40))
        await model.bootstrap()
        await functions.pauseNextRead()
        await model.refreshActiveDelivery()
        XCTAssertFalse(model.criticalReadRunning)
        XCTAssertFalse(model.v1Current)
        XCTAssertNotNil(model.refreshFailure)
        await model.refreshActiveDelivery()
        XCTAssertTrue(model.v1Current)
        XCTAssertNil(model.refreshFailure)
        await functions.releaseRead()
    }
    func testCompleteActionReceiptAvoidsRedundantReadAndRemainsUsableWhenReadsFail() async throws {
        let functions = InterleavedDeliveryFunctions()
        let operations = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(
            functions: functions, accountIDProvider: { UUID(uuidString: "96000000-0000-4000-8000-000000000001")! },
            objectUploader: { _, _, _, _, _ in }), storage: RefreshDeliveryStore())
        await operations.restore()
        let model = DastakDeliveryPartnerModel(functions: functions, operations: operations)
        await model.bootstrap()
        let initial = try XCTUnwrap(model.v1Dispatch?.currentMission)
        await functions.failFutureReads()
        await model.advanceV1Mission("v1StartPickups", mission: initial)
        let reads = await functions.readCount
        XCTAssertEqual(reads, 1, "A full mutation receipt requires no second network request")
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .enRouteToPickups)
        XCTAssertTrue(model.v1Current)
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(operations.pending)
        XCTAssertNil(operations.confirmedSnapshot, "Receipts are consumed once and cannot later resurrect old work")
    }

    func testPartialActionReceiptStillRequiresAuthoritativeRefresh() async throws {
        let functions = InterleavedDeliveryFunctions()
        let operations = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(
            functions: functions, accountIDProvider: { UUID(uuidString: "96000000-0000-4000-8000-000000000001")! },
            objectUploader: { _, _, _, _, _ in }), storage: RefreshDeliveryStore())
        await operations.restore()
        let model = DastakDeliveryPartnerModel(functions: functions, operations: operations)
        await model.bootstrap()
        let initial = try XCTUnwrap(model.v1Dispatch?.currentMission)
        await functions.usePartialActionReply()
        await model.advanceV1Mission("v1StartPickups", mission: initial)
        let reads = await functions.readCount
        XCTAssertEqual(reads, 2)
        XCTAssertTrue(model.v1Current)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .enRouteToPickups)
    }
    func testActiveDeliveryRenewsExpiringOnlineSessionButNeverEnablesOfflineRider() async {
        for online in [true, false] {
            let functions = InterleavedDeliveryFunctions()
            await functions.setAvailabilityFixture(online: online)
            let model = DastakDeliveryPartnerModel(functions: functions)
            await model.bootstrap()
            XCTAssertTrue(model.hasActiveJob)
            await model.publishLocation(.init(address: "Sample", point: GeoPoint(latitude: 12, longitude: 78)))
            let renewals = await functions.availabilityRenewals
            XCTAssertEqual(renewals, online ? 1 : 0)
        }
    }
    func testSlowAuxiliaryServiceDoesNotDelayActionReceiptOrActiveRead() async throws {
        let functions = InterleavedDeliveryFunctions()
        let operations = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(
            functions: functions, accountIDProvider: { UUID(uuidString: "96000000-0000-4000-8000-000000000001")! },
            objectUploader: { _, _, _, _, _ in }), storage: RefreshDeliveryStore())
        await operations.restore()
        let model = DastakDeliveryPartnerModel(functions: functions, operations: operations)
        await functions.pauseAuxiliaryRead()
        let slowDesk = Task { await model.bootstrap() }
        await functions.waitUntilAuxiliaryPaused()
        // This independent read must complete even with the desk request held.
        await model.refreshActiveDelivery()
        let mission = try XCTUnwrap(model.v1Dispatch?.currentMission)
        await model.advanceV1Mission("v1StartPickups", mission: mission)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .enRouteToPickups)
        XCTAssertNil(operations.pending)
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.isRefreshing, "The unrelated service is still intentionally held")
        await functions.releaseAuxiliaryRead()
        await slowDesk.value
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .enRouteToPickups)
    }
    func testActionReceiptSurvivesEarlierReadWithoutExtraRoundTripOrLockedControls() async throws {
        let functions = InterleavedDeliveryFunctions()
        let operations = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(
            functions: functions, accountIDProvider: { UUID(uuidString: "96000000-0000-4000-8000-000000000001")! },
            objectUploader: { _, _, _, _, _ in }),
            storage: RefreshDeliveryStore())
        await operations.restore()
        let model = DastakDeliveryPartnerModel(functions: functions, operations: operations)
        await model.bootstrap()
        let initial = try XCTUnwrap(model.v1Dispatch?.currentMission)
        await functions.pauseNextRead()
        let oldRead = Task { await model.refreshOrderChange(.merchantOrder) }
        await functions.waitUntilPaused()
        await model.advanceV1Mission("v1StartPickups", mission: initial)
        await functions.releaseRead()
        await oldRead.value
        XCTAssertTrue(model.v1Current)
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(operations.pending)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .enRouteToPickups)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.version, 2)
        let count = await functions.readCount
        XCTAssertEqual(count, 2, "Bootstrap and obsolete read; the authoritative action receipt replaces a third request")
    }
    func testTrackingAdvancesActionDeskAndOlderReadCannotReturnItToPickup() async throws {
        let functions = DeliveryRefreshFunctionsStub()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.bootstrap()
        let initial = try XCTUnwrap(model.v1Dispatch?.currentMission)
        let tracked = try mission(initial, status: "OUT_FOR_DELIVERY", version: 8)
        model.adoptTrackedMission(tracked)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .outForDelivery)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.version, 8)
        await model.refresh()
        XCTAssertEqual(model.v1Dispatch?.currentMission?.status, .outForDelivery)
        XCTAssertEqual(model.v1Dispatch?.currentMission?.version, 8)
        model.adoptTrackedMission(try mission(initial, status: "ASSIGNED", version: 2))
        XCTAssertEqual(model.v1Dispatch?.currentMission, tracked)
    }

    func testTrackingCannotSwitchAssignmentResurrectCompletedWorkOrUnlockFailedRead() async throws {
        let functions = DeliveryRefreshFunctionsStub()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.bootstrap()
        let initial = try XCTUnwrap(model.v1Dispatch?.currentMission)
        model.adoptTrackedMission(try mission(initial, status: "ARRIVED", version: 8, id: UUID()))
        XCTAssertEqual(model.v1Dispatch?.currentMission, initial)
        await functions.setResponse(.failure); await model.refresh()
        XCTAssertFalse(model.v1Current)
        model.adoptTrackedMission(try mission(initial, status: "ARRIVED", version: 8))
        XCTAssertEqual(model.v1Dispatch?.currentMission, initial)
        await functions.setResponse(.empty); await model.refresh()
        model.adoptTrackedMission(initial)
        XCTAssertNil(model.v1Dispatch?.currentMission)
    }

    private func mission(_ base: DastakV1DeliveryMissionSnapshot, status: String, version: Int, id: UUID? = nil) throws -> DastakV1DeliveryMissionSnapshot {
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        body["status"] = status; body["version"] = version
        if let id { body["id"] = id.uuidString }
        return try JSONDecoder().decode(DastakV1DeliveryMissionSnapshot.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func testUnrelatedServiceFailuresDoNotHideActiveDelivery() async {
        let functions = DeliveryRefreshFunctionsStub()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.bootstrap()
        XCTAssertEqual(model.v1Dispatch?.currentMission?.displayOrderNumber, "D-123")
        XCTAssertEqual(
            model.v1Dispatch?.currentMission?.pickupStops.first?.branch.address.displayLine,
            "128, Mandi Street, Vaniyambadi"
        )
        XCTAssertTrue(model.hasActiveJob)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNotNil(model.refreshFailure)
        XCTAssertNil(model.errorMessage, "Background reconnection must not present a blocking alert")
        XCTAssertFalse(model.canShowEmptyDesk, "A failed operational lane must not claim the rider is ready with an empty queue")
    }

    func testFailedRefreshRetainsLastKnownJobUntilSuccessfulEmptySnapshot() async {
        let functions = DeliveryRefreshFunctionsStub()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.refresh()
        await functions.setResponse(.failure)
        await model.refresh()
        XCTAssertTrue(model.hasActiveJob)
        await functions.setResponse(.empty)
        await model.refresh()
        XCTAssertFalse(model.hasActiveJob)
        XCTAssertNil(model.v1Dispatch?.currentMission)
    }

    func testMerchantRealtimeEventRefreshesOnlyOrderDispatchProjections() async {
        let functions = DeliveryRealtimeFunctionsStub()
        let model = DastakDeliveryPartnerModel(functions: functions)

        await model.refreshOrderChange(.merchantOrder)

        let requests = await functions.requests
            .map { "\($0.function):\($0.operation)" }
            .sorted()
        XCTAssertEqual(
            requests,
            [
                "courier-dispatch:partnerSnapshot",
                "courier-dispatch:v1PartnerSnapshot"
            ].sorted()
        )
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.refreshFailure)
    }

    func testParcelRealtimeEventDoesNotFanOutAcrossUnrelatedServices() async {
        let functions = DeliveryRealtimeFunctionsStub()
        let model = DastakDeliveryPartnerModel(functions: functions)

        await model.refreshOrderChange(.parcel)

        let requests = await functions.requests
        XCTAssertEqual(requests.map { "\($0.function):\($0.operation)" }, ["parcel-deliveries:partnerSnapshot"])
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.refreshFailure)
    }
}

private actor RefreshDeliveryStore: DastakDeliveryCommandStorage {
    private var value: DastakDeliveryCommand?
    func load(_ accountID: UUID) -> DastakDeliveryCommand? { value }
    func replace(_ command: DastakDeliveryCommand?, accountID: UUID, expectedRevision: UUID?) throws {
        guard value?.revision == expectedRevision else { throw DastakDeliveryJournalError.changed }
        value = command
    }
}

private actor InterleavedDeliveryFunctions: FunctionClient {
    private var response = InterleavedDeliveryFunctions.dispatch(status: "ASSIGNED", version: 1)
    private var pauseNext = false
    private var paused = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private(set) var readCount = 0
    private var failReads = false
    private var partialActionReply = false
    private var loseActionReply = false
    private(set) var mutationCount = 0
    func loseNextActionReply() { loseActionReply = true }
    func failFutureReads() { failReads = true }
    func allowFutureReads() { failReads = false }
    func setMissionStage(status: String, version: Int) { response = Self.dispatch(status: status, version: version) }
    func usePartialActionReply() { partialActionReply = true }
    private var availabilityOnline: Bool?
    private(set) var availabilityRenewals = 0
    func setAvailabilityFixture(online: Bool) { availabilityOnline = online }
    private var holdAuxiliary = false
    private var auxiliaryPaused = false
    private var auxiliaryWaiter: CheckedContinuation<Void, Never>?
    private var auxiliaryRelease: CheckedContinuation<Void, Never>?
    func pauseAuxiliaryRead() { holdAuxiliary = true }
    func waitUntilAuxiliaryPaused() async {
        if auxiliaryPaused { return }
        await withCheckedContinuation { auxiliaryWaiter = $0 }
    }
    func releaseAuxiliaryRead() { auxiliaryRelease?.resume(); auxiliaryRelease = nil }
    func pauseNextRead() { pauseNext = true }
    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func releaseRead() { release?.resume(); release = nil }
    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(_ name: String,
        request: Input, idempotencyKey: IdempotencyKey) async throws -> Result {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        let operation = body?["operation"] as? String
        var data = Data("{}".utf8)
        if let online = availabilityOnline, name == "delivery-partners" {
            if operation == "setAvailability" { availabilityRenewals += 1 }
            let until = ISO8601DateFormatter().string(from: .now.addingTimeInterval(60))
            let availability = "{\"status\":\"\(online ? "online" : "offline")\",\"availableUntil\":\"\(until)\",\"stateVersion\":1}"
            data = Data((operation == "selfSnapshot" ? "{\"onboardingState\":\"approved\",\"availability\":\(availability)}" : availability).utf8)
        }
        if name == "delivery-partners", holdAuxiliary {
            holdAuxiliary = false; auxiliaryPaused = true
            await withCheckedContinuation { continuation in
                auxiliaryRelease = continuation; auxiliaryWaiter?.resume(); auxiliaryWaiter = nil
            }
        }
        if operation == "v1PartnerSnapshot" {
            readCount += 1; data = response
            if failReads { throw URLError(.timedOut) }
            if pauseNext {
                pauseNext = false; paused = true
                await withCheckedContinuation { continuation in
                    release = continuation; waiter?.resume(); waiter = nil
                }
            }
        } else if operation == "v1StartPickups" {
            mutationCount += 1
            response = Self.dispatch(status: "EN_ROUTE_TO_PICKUPS", version: 2); data = response
            if loseActionReply { loseActionReply = false; throw URLError(.networkConnectionLost) }
            if partialActionReply {
                data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"returnMission\":null,", with: "").utf8)
            }
        }
        return try JSONDecoder().decode(Result.self, from: data)
    }
    private static func dispatch(status: String, version: Int) -> Data {
        Data("""
        {"offer":null,"returnMission":null,"currentMission":{
        "id":"96000000-0000-4000-8000-000000000002","displayOrderNumber":"D-RACE",
        "status":"\(status)","version":\(version),"pickupCount":1,"pickupStops":[],
        "canStartFinalDelivery":false,"canArriveCustomer":false,"canCaptureDeliveryEvidence":false,
        "canVerifyDelivery":false,"canCancelBeforePickup":true,"mustUseDeliveryRecovery":false}}
        """.utf8)
    }
}

private actor DeliveryRealtimeFunctionsStub: FunctionClient {
    struct Request: Equatable {
        let function: String
        let operation: String
    }

    private(set) var requests: [Request] = []

    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String,
        request: Input,
        idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        let encoded = try JSONEncoder().encode(request)
        let body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        guard let operation = body?["operation"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        requests.append(.init(function: name, operation: operation))
        let json = operation == "v1PartnerSnapshot" ? "{\"offer\":null,\"currentMission\":null,\"returnMission\":null,\"completedMission\":null}" : "{}"
        return try JSONDecoder().decode(Result.self, from: Data(json.utf8))
    }
}

private actor DeliveryRefreshFunctionsStub: FunctionClient {
    enum Response { case mission, empty, failure }
    private var response: Response = .mission
    func setResponse(_ response: Response) { self.response = response }

    func invoke<Request: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        let encoded = try JSONEncoder().encode(request)
        let body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        guard body?["operation"] as? String == "v1PartnerSnapshot", response != .failure else {
            throw URLError(.notConnectedToInternet)
        }
        let json = response == .empty ? "{\"offer\":null,\"currentMission\":null,\"returnMission\":null,\"completedMission\":null}" : """
        {"offer":null,"returnMission":null,"completedMission":null,"currentMission":{
          "id":"00000000-0000-0000-0000-000000000001",
          "displayOrderNumber":"D-123","status":"ASSIGNED","version":1,
          "pickupCount":1,"pickupStops":[{
            "id":"00000000-0000-0000-0000-000000000002",
            "sequence":1,"status":"PENDING","ready":true,"runningLate":false,
            "packageCount":1,"waitingSeconds":0,
            "branch":{
              "id":"00000000-0000-0000-0000-000000000003",
              "displayName":"Zuper",
              "address":{
                "line1":"128, Mandi Street, Vaniyambadi",
                "latitude":12.6811386362372,"longitude":78.6154330651743
              },
              "location":{"latitude":12.6811386362372,"longitude":78.6154330651743}
            }
          }],"canStartFinalDelivery":false,
          "canArriveCustomer":false,"canCaptureDeliveryEvidence":false,
          "canVerifyDelivery":false,"canCancelBeforePickup":true,
          "mustUseDeliveryRecovery":false
        }}
        """
        return try JSONDecoder().decode(Result.self, from: Data(json.utf8))
    }
}
