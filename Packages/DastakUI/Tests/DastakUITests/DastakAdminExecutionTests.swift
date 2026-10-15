import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakAdminExecutionTests: XCTestCase {
    func testTracePreservesNullSignedLedgerAndUnknownFields() throws {
        let trace = try decode(adminTrace())
        XCTAssertTrue(trace.financeCurrent)
        XCTAssertTrue(trace.deliveryCurrent)
        XCTAssertNil(trace.failureAndFinance?.record.rows("settlements")?.first?.integer("amountPaise"))
        XCTAssertEqual(trace.root.record("extra")?.integer("signedAmount"), -150)
        XCTAssertEqual(trace.root.record("extra")?.fields["unknown"], .null)
    }
    func testMalformedFinanceLeavesDeliveryAndRawTraceIntact() throws {
        var fixture = adminTraceObject()
        fixture["failureAndFinance"] = ["permissions": [:]]
        let trace = try decode(data(fixture))
        XCTAssertFalse(trace.financeCurrent)
        XCTAssertTrue(trace.deliveryCurrent)
        XCTAssertNotNil(trace.root.record("failureAndFinance"))
    }
    func testMissingPermissionsAndDuplicateFinanceIdentitiesLockActions() throws {
        for duplicate in [false, true] {
            var fixture = adminTraceObject()
            var finance = fixture["failureAndFinance"] as! [String: Any]
            if duplicate { finance["refunds"] = [refundRecord(), refundRecord()] }
            else { finance["permissions"] = ["canProcessRefunds": true] }
            fixture["failureAndFinance"] = finance
            XCTAssertFalse(try decode(data(fixture)).financeCurrent)
        }
    }
    func testFreshnessPermissionsAndImmutableReviewGuard() async throws {
        let (model, functions, _) = await setup()
        let reviewed = try XCTUnwrap(model.trace)
        XCTAssertTrue(model.allowed(refundRequest()))
        XCTAssertFalse(model.allowed(refundRequest(), now: Date().addingTimeInterval(61)))
        await functions.setTrace(adminTrace(permission: false))
        await model.select(adminOrder)
        XCTAssertFalse(model.allowed(refundRequest()))
        XCTAssertFalse(model.allowed(refundRequest(), reviewed: reviewed))
    }
    func testPreparedFoodCannotPhysicallyReturnButCanReviewRefund() async throws {
        let (model, _, _) = await setup(trace: adminTrace(food: true))
        var request = issueRequest("PHYSICAL_RETURN")
        XCTAssertFalse(model.allowed(request))
        request.decision = "REFUND_WITHOUT_RETURN"; request.returnPackageCount = nil
        XCTAssertTrue(model.allowed(request))
    }
    func testExactSKURecoveryRequestDoesNotContainSKUQuantityOrPrice() async throws {
        let (model, _, _) = await setup()
        var request = DastakAdminExecutionRequest(operation: .offer)
        request.recoveryCaseId = adminRecovery; request.branchId = adminBranch; request.expectedVersion = 1
        XCTAssertTrue(model.allowed(request))
        XCTAssertEqual(Set(request.encodedFields.keys), ["operation", "recoveryCaseId", "branchId", "expectedVersion"])
        request.refundId = adminRefund
        XCTAssertFalse(request.valid)
    }
    func testRequestRejectsCrossOperationAndInvalidMoneyAddressOrCount() {
        var request = issueRequest("PHYSICAL_RETURN")
        request.returnPackageCount = 0; XCTAssertFalse(request.valid)
        request.returnPackageCount = 1; request.refundAmountPaise = -1; XCTAssertFalse(request.valid)
        request.refundAmountPaise = 100; request.decision = "RESOLVE_NO_REFUND"; XCTAssertFalse(request.valid)
        var delivery = deliveryRequest()
        delivery.correctedAddress = .init(line1: "", latitude: 12, longitude: 78); XCTAssertFalse(delivery.valid)
        delivery.correctedAddress = .init(line1: "Main Road", latitude: 91, longitude: 78); XCTAssertFalse(delivery.valid)
        delivery.correctedAddress = .init(line1: "Main Road", latitude: 12, longitude: 78); XCTAssertTrue(delivery.valid)
        delivery.action = "RETURN_TO_ORIGIN"; XCTAssertFalse(delivery.valid)
        delivery.correctedAddress = nil; delivery.faultSource = "CUSTOMER"; delivery.refundAmountPaise = 100; XCTAssertFalse(delivery.valid)
    }
    func testSavedBeforeWriteAndRelaunchRetryUsesSameRefundBodyAndKey() async throws {
        let (model, functions, store) = await setup()
        await model.submit(refundRequest(), reviewed: try XCTUnwrap(model.trace))
        let saved = try XCTUnwrap(model.pending)
        let disk = await store.load(adminAccount); XCTAssertEqual(saved, disk)
        let relaunched = makeModel(functions, store); await relaunched.restore()
        await functions.reply(.data(data(["refundId": adminRefund.uuidString, "refundState": "pending"])))
        await relaunched.retry()
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].body, writes[1].body)
        XCTAssertEqual(writes[0].key, writes[1].key)
        XCTAssertEqual(writes[0].endpoint, "dastak-payments")
        XCTAssertNil(relaunched.pending)
        XCTAssertTrue(relaunched.message?.contains("not a completed refund") == true)
    }
    func testSaveFailurePreventsWriteAndLocksWorkspace() async throws {
        let (model, functions, store) = await setup()
        await store.failSave()
        await model.submit(refundRequest(), reviewed: try XCTUnwrap(model.trace))
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(model.blocksActions)
    }
    func testWrongRefundAcknowledgementRetainsOriginal() async throws {
        let (model, functions, _) = await setup()
        await functions.reply(.data(data(["refundId": UUID().uuidString, "refundState": "processed"])))
        await model.submit(refundRequest(), reviewed: try XCTUnwrap(model.trace))
        XCTAssertNotNil(model.pending)
        XCTAssertTrue(model.blocksActions)
    }
    func testKnownRejectionRequiresNewReadWhere429KeepsOriginal() async throws {
        for status in [409, 429] {
            let (model, functions, _) = await setup()
            await functions.reply(.rejected(status))
            await model.submit(refundRequest(), reviewed: try XCTUnwrap(model.trace))
            XCTAssertEqual(model.pending == nil, status == 409)
            XCTAssertFalse(model.current)
            XCTAssertFalse(model.allowed(refundRequest()))
        }
    }
    func testAcknowledgedCleanupFailureDoesNotRepeatProviderCall() async throws {
        let (model, functions, store) = await setup()
        await store.failRemove()
        await functions.reply(.data(data(["refundId": adminRefund.uuidString, "refundState": "processed"])))
        await model.submit(refundRequest(), reviewed: try XCTUnwrap(model.trace))
        XCTAssertTrue(model.pending?.acknowledged == true)
        let relaunched = makeModel(functions, store); await relaunched.restore(); await relaunched.retry()
        let writes = await functions.writes; XCTAssertEqual(writes.count, 1)
        XCTAssertNil(relaunched.pending)
    }
    func testAccountSwitchBeforeWriteNeverSendsAction() async throws {
        let functions = AdminExecutionFunctions(); let store = AdminExecutionStore(); let identity = AdminExecutionIdentity()
        let model = DastakAdminExecutionModel(services: MarketplaceAuthenticatedServices(functions: functions, accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }), storage: store)
        await model.restore(); await model.select(adminOrder)
        let trace = try XCTUnwrap(model.trace)
        await identity.change()
        await model.submit(refundRequest(), reviewed: trace)
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertFalse(model.restored)
    }
    func testSupersededDiskCommandIsNotReplayed() async throws {
        let (model, functions, store) = await setup()
        await model.submit(refundRequest(), reviewed: try XCTUnwrap(model.trace))
        let saved = try XCTUnwrap(model.pending)
        var changed = saved; changed.revision = UUID()
        try await store.replace(changed, accountID: adminAccount, expectedRevision: saved.revision)
        await model.retry()
        let writes = await functions.writes; XCTAssertEqual(writes.count, 1)
        XCTAssertNotNil(model.pending)
    }
    func testWrongOrderReadClearsOldSelectionAndNeverEnablesRefund() async throws {
        let (model, _, _) = await setup()
        await model.select(UUID())
        XCTAssertNil(model.trace)
        XCTAssertFalse(model.allowed(refundRequest()))
    }
    func testPaginatedDirectoryValidatesScopeCursorAndLoadsHistory() async throws {
        let (model, functions, _) = await setup()
        await functions.setPage(data(["orders": [orderRecord()], "scope": "HISTORY", "hasMore": true, "nextCursor": ["updatedAt": adminTime, "orderId": adminOrder.uuidString]]))
        await model.refreshPage(scope: "HISTORY", query: "DSK")
        XCTAssertTrue(model.listCurrent); XCTAssertNotNil(model.cursor)
        await functions.setPage(data(["orders": [], "scope": "HISTORY", "hasMore": false, "nextCursor": NSNull()]))
        await model.refreshPage(append: true)
        XCTAssertEqual(model.orders.count, 1); XCTAssertNil(model.cursor)
        await functions.setPage(data(["orders": [], "scope": "ACTIVE", "hasMore": false]))
        await model.refreshPage(scope: "HISTORY")
        XCTAssertFalse(model.listCurrent)
    }
    func testCursorCycleAndMismatchedTailAreRejected() async throws {
        let (model, functions, _) = await setup()
        let page = data(["orders": [orderRecord()], "scope": "ACTIVE", "hasMore": true, "nextCursor": ["updatedAt": adminTime, "orderId": adminOrder.uuidString]])
        await functions.setPage(page); await model.refreshPage()
        XCTAssertTrue(model.listCurrent)
        await model.refreshPage(append: true)
        XCTAssertFalse(model.listCurrent)
        await functions.setPage(data(["orders": [orderRecord()], "scope": "ACTIVE", "hasMore": true, "nextCursor": ["updatedAt": adminTime, "orderId": UUID().uuidString]]))
        await model.refreshPage(); XCTAssertFalse(model.listCurrent)
    }
    func testOlderSelectionReplyCannotReplaceNewOrder() async throws {
        let (model, functions, _) = await setup()
        await functions.holdNextTrace()
        let old = Task { await model.select(adminOrder) }
        await functions.waitForHold()
        let other = UUID()
        await functions.setTrace(adminTrace(id: other))
        await model.select(other)
        await functions.releaseTrace(adminTrace())
        await old.value
        XCTAssertEqual(model.trace?.order.id, other)
        XCTAssertEqual(model.selectedID, other)
    }
    func testReadCrossingWriteCannotReenableExpiredTrace() async throws {
        let (model, functions, _) = await setup()
        let reviewed = try XCTUnwrap(model.trace)
        await functions.holdNextTrace()
        let read = Task { await model.select(adminOrder) }
        await functions.waitForHold()
        // A read in progress deliberately locks new actions.
        await model.submit(refundRequest(), reviewed: reviewed)
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
        await functions.releaseTrace(adminTrace()); await read.value
    }
    func testAllActionAcknowledgementsRequireTheirExactTargetsAndStates() throws {
        var requests: [(DastakAdminExecutionRequest, [String: Any])] = []
        var offer = DastakAdminExecutionRequest(operation: .offer); offer.recoveryCaseId = adminRecovery; offer.branchId = adminBranch; offer.expectedVersion = 1
        requests.append((offer, ["recoveryCaseId": adminRecovery.uuidString, "branchId": adminBranch.uuidString, "recoveryOpportunityId": UUID().uuidString, "exactSkuId": UUID().uuidString, "quantity": 1, "status": "OFFERED", "expiresAt": adminTime]))
        var fail = DastakAdminExecutionRequest(operation: .fail); fail.recoveryCaseId = adminRecovery; fail.expectedVersion = 1; fail.reason = "No eligible stock"
        requests.append((fail, ["recoveryCaseId": adminRecovery.uuidString, "orderId": adminOrder.uuidString, "status": "RECOVERY_FAILED", "lineStatus": "REFUNDED", "refundId": adminRefund.uuidString]))
        var delivery = deliveryRequest()
        requests.append((delivery, ["recoveryCaseId": adminRecovery.uuidString, "deliveryMissionId": adminMission.uuidString, "action": "RESUME_DELIVERY", "recoveryStatus": "RESOLVED", "missionStatus": "OUT_FOR_DELIVERY"]))
        delivery.action = "RETURN_TO_ORIGIN"
        requests.append((delivery, ["recoveryCaseId": adminRecovery.uuidString, "deliveryMissionId": adminMission.uuidString, "action": "RETURN_TO_ORIGIN", "missionStatus": "DELIVERY_RECOVERY", "returnStatus": "IN_RIDER_CUSTODY", "returnId": UUID().uuidString, "returnMissionId": UUID().uuidString]))
        for decision in ["REJECT", "RESOLVE_NO_REFUND", "REFUND_WITHOUT_RETURN", "PHYSICAL_RETURN"] {
            var request = issueRequest(decision)
            if ["REJECT", "RESOLVE_NO_REFUND"].contains(decision) { request.refundAmountPaise = nil; request.faultSource = nil; request.returnPackageCount = nil }
            var reply: [String: Any] = ["issueId": adminIssue.uuidString, "decision": decision, "issueStatus": decision == "REJECT" ? "REJECTED" : decision == "PHYSICAL_RETURN" ? "UNDER_REVIEW" : "RESOLVED"]
            reply["refundId"] = adminRefund.uuidString; reply["returnId"] = UUID().uuidString; reply["returnMissionId"] = adminMission.uuidString; reply["returnStatus"] = "RIDER_SEARCH"
            requests.append((request, reply))
        }
        var rider = DastakAdminExecutionRequest(operation: .rider); rider.returnMissionId = adminMission; rider.riderId = adminBranch; rider.expectedVersion = 1
        requests.append((rider, ["returnMissionId": adminMission.uuidString, "riderId": adminBranch.uuidString, "returnId": UUID().uuidString, "missionStatus": "ASSIGNED"]))
        requests.append((refundRequest(), ["refundId": adminRefund.uuidString, "refundState": "pending"]))
        var settlement = DastakAdminExecutionRequest(operation: .settlement); settlement.settlementEntryId = adminRefund; settlement.expectedVersion = 1
        requests.append((settlement, ["settlementEntryId": adminRefund.uuidString, "status": "PENDING", "calculationStatus": "CALCULATED", "amountPaise": -100, "currency": "INR", "version": 1]))
        var handoff = DastakAdminExecutionRequest(operation: .handoff); handoff.missionId = adminMission; handoff.deliveryEvidenceId = adminBranch; handoff.expectedMissionVersion = 1; handoff.reason = "Evidence confirms complete handoff"
        requests.append((handoff, ["exceptionalHandoffAuthorizationId": UUID().uuidString, "completedMission": ["id": adminMission.uuidString, "orderId": adminOrder.uuidString, "status": "DELIVERED", "verificationStatus": "OVERRIDDEN"]]))
        var cancel = DastakAdminExecutionRequest(operation: .cancel); cancel.orderId = adminOrder; cancel.expectedVersion = 1; cancel.reason = "Customer requests cancellation"
        requests.append((cancel, ["status": "CANCELLED", "version": 2, "cancelledAt": adminTime]))
        for (request, reply) in requests {
            let command = DastakAdminExecutionCommand(accountID: adminAccount, orderID: adminOrder, key: adminKey(), request: request, relatedMissionID: adminMission, currency: "INR", approvedAmountPaise: 100)
            XCTAssertTrue(request.valid, request.operation.rawValue)
            XCTAssertTrue(DastakAdminExecutionModel.acknowledges(command, try record(reply)), request.operation.rawValue)
            XCTAssertFalse(DastakAdminExecutionModel.acknowledges(command, try record([:])), request.operation.rawValue)
        }
    }
    func testFileJournalProtectsAccountAndCompareAndSwap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DastakAdminExecutionFileStore(directory: directory)
        let command = DastakAdminExecutionCommand(accountID: adminAccount, orderID: adminOrder, key: adminKey(), request: refundRequest(), currency: "INR", approvedAmountPaise: 100)
        try await store.replace(command, accountID: adminAccount, expectedRevision: nil)
        let saved = try await store.load(adminAccount); XCTAssertEqual(saved, command)
        let other = try await store.load(UUID()); XCTAssertNil(other)
        do { try await store.replace(nil, accountID: adminAccount, expectedRevision: nil); XCTFail("stale deletion accepted") } catch {}
        let file = directory.appendingPathComponent(adminAccount.uuidString.lowercased() + ".json")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        try await store.replace(nil, accountID: adminAccount, expectedRevision: command.revision)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testUntraceableEvidenceCannotRequestDownloadURL() async throws {
        let (model, functions, _) = await setup()
        do { _ = try await model.evidenceURL(path: "other-account/photo.jpg", reviewed: try XCTUnwrap(model.trace)); XCTFail("unknown evidence accepted") } catch {}
        let downloads = await functions.downloads; XCTAssertEqual(downloads, 0)
    }
    func testOrderOnlyProcessedRefundRequiresExactCompletedTrace() async throws {
        for complete in [false, true] {
            let (model, functions, _) = await setup()
            let reviewed = try XCTUnwrap(model.trace)
            if complete {
                var fixture = adminTraceObject(); var finance = fixture["failureAndFinance"] as! [String: Any]
                var refund = refundRecord(); refund["status"] = "COMPLETED"; refund["completedAt"] = adminTime
                finance["refunds"] = [refund]; fixture["failureAndFinance"] = finance
                await functions.setTrace(data(fixture))
            }
            await functions.reply(.data(data(["orderId": adminOrder.uuidString, "refundState": "processed"])))
            await model.submit(refundRequest(), reviewed: reviewed)
            XCTAssertEqual(model.pending == nil, complete)
        }
    }
    func testCompletedRefundDoesNotInferWrongAmountCurrencyOrMissingCompletion() throws {
        let command = DastakAdminExecutionCommand(accountID: adminAccount, orderID: adminOrder, key: adminKey(), request: refundRequest(), currency: "INR", approvedAmountPaise: 100)
        for field in ["amountPaise", "currency", "completedAt", "id"] {
            var fixture = adminTraceObject(); var finance = fixture["failureAndFinance"] as! [String: Any]
            var refund = refundRecord(); refund["status"] = "COMPLETED"; refund["completedAt"] = adminTime
            switch field {
            case "amountPaise": refund[field] = 99
            case "currency": refund[field] = "USD"
            case "id": refund[field] = UUID().uuidString
            default: refund.removeValue(forKey: field)
            }
            finance["refunds"] = [refund]; fixture["failureAndFinance"] = finance
            XCTAssertFalse(DastakAdminExecutionModel.completedRefund(command, trace: try decode(data(fixture))))
        }
    }
    func testSettlementEligibleAcknowledgementPreservesCurrencyAndVersion() throws {
        var request = DastakAdminExecutionRequest(operation: .settlement); request.settlementEntryId = adminRefund; request.expectedVersion = 1
        let command = DastakAdminExecutionCommand(accountID: adminAccount, orderID: adminOrder, key: adminKey(), request: request, currency: "INR")
        var reply: [String: Any] = ["settlementEntryId": adminRefund.uuidString, "status": "ELIGIBLE", "calculationStatus": "CALCULATED", "amountPaise": 0, "currency": "INR", "version": 2]
        XCTAssertTrue(DastakAdminExecutionModel.acknowledges(command, try record(reply)))
        reply["currency"] = "USD"; XCTAssertFalse(DastakAdminExecutionModel.acknowledges(command, try record(reply)))
    }
    func testDeliveryRecoveryRequiresAssignedMissionAndForbidsFoodReturn() async throws {
        for food in [false, true] {
            var fixture = adminTraceObject(food: food)
            var finance = fixture["failureAndFinance"] as! [String: Any]
            finance["recoveryCases"] = [["id": adminRecovery.uuidString, "version": 1, "type": "DELIVERY", "status": "ACTION_REQUIRED", "deliveryMissionId": adminMission.uuidString]]
            fixture["failureAndFinance"] = finance
            var delivery = fixture["delivery"] as! [String: Any]
            delivery["mission"] = ["id": adminMission.uuidString, "status": "DELIVERY_RECOVERY", "version": 1, "assignedRiderId": adminBranch.uuidString]
            fixture["delivery"] = delivery
            let (model, functions, _) = await setup(trace: data(fixture))
            var request = deliveryRequest()
            XCTAssertTrue(model.allowed(request))
            request.action = "RETURN_TO_ORIGIN"
            XCTAssertEqual(model.allowed(request), !food)
            delivery["mission"] = ["id": UUID().uuidString, "status": "DELIVERY_RECOVERY", "version": 1, "assignedRiderId": adminBranch.uuidString]
            fixture["delivery"] = delivery; await functions.setTrace(data(fixture)); await model.select(adminOrder)
            request.action = "RESUME_DELIVERY"; XCTAssertFalse(model.allowed(request))
        }
    }
    func testReturnAssignmentRequiresUnassignedPhysicalRiderSearch() async throws {
        var fixture = adminTraceObject(); var finance = fixture["failureAndFinance"] as! [String: Any]
        finance["returns"] = [["id": adminRecovery.uuidString, "version": 1, "status": "RIDER_SEARCH", "physicalReturnRequired": true, "mission": ["id": adminMission.uuidString, "status": "RIDER_SEARCH", "version": 1]]]
        fixture["failureAndFinance"] = finance
        let (model, functions, _) = await setup(trace: data(fixture))
        var request = DastakAdminExecutionRequest(operation: .rider); request.returnMissionId = adminMission; request.expectedVersion = 1; request.riderId = adminBranch
        XCTAssertTrue(model.allowed(request))
        finance["returns"] = [["id": adminRecovery.uuidString, "version": 1, "status": "CUSTOMER_PICKUP", "physicalReturnRequired": true, "mission": ["id": adminMission.uuidString, "status": "ASSIGNED", "version": 2, "assignedRiderId": adminBranch.uuidString]]]
        fixture["failureAndFinance"] = finance; await functions.setTrace(data(fixture)); await model.select(adminOrder)
        XCTAssertFalse(model.allowed(request))
    }
    func testExceptionalHandoffNeedsCapabilityArrivalVersionAndEvidence() async throws {
        var fixture = adminTraceObject(); var delivery = fixture["delivery"] as! [String: Any]
        delivery["canAuthorizeExceptionalHandoff"] = true
        delivery["mission"] = ["id": adminMission.uuidString, "status": "ARRIVED", "version": 1]
        delivery["deliveryEvidence"] = [["id": adminBranch.uuidString, "objectPath": "delivery/test.jpg"]]
        fixture["delivery"] = delivery
        let (model, functions, _) = await setup(trace: data(fixture))
        var request = DastakAdminExecutionRequest(operation: .handoff); request.missionId = adminMission; request.deliveryEvidenceId = adminBranch; request.expectedMissionVersion = 1; request.reason = "Reviewed physical handoff evidence"
        XCTAssertTrue(model.allowed(request))
        request.deliveryEvidenceId = UUID(); XCTAssertFalse(model.allowed(request))
        request.deliveryEvidenceId = adminBranch; request.expectedMissionVersion = 2; XCTAssertFalse(model.allowed(request))
        request.expectedMissionVersion = 1
        delivery["canAuthorizeExceptionalHandoff"] = false; fixture["delivery"] = delivery
        await functions.setTrace(data(fixture)); await model.select(adminOrder); XCTAssertFalse(model.allowed(request))
    }
    func testSameVersionTraceChangeInvalidatesReviewedIntent() async throws {
        let (model, functions, _) = await setup()
        let reviewed = try XCTUnwrap(model.trace)
        var fixture = adminTraceObject(); fixture["extra"] = ["newEvidence": true]
        await functions.setTrace(data(fixture)); await model.select(adminOrder)
        XCTAssertTrue(model.allowed(refundRequest()))
        XCTAssertFalse(model.allowed(refundRequest(), reviewed: reviewed))
    }
    func testLateReadCrossingSavedRetryCannotRestoreCurrentTrace() async throws {
        let (model, functions, _) = await setup()
        await model.submit(refundRequest(), reviewed: try XCTUnwrap(model.trace))
        await functions.holdNextTrace()
        let old = Task { await model.select(adminOrder) }
        await functions.waitForHold()
        await functions.reply(.data(data(["refundId": adminRefund.uuidString, "refundState": "processed"])))
        await model.retry()
        await functions.releaseTrace(adminTrace()); await old.value
        XCTAssertNil(model.pending)
        XCTAssertFalse(model.current)
    }
    private func setup(trace: Data = adminTrace()) async -> (DastakAdminExecutionModel, AdminExecutionFunctions, AdminExecutionStore) {
        let functions = AdminExecutionFunctions(); await functions.setTrace(trace)
        let store = AdminExecutionStore(); let model = makeModel(functions, store)
        await model.restore(); await model.select(adminOrder)
        return (model, functions, store)
    }
    private func makeModel(_ functions: AdminExecutionFunctions, _ store: AdminExecutionStore) -> DastakAdminExecutionModel {
        .init(services: MarketplaceAuthenticatedServices(functions: functions, accountIDProvider: { adminAccount }, objectUploader: { _, _, _, _, _ in }), storage: store)
    }
    private func decode(_ data: Data) throws -> DastakV1AdminExecutionTrace { try JSONDecoder().decode(DastakV1AdminExecutionTrace.self, from: data) }
    private func record(_ object: [String: Any]) throws -> DastakAdminTraceRecord { try JSONDecoder().decode(DastakAdminTraceRecord.self, from: data(object)) }
}

