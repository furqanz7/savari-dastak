import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakDeliveryOperationsTests: XCTestCase {
    func testIndependentReadResolvesLostStartReceiptWithoutRepeatingMutation() async throws {
        let (ops, functions, _) = await setup(returned: "null")
        let initial = try decode(normalDispatch(status: "ASSIGNED", version: 1)); ops.adopt(initial)
        await ops.submitDelivery(.start, mission: try XCTUnwrap(initial.currentMission))
        XCTAssertNotNil(ops.pending)
        await ops.reconcileObserved(try decode(normalDispatch(status: "EN_ROUTE_TO_PICKUPS", version: 2)))
        XCTAssertNil(ops.pending)
        XCTAssertFalse(ops.blocksActions)
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testReadWithWrongMissionOrUnchangedStateCannotClearSavedAction() async throws {
        for data in [normalDispatch(status: "ASSIGNED", version: 1),
                     normalDispatch(status: "EN_ROUTE_TO_PICKUPS", version: 2).replacingJSONText(returnID.uuidString, UUID().uuidString)] {
            let (ops, _, _) = await setup(returned: "null")
            let initial = try decode(normalDispatch(status: "ASSIGNED", version: 1)); ops.adopt(initial)
            await ops.submitDelivery(.start, mission: try XCTUnwrap(initial.currentMission))
            let saved = ops.pending
            await ops.reconcileObserved(try decode(data))
            XCTAssertEqual(ops.pending, saved)
        }
    }
    func testHungMutationReleasesBusyRetainsIntentAndAutomaticRecoveryFinishesIt() async throws {
        let functions = SuspendedDeliveryMutationFunctions()
        let ops = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { accountID }, objectUploader: { _, _, _, _, _ in }),
            storage: DeliveryOperationsStore(), requestTimeout: .milliseconds(40))
        await ops.restore()
        let initial = try decode(normalDispatch(status: "ASSIGNED", version: 1)); ops.adopt(initial)
        await ops.submitDelivery(.start, mission: try XCTUnwrap(initial.currentMission))
        let saved = try XCTUnwrap(ops.pending)
        XCTAssertFalse(ops.busy, "An unresponsive request must release the loading state")
        await ops.recoverAutomatically()
        XCTAssertNil(ops.pending)
        XCTAssertFalse(ops.blocksActions)
        let calls = await functions.mutations
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].0, calls[1].0)
        XCTAssertEqual(calls[0].1, saved.key.rawValue)
        XCTAssertEqual(calls[1].1, saved.key.rawValue)
        await functions.releaseOriginalReply()
        XCTAssertNil(ops.pending, "The old response has no path back into the delivery model")
        XCTAssertNil(ops.confirmedSnapshot)
    }
    func testAutomaticRecoveryReplaysOriginalActionAndNeverPublishesHistoricalReceipt() async throws {
        let (ops, functions, _) = await setup(returned: "null")
        let initial = try decode(normalDispatch(status: "ASSIGNED", version: 1)); ops.adopt(initial)
        await ops.submitDelivery(.start, mission: try XCTUnwrap(initial.currentMission))
        let saved = try XCTUnwrap(ops.pending)
        await functions.enqueue(.data(Data("{\"kind\":\"V1_DELIVERY\",\"workId\":\"\(returnID)\",\"terminal\":false,\"missionStatus\":\"EN_ROUTE_TO_PICKUPS\",\"collection\":null}".utf8)))
        await functions.enqueue(.data(normalDispatch(status: "EN_ROUTE_TO_PICKUPS", version: 2)))
        await ops.recoverAutomatically()
        XCTAssertNil(ops.pending)
        XCTAssertFalse(ops.busy)
        XCTAssertFalse(ops.blocksActions)
        XCTAssertNil(ops.confirmedSnapshot, "Replay receipts may describe an earlier stage; the desk must read current work")
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls[0].body, calls[2].body)
        XCTAssertEqual(calls[2].key, saved.key.rawValue)
    }

    func testAutomaticRecoveryStopsAtMatchingCompletedDeliveryWithoutReplayingAction() async throws {
        let (ops, functions, _) = await setup(returned: "null")
        let initial = try decode(normalDispatch(status: "ASSIGNED", version: 1)); ops.adopt(initial)
        await ops.submitDelivery(.start, mission: try XCTUnwrap(initial.currentMission))
        await functions.enqueue(.data(Data("{\"kind\":\"V1_DELIVERY\",\"workId\":\"\(returnID)\",\"terminal\":true,\"missionStatus\":\"DELIVERED\",\"collection\":null}".utf8)))
        await ops.recoverAutomatically()
        XCTAssertNil(ops.pending)
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 2, "Terminal recovery performs only a read")
    }

    func testHangingAccountLookupUnlocksRestoreForAnotherAttempt() async throws {
        let functions = DeliveryOperationsFunctions()
        let identity = SuspendedDeliveryIdentity()
        let ops = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { await identity.read() }, objectUploader: { _, _, _, _, _ in }),
            storage: DeliveryOperationsStore(), requestTimeout: .milliseconds(40))
        await ops.restore()
        XCTAssertFalse(ops.busy)
        XCTAssertFalse(ops.restored)
        await identity.release()
        await ops.recoverAutomatically()
        XCTAssertTrue(ops.restored)
        XCTAssertFalse(ops.blocksActions)
    }
    func testCollectionAcknowledgesSameVersionForCashUPIAndFailedAttempt() async throws {
        for (outcome, method, state) in [("COLLECTED", "CASH", "PAYMENT_COLLECTED"), ("COLLECTED", "UPI", "PAYMENT_COLLECTED"), ("FAILED", "CASH", "COLLECTION_RETRY_NEEDED")] {
            let (ops, functions, store) = await setup(returned: "null")
            let before = try decode(collectionDispatch(state: "PAYMENT_DUE_AT_DELIVERY"))
            ops.adopt(before)
            await functions.enqueue(.data(collectionDispatch(state: state, outcome: outcome, method: method)))
            await ops.submitDelivery(.collection, mission: try XCTUnwrap(before.currentMission),
                outcome: DastakV1CollectionOutcome(rawValue: outcome), method: DastakV1CollectionMethod(rawValue: method),
                failureReason: outcome == "FAILED" ? "Payment declined" : nil)
            XCTAssertNil(ops.pending)
            XCTAssertFalse(ops.blocksActions)
            XCTAssertEqual(ops.confirmedSnapshot?.currentMission?.version, 12)
            let disk = try await store.load(accountID)
            XCTAssertNil(disk)
        }
    }

    func testSavedCollectionResolvesCompletedDeliveryWithoutReplayingPayment() async throws {
        let (ops, functions, store) = await setup(returned: "null")
        let before = try decode(collectionDispatch(state: "PAYMENT_DUE_AT_DELIVERY")); ops.adopt(before)
        await ops.submitDelivery(.collection, mission: try XCTUnwrap(before.currentMission), outcome: .collected, method: .cash)
        XCTAssertNotNil(ops.pending)
        let relaunched = makeOps(functions, store); await relaunched.restore()
        await functions.enqueue(.data(Data("{\"kind\":\"V1_DELIVERY\",\"workId\":\"\(returnID)\",\"terminal\":true,\"missionStatus\":\"DELIVERED\",\"collection\":null}".utf8)))
        await relaunched.retry()
        XCTAssertNil(relaunched.pending)
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 2)
        let last = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[1].body) as? [String: Any])
        XCTAssertEqual(last["operation"] as? String, "partnerOrderDetail")
    }

    func testUncertainRecoveryReadNeverDiscardsMoneyCommand() async throws {
        for (id, status, terminal) in [(UUID(), "DELIVERED", true), (returnID, "ARRIVED", false), (returnID, "CANCELLED", true)] {
            let (ops, functions, _) = await setup(returned: "null")
            let before = try decode(collectionDispatch(state: "PAYMENT_DUE_AT_DELIVERY")); ops.adopt(before)
            await ops.submitDelivery(.collection, mission: try XCTUnwrap(before.currentMission), outcome: .collected, method: .cash)
            let saved = ops.pending
            await functions.enqueue(.data(Data("{\"kind\":\"V1_DELIVERY\",\"workId\":\"\(id)\",\"terminal\":\(terminal),\"missionStatus\":\"\(status)\",\"collection\":null}".utf8)))
            await ops.reconcilePending()
            XCTAssertEqual(ops.pending, saved)
        }
    }

    func testSameVersionLateReadCannotUndoConfirmedPayment() throws {
        let before = try XCTUnwrap(decode(collectionDispatch(state: "PAYMENT_DUE_AT_DELIVERY")).currentMission)
        let confirmed = try XCTUnwrap(decode(collectionDispatch(state: "PAYMENT_COLLECTED", outcome: "COLLECTED", method: "CASH")).currentMission)
        XCTAssertEqual(before.retainingConfirmedProgress(from: confirmed), confirmed)
        XCTAssertEqual(confirmed.retainingConfirmedProgress(from: before), confirmed)
    }
    func testLegacyArrivalAcknowledgesAtStoreAndKeepsSameRequestAfterTimeout() async throws {
        let (ops, functions, _) = await setup(returned: "null")
        await ops.submitAssignment(parcel: false, action: "arriveAtStore", assignmentID: returnID, code: nil)
        XCTAssertNotNil(ops.pending)
        let reply = Data("""
        {"offer":null,"currentJob":{"assignmentId":"\(returnID)","orderId":"\(stopID)","assignmentStatus":"accepted","orderStatus":"at_store","offeredAt":"2026-10-15T00:00:00Z","respondBy":"2026-10-15T00:01:00Z","acceptedAt":"2026-10-15T00:00:30Z","distanceMeters":500,"courierPayout":{"paise":1500},"store":{"storeId":"\(stopID)","name":"Merchant","address":"Store Road","pickup":{"latitude":12,"longitude":78}},"dropoff":{"latitude":12.1,"longitude":78.1},"items":[]}}
        """.utf8)
        await functions.enqueue(.data(reply)); await ops.retry()
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].body, calls[1].body)
        XCTAssertEqual(calls[0].key, calls[1].key)
        XCTAssertNil(ops.pending)
    }
    func testReleaseBeforePickupRequiresExplicitReassignmentReceiptNotCancelledHistory() async throws {
        let (ops, functions, _) = await setup(returned: "null")
        let before = try decode(normalDispatch(status: "ASSIGNED", version: 1)
            .replacingJSONText("\"canCancelBeforePickup\":false", "\"canCancelBeforePickup\":true"))
        ops.adopt(before)
        await functions.enqueue(.data(dispatch(returned: "null")))
        await ops.submitDelivery(.cancel, mission: try XCTUnwrap(before.currentMission), reason: "Cannot continue before pickup")
        XCTAssertNotNil(ops.pending, "An empty desk alone is not a release receipt")
        await functions.enqueue(.data(Data(#"{"offer":null,"currentMission":null,"reassignmentStarted":true}"#.utf8)))
        await ops.retry()
        XCTAssertNil(ops.pending)
    }
    func testNormalDeliveryRetrySurvivesRelaunchAndCannotBeReplaced() async throws {
        let (ops, functions, store) = await setup(returned: "null")
        let before = try decode(normalDispatch(status: "ASSIGNED", version: 1))
        ops.adopt(before)
        let mission = try XCTUnwrap(before.currentMission)
        await ops.submitDelivery(.start, mission: mission)
        XCTAssertEqual(ops.pending?.operation, .start)
        let relaunched = makeOps(functions, store); await relaunched.restore(); relaunched.adopt(before)
        await relaunched.submitDelivery(.cancel, mission: mission, reason: "Changed request")
        await functions.enqueue(.data(normalDispatch(status: "EN_ROUTE_TO_PICKUPS", version: 2)))
        await relaunched.retry()
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].body, calls[1].body)
        XCTAssertEqual(calls[0].key, calls[1].key)
        XCTAssertNil(relaunched.pending)
    }

    func testNormalDeliveryRejectsWrongAcknowledgementAndLocksStaleActions() async throws {
        let (ops, functions, _) = await setup(returned: "null")
        let before = try decode(normalDispatch(status: "ASSIGNED", version: 1)); ops.adopt(before)
        let mission = try XCTUnwrap(before.currentMission)
        await functions.enqueue(.data(normalDispatch(status: "ASSIGNED", version: 1)))
        await ops.submitDelivery(.start, mission: mission)
        XCTAssertNotNil(ops.pending)
        XCTAssertTrue(ops.blocksActions)
        let (other, otherFunctions, _) = await setup(returned: "null")
        other.adopt(before); other.invalidate()
        await other.submitDelivery(.start, mission: mission)
        let calls = await otherFunctions.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testNormalPhotoTimeoutKeepsOriginalBytesAndOwnedPath() async throws {
        let functions = DeliveryOperationsFunctions(); let store = DeliveryOperationsStore(); let uploads = DeliveryUploadLog()
        let ops = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { accountID }, objectUploader: { _, path, data, _, _ in try await uploads.upload(path, data) }), storage: store)
        await ops.restore()
        let data = normalDispatch(status: "ARRIVED", version: 4)
            .replacingJSONText("\"canCaptureDeliveryEvidence\":false", "\"canCaptureDeliveryEvidence\":true")
        let snapshot = try decode(data); ops.adopt(snapshot)
        await ops.submitDelivery(.deliveryEvidence, mission: try XCTUnwrap(snapshot.currentMission), photo: Data([1, 2, 3]), contentType: "image/jpeg")
        let saved = try XCTUnwrap(ops.pending)
        XCTAssertTrue(saved.objectPath?.hasPrefix("rider-delivery/\(accountID.uuidString.lowercased())/") == true)
        await ops.retry()
        let attempts = await uploads.attempts
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0].0, attempts[1].0)
        XCTAssertEqual(attempts[0].1, attempts[1].1)
        XCTAssertEqual(ops.pending?.key, saved.key)
    }

    func testReturnOnlySnapshotIsActiveWorkAndNotAnEmptyDeliveryDesk() async throws {
        let functions = DeliveryOperationsFunctions()
        await functions.enqueue(.data(dispatch()))
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.refreshOrderChange(.merchantOrder)
        XCTAssertTrue(model.hasActiveJob)
        XCTAssertEqual(model.v1Dispatch?.returnMission?.id, returnID)
        XCTAssertNil(model.v1Dispatch?.currentMission)
    }
    func testMalformedReturnDoesNotDestroyNormalLaneAndMissingReturnIsUnknown() throws {
        for value in ["{}", "null"] {
            let snapshot = try decode(dispatch(returned: value))
            XCTAssertTrue(snapshot.deliveryLaneCurrent)
            XCTAssertEqual(snapshot.returnLaneCurrent, value == "null")
        }
        XCTAssertFalse(try decode(Data(#"{"offer":null,"currentMission":null}"#.utf8)).returnLaneCurrent)
        let snapshot = try decode(Data("{\"offer\":{},\"currentMission\":null,\"returnMission\":\(returnFixture())}".utf8))
        XCTAssertFalse(snapshot.deliveryLaneCurrent)
        XCTAssertTrue(snapshot.returnLaneCurrent)
        XCTAssertEqual(snapshot.returnMission?.id, returnID)
    }
    func testReturnStaleAndMalformedReadRetainsJobButLocksCustody() async throws {
        let (ops, _, _) = await setup()
        let mission = try XCTUnwrap(ops.returnMission)
        ops.invalidate()
        XCTAssertNotNil(ops.returnMission)
        XCTAssertFalse(ops.canReturn(.arriveCustomer, mission: mission))
        ops.adopt(try decode(dispatch(returned: "{}")))
        XCTAssertFalse(ops.returnsCurrent)
        XCTAssertEqual(ops.returnMission?.id, returnID)
    }
    func testArrivalRequiresServerFlagFreshGPSAndRecentRead() async throws {
        let (ops, _, _) = await setup()
        let mission = try XCTUnwrap(ops.returnMission)
        XCTAssertTrue(ops.canReturn(.arriveCustomer, mission: mission))
        XCTAssertFalse(ops.canReturn(.arriveCustomer, mission: mission, now: Date().addingTimeInterval(61)))
        ops.adopt(try decode(dispatch(returned: returnFixture(eligible: false))))
        XCTAssertFalse(ops.canReturn(.arriveCustomer, mission: try XCTUnwrap(ops.returnMission)))
    }
    func testPickupRequiresPhotoAllPackagesAndSixASCIIDigits() async throws {
        let (ops, _, _) = await setup(returned: returnFixture(status: "AT_CUSTOMER", evidence: false))
        var mission = try XCTUnwrap(ops.returnMission)
        XCTAssertFalse(ops.canReturn(.pickup, mission: mission, confirmed: true, code: "123456"))
        ops.adopt(try decode(dispatch(returned: returnFixture(status: "AT_CUSTOMER", evidence: true))))
        mission = try XCTUnwrap(ops.returnMission)
        XCTAssertFalse(ops.canReturn(.pickup, mission: mission, code: "123456"))
        XCTAssertFalse(ops.canReturn(.pickup, mission: mission, confirmed: true, code: "١٢٣٤٥٦"))
        XCTAssertTrue(ops.canReturn(.pickup, mission: mission, confirmed: true, code: "123456"))
    }
    func testMerchantReceiptRequiresPickedUpCustodyArrivalAndPhysicalCount() async throws {
        let (ops, _, _) = await setup(returned: returnFixture(status: "RETURNING_TO_MERCHANTS", stopStatus: "ARRIVED"))
        let mission = try XCTUnwrap(ops.returnMission)
        XCTAssertFalse(ops.canReturn(.receipt, mission: mission, stopID: stopID, code: "123456"))
        XCTAssertFalse(ops.canReturn(.receipt, mission: mission, stopID: UUID(), confirmed: true, code: "123456"))
        XCTAssertTrue(ops.canReturn(.receipt, mission: mission, stopID: stopID, confirmed: true, code: "123456"))
    }
    func testCommandIsSavedBeforeWriteAndRetryKeepsOriginalPINAndKeyAcrossRelaunch() async throws {
        let (ops, functions, store) = await setup(returned: returnFixture(status: "AT_CUSTOMER", evidence: true))
        await ops.submitReturn(.pickup, mission: try XCTUnwrap(ops.returnMission), confirmed: true, code: "123456")
        let saved = try XCTUnwrap(ops.pending)
        let disk = try await store.load(accountID)
        XCTAssertEqual(saved, disk)
        let restored = makeOps(functions, store)
        await restored.restore()
        restored.adopt(try decode(dispatch(returned: returnFixture(status: "AT_CUSTOMER", evidence: true))))
        await restored.submitReturn(.pickup, mission: try XCTUnwrap(restored.returnMission), confirmed: true, code: "654321")
        await functions.enqueue(.data(dispatch(returned: returnFixture(status: "RETURNING_TO_MERCHANTS", version: 2))))
        await restored.retry()
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].body, calls[1].body)
        XCTAssertEqual(calls[0].key, calls[1].key)
        XCTAssertNil(restored.pending)
        let remaining = try await store.load(accountID)
        XCTAssertNil(remaining)
    }
    func testStorageWriteFailurePreventsAnyHandoffRequest() async throws {
        let (ops, functions, store) = await setup()
        await store.failNextSave()
        await ops.submitReturn(.arriveCustomer, mission: try XCTUnwrap(ops.returnMission))
        let calls = await functions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(ops.blocksActions)
    }
    func testWrongMissionAcknowledgementKeepsCommand() async throws {
        let (ops, functions, _) = await setup()
        await functions.enqueue(.data(dispatch(returned: returnFixture(status: "AT_CUSTOMER", version: 2, id: UUID()))))
        await ops.submitReturn(.arriveCustomer, mission: try XCTUnwrap(ops.returnMission))
        XCTAssertNotNil(ops.pending)
        XCTAssertTrue(ops.blocksActions)
    }
    func testAcknowledgedCommandWithCleanupFailureNeverRepeatsServerWrite() async throws {
        let (ops, functions, store) = await setup()
        await store.failNextRemoval()
        await functions.enqueue(.data(dispatch(returned: returnFixture(status: "AT_CUSTOMER", version: 2))))
        await ops.submitReturn(.arriveCustomer, mission: try XCTUnwrap(ops.returnMission))
        XCTAssertTrue(ops.pending?.acknowledged == true)
        let relaunched = makeOps(functions, store)
        await relaunched.restore(); await relaunched.retry()
        XCTAssertNil(relaunched.pending)
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 1)
    }
    func testDefinitiveRejectedPINUnlocksOnlyAfterRefreshAndDoesNotSilentlyRetry() async throws {
        let (ops, functions, _) = await setup(returned: returnFixture(status: "AT_CUSTOMER", evidence: true))
        await functions.enqueue(.rejected)
        await ops.submitReturn(.pickup, mission: try XCTUnwrap(ops.returnMission), confirmed: true, code: "123456")
        XCTAssertNil(ops.pending)
        XCTAssertFalse(ops.returnsCurrent)
        await ops.retry()
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 1)
    }
    func testFinalReturnNeedsMatchingCompletedHistoryNotAnEmptySnapshot() async throws {
        let (ops, functions, _) = await setup(returned: returnFixture(status: "RETURNING_TO_MERCHANTS", stopStatus: "ARRIVED"))
        await functions.enqueue(.data(dispatch(returned: "null")))
        await functions.enqueue(.data(Data(#"{"items":[]}"#.utf8)))
        await ops.submitReturn(.receipt, mission: try XCTUnwrap(ops.returnMission), stopID: stopID, confirmed: true, code: "123456")
        XCTAssertNotNil(ops.pending)
        await functions.enqueue(.data(dispatch(returned: "null")))
        await functions.enqueue(.data(historyFixture()))
        await ops.retry()
        XCTAssertNil(ops.pending)
        XCTAssertNil(ops.returnMission)
    }
    func testEvidenceUploadTimeoutRetainsOriginalBytesPathAndKey() async throws {
        let functions = DeliveryOperationsFunctions()
        let store = DeliveryOperationsStore()
        let uploads = DeliveryUploadLog()
        let ops = DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { accountID }, objectUploader: { _, path, data, _, _ in try await uploads.upload(path, data) }), storage: store)
        await ops.restore(); ops.adopt(try decode(dispatch(returned: returnFixture(status: "AT_CUSTOMER"))))
        await ops.submitReturn(.evidence, mission: try XCTUnwrap(ops.returnMission), photo: Data([1, 2, 3]), contentType: "image/jpeg")
        let first = try XCTUnwrap(ops.pending)
        await ops.retry()
        let attempts = await uploads.attempts
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0].0, attempts[1].0)
        XCTAssertEqual(attempts[0].1, attempts[1].1)
        XCTAssertEqual(ops.pending?.key, first.key)
        XCTAssertTrue(ops.pending?.uploaded == true)
        XCTAssertNil(ops.pending?.photo)
    }
    func testHistoryFailureRetainsRecordsAndNullablePayout() async {
        let (ops, functions, _) = await setup()
        await functions.enqueue(.data(historyFixture()))
        await ops.refreshHistory()
        XCTAssertTrue(ops.historyCurrent)
        XCTAssertNil(ops.history.first?.payoutPaise)
        await ops.refreshHistory()
        XCTAssertFalse(ops.historyCurrent)
        XCTAssertEqual(ops.history.count, 1)
    }
    func testOldTrackedReturnCannotReplaceNewerVersionOrDifferentMission() async throws {
        let (ops, _, _) = await setup(returned: returnFixture(version: 3))
        ops.adoptTracked(try decode(dispatch()).returnMission)
        XCTAssertEqual(ops.returnMission?.version, 3)
        ops.adoptTracked(try decode(dispatch(returned: returnFixture(version: 4, id: UUID()))).returnMission)
        XCTAssertEqual(ops.returnMission?.id, returnID)
    }
    func testGPSReplyCannotUndoStopArrivalWhenMissionVersionIsUnchanged() async throws {
        let (ops, _, _) = await setup(returned: returnFixture(status: "RETURNING_TO_MERCHANTS", stopStatus: "ARRIVED"))
        ops.adoptTracked(try decode(dispatch(returned: returnFixture(status: "RETURNING_TO_MERCHANTS"))).returnMission)
        XCTAssertEqual(ops.returnMission?.stops.first?.status, "ARRIVED")
    }
    func testUnknownOrInconsistentReturnLocksOnlyReturnLane() throws {
        for returned in [
            returnFixture().replacingOccurrences(of: "\"status\":\"ASSIGNED\"", with: "\"status\":\"FUTURE_STATE\""),
            returnFixture().replacingOccurrences(of: "\"failedAttempts\":0", with: "\"failedAttempts\":-1"),
            returnFixture().replacingOccurrences(of: "\"packageCount\":2", with: "\"packageCount\":0")
        ] {
            let result = try decode(dispatch(returned: returned))
            XCTAssertFalse(result.returnLaneCurrent)
            XCTAssertTrue(result.deliveryLaneCurrent)
            XCTAssertNil(result.returnMission)
        }
    }
    func testProtectedFileJournalRoundTripAccountIsolationAndCompareAndSwap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DastakDeliveryCommandFileStore(directory: directory)
        let command = DastakDeliveryCommand(accountID: accountID, key: IdempotencyKey(rawValue: UUID().uuidString)!,
            operation: .pickup, missionID: returnID, expectedVersion: 1, stopID: nil, code: "123456", reason: nil, objectPath: nil, photo: nil, contentType: nil)
        try await store.replace(command, accountID: accountID, expectedRevision: nil)
        let loaded = try await store.load(accountID)
        XCTAssertEqual(loaded, command)
        let other = try await store.load(UUID())
        XCTAssertNil(other)
        do { try await store.replace(nil, accountID: accountID, expectedRevision: UUID()); XCTFail("Must not remove another revision") } catch {}
        try await store.replace(nil, accountID: accountID, expectedRevision: command.revision)
    }

    func testEvidenceAcknowledgesExactPathWithoutRequiringMissionVersionIncrement() async throws {
        let (ops, functions, _) = await setup(returned: returnFixture(status: "AT_CUSTOMER"))
        await ops.submitReturn(.evidence, mission: try XCTUnwrap(ops.returnMission), photo: Data([1]), contentType: "image/jpeg")
        let path = try XCTUnwrap(ops.pending?.objectPath)
        let reply = returnFixture(status: "AT_CUSTOMER", evidence: true)
            .replacingOccurrences(of: "return-pickup/test.jpg", with: path)
        await functions.enqueue(.data(dispatch(returned: reply)))
        await ops.retry()
        XCTAssertNil(ops.pending)
        XCTAssertEqual(ops.returnMission?.version, 1)
    }

    func testReturnStopArrivalAcknowledgesStopStateWithoutMissionVersionIncrement() async throws {
        let (ops, functions, _) = await setup(returned: returnFixture(status: "RETURNING_TO_MERCHANTS"))
        await functions.enqueue(.data(dispatch(returned: returnFixture(status: "RETURNING_TO_MERCHANTS", stopStatus: "ARRIVED"))))
        await ops.submitReturn(.arriveStop, mission: try XCTUnwrap(ops.returnMission), stopID: stopID)
        XCTAssertNil(ops.pending)
        XCTAssertEqual(ops.returnMission?.stops.first?.status, "ARRIVED")
    }

    func testHeartbeatIsIndependentThrottledAndSendsMissionVersionOnly() async throws {
        let (ops, functions, _) = await setup(returned: "null")
        let mission = try normalMission()
        let response = heartbeatReceipt()
        await functions.enqueue(.data(response)); await functions.enqueue(.data(response))
        let now = Date()
        await ops.heartbeat(mission, now: now)
        await ops.heartbeat(mission, now: now.addingTimeInterval(10))
        await ops.heartbeat(mission, now: now.addingTimeInterval(30))
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 2)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[0].body) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["operation", "missionId", "expectedVersion"])
        XCTAssertEqual(body["operation"] as? String, "v1Heartbeat")
        XCTAssertEqual(body["expectedVersion"] as? Int, 1)
        XCTAssertNil(ops.returnMission)
        XCTAssertNil(ops.heartbeatFailure)
        await ops.heartbeat(mission, now: now.addingTimeInterval(60))
        XCTAssertNotNil(ops.heartbeatFailure)
    }

    func testHeartbeatWarningRecoversOnRealReceiptAndClearsWhenMissionEnds() async throws {
        let (ops, functions, _) = await setup(returned: "null")
        let mission = try normalMission(); let now = Date()
        await ops.heartbeat(mission, now: now)
        XCTAssertNotNil(ops.heartbeatFailure)
        await functions.enqueue(.data(heartbeatReceipt()))
        await ops.heartbeat(mission, now: now.addingTimeInterval(30))
        XCTAssertNil(ops.heartbeatFailure)
        await ops.heartbeat(mission, now: now.addingTimeInterval(60))
        XCTAssertNotNil(ops.heartbeatFailure)
        await ops.heartbeat(nil, now: now.addingTimeInterval(61))
        XCTAssertNil(ops.heartbeatFailure)
    }

    func testHeartbeatRejectsWrongMissionStaleVersionAndSnapshotInsteadOfReceipt() async throws {
        for response in [heartbeatReceipt(id: UUID()), heartbeatReceipt(version: 1),
                         normalDispatch(status: "OUT_FOR_DELIVERY", version: 2)] {
            let (ops, functions, _) = await setup(returned: "null")
            await functions.enqueue(.data(response))
            await ops.heartbeat(try normalMission())
            XCTAssertNotNil(ops.heartbeatFailure)
        }
    }

    func testHeartbeatThrottleIsScopedToMissionAndDoesNotReuseOldWarning() async throws {
        let monitor = DastakDeliveryHeartbeat(functions: DeliveryOperationsFunctions())
        let mission = try normalMission(); let now = Date()
        await monitor.send(mission, now: now)
        XCTAssertNotNil(monitor.failure)
        monitor.reset(for: UUID())
        XCTAssertNil(monitor.failure)
        let attempted = await monitor.send(mission, now: now.addingTimeInterval(1))
        XCTAssertTrue(attempted)
    }

    func testHeartbeatOnlyVersionChangeDoesNotClearHandoffInputs() throws {
        let first = try XCTUnwrap(decode(normalDispatch(status: "ARRIVED", version: 4)).currentMission)
        let heartbeat = try XCTUnwrap(decode(normalDispatch(status: "ARRIVED", version: 5)).currentMission)
        let nextStage = try XCTUnwrap(decode(normalDispatch(status: "OUT_FOR_DELIVERY", version: 6)).currentMission)
        XCTAssertEqual(DastakDeliveryPresentation.handoffRevision(first), DastakDeliveryPresentation.handoffRevision(heartbeat))
        XCTAssertNotEqual(DastakDeliveryPresentation.handoffRevision(first), DastakDeliveryPresentation.handoffRevision(nextStage))
    }

    func testGPSPartialLaneUpdatesMatchingMissionWithoutClearingUnknownReturnLane() throws {
        let tracker = DastakActiveDeliveryTracker(functions: DeliveryOperationsFunctions())
        // Disable CLLocation side effects; exercise only response adoption.
        tracker.stop()
        let initial = try XCTUnwrap(decode(normalDispatch(status: "EN_ROUTE_TO_PICKUPS", version: 3)).currentMission)
        tracker.adopt(initial)
        let partial = try decode(normalDispatch(status: "OUT_FOR_DELIVERY", version: 8)
            .replacingJSONText("\"returnMission\":null,", ""))
        XCTAssertFalse(partial.returnLaneCurrent)
        tracker.adopt(partial)
        XCTAssertEqual(tracker.mission?.status, .outForDelivery)
        XCTAssertEqual(tracker.mission?.version, 8)
        tracker.adopt(initial)
        XCTAssertEqual(tracker.mission?.version, 8)

        var fullReturn = try decode(dispatch())
        tracker.adopt(fullReturn)
        tracker.adopt(partial)
        XCTAssertNil(tracker.mission)
        XCTAssertNotNil(tracker.returnMission)
        fullReturn = try decode(dispatch(returned: "null"))
        tracker.adopt(fullReturn)
        tracker.adopt(partial)
        XCTAssertNil(tracker.mission, "A partial GPS response cannot resurrect an assignment after it ended")
    }

    func testProblemReasonIsFrozenAcrossRelaunchAndAcknowledgedByRecoveryState() async throws {
        let (ops, functions, store) = await setup(returned: "null")
        let mission = try normalMission()
        await ops.report(.unreachable, mission: mission, current: mission, reason: "  Customer not answering  ", fresh: true)
        XCTAssertEqual(ops.pending?.reason, "Customer not answering")
        let relaunched = makeOps(functions, store); await relaunched.restore()
        await functions.enqueue(.data(normalDispatch(status: "DELIVERY_RECOVERY", version: 2)))
        await relaunched.retry()
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].key, calls[1].key)
        XCTAssertEqual(calls[0].body, calls[1].body)
        XCTAssertNil(relaunched.pending)
    }

    func testSupersededDiskRecordPreventsRetryWrite() async throws {
        let (ops, functions, store) = await setup()
        await ops.submitReturn(.arriveCustomer, mission: try XCTUnwrap(ops.returnMission))
        let saved = try XCTUnwrap(ops.pending)
        try await store.replace(nil, accountID: accountID, expectedRevision: saved.revision)
        await ops.retry()
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(ops.pending, "A record already resolved by another scene cannot leave a permanent local lock")
    }

    private func normalMission() throws -> DastakV1DeliveryMissionSnapshot {
        try XCTUnwrap(decode(normalDispatch(status: "OUT_FOR_DELIVERY", version: 1)).currentMission)
    }

    private func setup(returned: String = returnFixture()) async -> (DastakDeliveryOperations, DeliveryOperationsFunctions, DeliveryOperationsStore) {
        let functions = DeliveryOperationsFunctions(); let store = DeliveryOperationsStore()
        let ops = makeOps(functions, store); await ops.restore()
        ops.adopt(try! decode(dispatch(returned: returned)))
        return (ops, functions, store)
    }
    private func makeOps(_ functions: DeliveryOperationsFunctions, _ store: DeliveryOperationsStore) -> DastakDeliveryOperations {
        DastakDeliveryOperations(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { accountID }, objectUploader: { _, _, _, _, _ in }), storage: store)
    }
    private func decode(_ data: Data) throws -> DastakV1DeliveryDispatchSnapshot { try JSONDecoder().decode(DastakV1DeliveryDispatchSnapshot.self, from: data) }
}

private extension Data {
    func replacingJSONText(_ old: String, _ new: String) -> Data { Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8) }
}

private actor DeliveryOperationsStore: DastakDeliveryCommandStorage {
    var value: DastakDeliveryCommand?
    private var failSave = false
    private var failRemove = false
    func failNextSave() { failSave = true }
    func failNextRemoval() { failRemove = true }
    func load(_ accountID: UUID) throws -> DastakDeliveryCommand? { value?.accountID == accountID ? value : nil }
    func replace(_ command: DastakDeliveryCommand?, accountID: UUID, expectedRevision: UUID?) throws {
        if failSave { failSave = false; throw URLError(.cannotWriteToFile) }
        if command == nil && failRemove { failRemove = false; throw URLError(.cannotWriteToFile) }
        guard value?.revision == expectedRevision else { throw DastakDeliveryJournalError.changed }
        value = command
    }
}
private actor DeliveryOperationsFunctions: FunctionClient {
    enum Reply: Sendable { case data(Data), rejected }
    struct Call: Sendable { let body: Data; let key: String }
    var calls: [Call] = []
    private var replies: [Reply] = []
    func enqueue(_ reply: Reply) { replies.append(reply) }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String,
        request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request)
        calls.append(.init(body: data, key: idempotencyKey.rawValue))
        if (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["operation"] as? String == "partnerSnapshot" {
            return try JSONDecoder().decode(Response.self, from: Data("{}".utf8))
        }
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        switch replies.removeFirst() {
        case let .data(data): return try JSONDecoder().decode(Response.self, from: data)
        case .rejected: throw FunctionClientError.api(statusCode: 409, code: "return_pickup_code_invalid", message: "Return PIN is incorrect.")
        }
    }
}
private actor DeliveryUploadLog {
    var attempts: [(String, Data)] = []
    func upload(_ path: String, _ data: Data) throws {
        attempts.append((path, data))
        if attempts.count == 1 { throw URLError(.timedOut) }
    }
}
private actor SuspendedDeliveryIdentity {
    private var continuation: CheckedContinuation<UUID, Never>?
    private var released = false
    func read() async -> UUID {
        if released { return accountID }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(returning: accountID); continuation = nil }
}
private actor SuspendedDeliveryMutationFunctions: FunctionClient {
    private var original: CheckedContinuation<Void, Never>?
    private(set) var mutations: [(Data, String)] = []
    func releaseOriginalReply() { original?.resume(); original = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String,
        request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let body = try JSONEncoder().encode(request)
        let operation = (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["operation"] as? String
        if operation == "partnerOrderDetail" {
            return try JSONDecoder().decode(Response.self, from: Data("{\"kind\":\"V1_DELIVERY\",\"workId\":\"\(returnID)\",\"terminal\":false,\"missionStatus\":\"EN_ROUTE_TO_PICKUPS\",\"collection\":null}".utf8))
        }
        mutations.append((body, idempotencyKey.rawValue))
        if mutations.count == 1 { await withCheckedContinuation { original = $0 } }
        return try JSONDecoder().decode(Response.self, from: normalDispatch(status: "EN_ROUTE_TO_PICKUPS", version: 2))
    }
}
private let accountID = UUID(uuidString: "95000000-0000-4000-8000-000000000001")!
private let returnID = UUID(uuidString: "95000000-0000-4000-8000-000000000002")!
private let stopID = UUID(uuidString: "95000000-0000-4000-8000-000000000003")!
private func dispatch(returned: String = returnFixture()) -> Data {
    Data("{\"offer\":null,\"currentMission\":null,\"completedMission\":null,\"returnMission\":\(returned)}".utf8)
}
private func returnFixture(status: String = "ASSIGNED", version: Int = 1, stopStatus: String = "PENDING",
    evidence: Bool = false, eligible: Bool = true, id: UUID = returnID) -> String {
    let timestamp = "2026-10-11T00:00:00Z"
    let arrival = "{\"eligible\":\(eligible),\"reason\":\"ELIGIBLE\",\"radiusMeters\":50,\"validUntil\":\"2099-01-01T00:00:00Z\"}"
    let photo = evidence ? "{\"id\":\"\(UUID())\",\"objectPath\":\"return-pickup/test.jpg\",\"contentType\":\"image/jpeg\",\"capturedAt\":\"\(timestamp)\"}" : ""
    return """
    {"id":"\(id)","returnId":"\(returnID)","orderId":"\(returnID)","status":"\(status)","version":\(version),"transportType":"MOTORBIKE",
    "assignedAt":"\(timestamp)","arrivedCustomerAt":"\(timestamp)","pickupCompletedAt":\(status == "RETURNING_TO_MERCHANTS" ? "\"\(timestamp)\"" : "null"),"completedAt":null,
    "customerDestination":{"address":{"line1":"Customer Road","latitude":12,"longitude":78},"recipient":null},"packageCount":2,
    "pickupVerification":{"status":"\(status == "RETURNING_TO_MERCHANTS" ? "CONSUMED" : "ACTIVE")","failedAttempts":0},"evidence":[\(photo)],
    "stops":[{"id":"\(stopID)","sequence":1,"status":"\(stopStatus)","packageCount":2,"arrivedAt":"\(timestamp)","completedAt":null,
    "verificationStatus":"ACTIVE","failedAttempts":0,"arrival":\(arrival),"canArrive":true,
    "branch":{"id":"\(stopID)","displayName":"Return branch","address":{"line1":"Store Road"},"location":{"latitude":12,"longitude":78}}}],
    "customerArrival":\(arrival),"canArriveCustomer":true,"canCaptureEvidence":true,"canVerifyPickup":true,"canCompleteReturnStops":true}
    """
}
private func historyFixture() -> Data {
    Data("""
    {"items":[{"kind":"RETURN","workId":"\(returnID)","reference":"DSK-TEST","status":"COMPLETED","startedAt":"2026-10-11T00:00:00Z","endedAt":"2026-10-11T01:00:00Z","packageCount":2,"payoutPaise":null,"outcome":"RETURNED"}]}
    """.utf8)
}
private func normalDispatch(status: String, version: Int) -> Data {
    Data("""
    {"offer":null,"returnMission":null,"completedMission":null,"currentMission":{
    "id":"\(returnID)","displayOrderNumber":"DSK-TEST","status":"\(status)","version":\(version),
    "pickupCount":1,"pickupStops":[],"canStartFinalDelivery":false,"canArriveCustomer":false,
    "canCaptureDeliveryEvidence":false,"canVerifyDelivery":false,"canCancelBeforePickup":false,"mustUseDeliveryRecovery":true}}
    """.utf8)
}
private func heartbeatReceipt(id: UUID = returnID, version: Int = 2) -> Data {
    Data("{\"missionId\":\"\(id)\",\"version\":\(version),\"lastContactAt\":\"2026-10-15T02:00:00Z\",\"escalationState\":\"NONE\"}".utf8)
}

private func collectionDispatch(state: String, outcome: String? = nil, method: String? = nil) -> Data {
    let collection = """
    "launchCollection":{"required":true,"state":"\(state)","amountPaise":4590,"currencyCode":"INR","methods":["CASH","UPI"],"canRecord":true,"lastOutcome":\(outcome.map { "\"\($0)\"" } ?? "null"),"lastMethod":\(method.map { "\"\($0)\"" } ?? "null")},
    """
    return normalDispatch(status: "ARRIVED", version: 12)
        .replacingJSONText("\"pickupCount\":1", collection + "\"pickupCount\":1")
}