private actor AdminExecutionIdentity { var id = adminAccount; func change() { id = UUID() } }
private actor AdminExecutionStore: DastakAdminExecutionStorage {
    private var command: DastakAdminExecutionCommand?
    private var saveFails = false
    private var removeFails = false
    func failSave() { saveFails = true }
    func failRemove() { removeFails = true }
    func load(_ id: UUID) -> DastakAdminExecutionCommand? { command?.accountID == id ? command : nil }
    func replace(_ next: DastakAdminExecutionCommand?, accountID: UUID, expectedRevision: UUID?) throws {
        guard command?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        if next == nil && removeFails { removeFails = false; throw URLError(.cannotWriteToFile) }
        if next != nil && saveFails { saveFails = false; throw URLError(.cannotWriteToFile) }
        command = next
    }
}
private actor AdminExecutionFunctions: FunctionClient {
    enum Reply: Sendable { case data(Data), rejected(Int) }
    struct Write: Sendable { let endpoint: String; let body: Data; let key: String }
    var writes: [Write] = []
    var downloads = 0
    private var trace = adminTrace()
    private var page = data(["orders": [], "scope": "ACTIVE", "hasMore": false])
    private var replies: [Reply] = []
    private var hold = false
    private var continuation: CheckedContinuation<Data, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    func setTrace(_ data: Data) { trace = data }
    func setPage(_ data: Data) { page = data }
    func reply(_ reply: Reply) { replies.append(reply) }
    func holdNextTrace() { hold = true }
    func waitForHold() async { if continuation == nil { await withCheckedContinuation { waiting = $0 } } }
    func releaseTrace(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(request)
        let operation = (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["operation"] as? String
        if operation == "adminExecutionTrace" {
            var reply = trace
            if hold { hold = false; reply = await withCheckedContinuation { continuation = $0; waiting?.resume(); waiting = nil } }
            return try JSONDecoder().decode(Response.self, from: reply)
        }
        if operation == "adminExecutionOrders" { return try JSONDecoder().decode(Response.self, from: page) }
        if name == "issue-evidence-url" { downloads += 1; throw URLError(.timedOut) }
        writes.append(.init(endpoint: name, body: body, key: idempotencyKey.rawValue))
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        switch replies.removeFirst() {
        case let .data(reply): return try JSONDecoder().decode(Response.self, from: reply)
        case let .rejected(status): throw FunctionClientError.api(statusCode: status, code: "fixture_rejection", message: "Test rejection")
        }
    }
}
private let adminAccount = UUID(uuidString: "96000000-0000-4000-8000-000000000001")!
private let adminOrder = UUID(uuidString: "96000000-0000-4000-8000-000000000002")!
private let adminRefund = UUID(uuidString: "96000000-0000-4000-8000-000000000003")!
private let adminRecovery = UUID(uuidString: "96000000-0000-4000-8000-000000000004")!
private let adminIssue = UUID(uuidString: "96000000-0000-4000-8000-000000000005")!
private let adminBranch = UUID(uuidString: "96000000-0000-4000-8000-000000000006")!
private let adminMission = UUID(uuidString: "96000000-0000-4000-8000-000000000007")!
private let adminTime = "2026-10-11T00:00:00Z"
private func adminKey() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
private func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
private func orderRecord(_ id: UUID = adminOrder, food: Bool = false) -> [String: Any] { ["id": id.uuidString, "displayOrderNumber": "DSK-TEST", "orderType": food ? "RESTAURANT_ONLY" : "RETAIL_ONLY", "status": "PAID", "version": 1, "updatedAt": adminTime] }
private func refundRecord() -> [String: Any] { ["id": adminRefund.uuidString, "status": "APPROVED", "version": 1, "amountPaise": 100, "currency": "INR"] }
private func adminTraceObject(id: UUID = adminOrder, permission: Bool = true, food: Bool = false) -> [String: Any] {
    ["order": orderRecord(id, food: food), "launchPayment": NSNull(), "cancellation": ["canCancel": false],
     "extra": ["signedAmount": -150, "unknown": NSNull()],
     "failureAndFinance": [
        "permissions": ["canManageRecovery": permission, "canApproveReturns": permission, "canApproveRefunds": permission, "canProcessRefunds": permission, "canManageSettlements": permission],
        "recoveryCases": [["id": adminRecovery.uuidString, "type": "EXACT_SKU", "status": "SEARCHING_EXACT_SKU", "version": 1]],
        "customerIssues": [["id": adminIssue.uuidString, "status": "OPEN", "version": 1, "preparedFood": food, "physicalReturnAllowed": !food, "evidence": []]],
        "returns": [], "refunds": [refundRecord()],
        "settlements": [["id": adminRefund.uuidString, "status": "PENDING", "version": 1, "currency": "INR", "amountPaise": NSNull()]],
        "platformFees": [], "royaltyLedger": [], "royaltyBalances": [], "withdrawals": []
     ],
     "delivery": ["canAuthorizeExceptionalHandoff": false, "mission": NSNull(), "offers": [], "pickupStops": [], "verification": [], "custody": [], "problems": [], "deliveryEvidence": [], "exceptionalHandoffs": []]]
}
private func adminTrace(id: UUID = adminOrder, permission: Bool = true, food: Bool = false) -> Data { data(adminTraceObject(id: id, permission: permission, food: food)) }
private func refundRequest() -> DastakAdminExecutionRequest { var r = DastakAdminExecutionRequest(operation: .refund); r.orderId = adminOrder; r.refundId = adminRefund; r.entityType = "dastak_v1_order"; return r }
private func issueRequest(_ decision: String) -> DastakAdminExecutionRequest {
    var r = DastakAdminExecutionRequest(operation: .issue); r.issueId = adminIssue; r.expectedVersion = 1; r.decision = decision; r.reason = "Reviewed evidence and customer issue"; r.refundAmountPaise = 100; r.faultSource = "DASTAK"; r.returnPackageCount = decision == "PHYSICAL_RETURN" ? 1 : nil; return r
}
private func deliveryRequest() -> DastakAdminExecutionRequest { var r = DastakAdminExecutionRequest(operation: .delivery); r.recoveryCaseId = adminRecovery; r.expectedVersion = 1; r.reason = "Verified corrected delivery instruction"; r.action = "RESUME_DELIVERY"; r.faultSource = "DASTAK"; return r }
