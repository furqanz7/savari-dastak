import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantOperationTests: XCTestCase {
    private let account = UUID()

    private func model(_ functions: OperationFunctions, store: any DastakMerchantJournalStorage,
        uploads: OperationUploads = OperationUploads()) -> DastakMerchantModel {
        DastakMerchantModel(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { [account] in account },
            objectUploader: { bucket, path, data, type, _ in await uploads.record(bucket, path, data, type) }),
            journalStorage: store, requestTimeout: .milliseconds(80))
    }

    func testPackageTimeoutRelaunchReplaysOriginalCountVersionAndKey() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let first = model(functions, store: store); await first.refreshOrders()
        let order = try XCTUnwrap(first.v1Fulfilments.first)
        await first.declareV1Packages(order, count: 2)
        XCTAssertNil(first.busyIdentity); XCTAssertNotNil(first.pendingOperationCommand)
        await first.declareV1Packages(order, count: 9)
        let restored = model(functions, store: store); await restored.restoreMerchantCommands()
        await restored.retryMerchantJournal()
        let calls = await functions.writes
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0], calls[1])
        let body = try object(calls[0].body)
        XCTAssertEqual(body["packageCount"] as? Int, 2)
        XCTAssertEqual(body["expectedVersion"] as? Int, 3)
    }

    func testInvalidPackageCountExplainsIssueWithoutSecuringOrSendingCommand() async throws {
        let functions = OperationFunctions(), merchant = model(functions, store: MerchantJournalTestStore())
        await merchant.refreshOrders()
        let order = try XCTUnwrap(merchant.v1Fulfilments.first)
        for count in [0, -1, 1001] {
            await merchant.declareV1Packages(order, count: count)
            XCTAssertEqual(merchant.errorMessage, DastakMerchantValidation.packageHelp)
            XCTAssertNil(merchant.merchantJournal); XCTAssertNil(merchant.busyIdentity)
        }
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
    }
    func testMaximumPackageCountUsesExistingJournalAndExactServerValue() async throws {
        let functions = OperationFunctions(), merchant = model(functions, store: MerchantJournalTestStore())
        await merchant.refreshOrders()
        await functions.enqueue(.data(operationFulfilment(version: 4, count: 1000)))
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 1000)
        let writes = await functions.writes
        XCTAssertEqual(try object(XCTUnwrap(writes.first).body)["packageCount"] as? Int, 1000)
        XCTAssertNil(merchant.pendingOperationCommand)
    }

    func testWriteCannotStartIfJournalSaveFails() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let merchant = model(functions, store: store); await merchant.refreshOrders(); await store.failSave()
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 2)
        let writes = await functions.writes
        XCTAssertTrue(writes.isEmpty); XCTAssertTrue(merchant.isBusy)
        XCTAssertFalse(merchant.merchantJournalRestored)
    }

    func testWrongReceiptRetainsCommandRatherThanClaimingSuccess() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let merchant = model(functions, store: store); await merchant.refreshOrders()
        await functions.enqueue(.data(operationFulfilment(version: 4, count: 99)))
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 2)
        XCTAssertNotNil(merchant.merchantJournal); XCTAssertNil(merchant.notice)
        XCTAssertNil(merchant.busyIdentity)
    }

    func testAcknowledgedCleanupFailureNeverRepeatsWrite() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let merchant = model(functions, store: store); await merchant.refreshOrders()
        await functions.enqueue(.data(operationFulfilment(version: 4, count: 2))); await store.failRemoval()
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 2)
        XCTAssertEqual(merchant.merchantJournal?.acknowledged, true)
        let restored = model(functions, store: store); await restored.restoreMerchantCommands()
        await restored.retryMerchantJournal()
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 1); XCTAssertNil(restored.merchantJournal)
    }

    func testLaterRejectionDoesNotEraseEarlierUnknownOutcome() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let merchant = model(functions, store: store); await merchant.refreshOrders()
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 2)
        await functions.enqueue(.api(404)); await merchant.retryMerchantJournal()
        XCTAssertEqual(merchant.merchantJournal?.attempts, 2)
        XCTAssertNotNil(merchant.pendingOperationCommand)
    }

    func testFirstDefinitiveRejectionClearsOnlyItsOriginalCommand() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let merchant = model(functions, store: store); await merchant.refreshOrders()
        await functions.enqueue(.api(409))
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 2)
        XCTAssertNil(merchant.merchantJournal); XCTAssertNil(merchant.busyIdentity)
    }

    func testReadyPhotoRelaunchUsesSecuredBytesPathAndSkipsCompletedUpload() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore(), uploads = OperationUploads()
        let merchant = model(functions, store: store, uploads: uploads); await merchant.refreshOrders()
        await merchant.addV1ReadyEvidence(try XCTUnwrap(merchant.v1Fulfilments.first), data: Data([1, 2, 3]),
            contentType: "image/jpeg", fileExtension: "jpg")
        let saved = try XCTUnwrap(merchant.merchantJournal)
        XCTAssertEqual(saved.uploadCompleted, true)
        let restored = model(functions, store: store, uploads: uploads); await restored.restoreMerchantCommands()
        await restored.retryMerchantJournal()
        let files = await uploads.files, calls = await functions.writes
        XCTAssertEqual(files.count, 1); XCTAssertEqual(files[0].data, Data([1, 2, 3]))
        XCTAssertTrue(files[0].path.hasPrefix("merchant-ready/\(account.uuidString.lowercased())/"))
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0], calls[1])
        XCTAssertEqual(try object(calls[0].body)["objectPath"] as? String, files[0].path)
    }

    func testJournalTargetDoesNotRetainPickupPINOrRiderData() async throws {
        let fulfilment = try JSONDecoder().decode(DastakV1MerchantFulfilment.self, from: operationFulfilment())
        let command = DastakMerchantOperationCommand(operation: .packages(.init(fulfilment), count: 2),
            key: IdempotencyKey(rawValue: UUID().uuidString)!)
        let text = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        XCTAssertFalse(text.contains("1234")); XCTAssertFalse(text.contains("pickupCode"))
        XCTAssertFalse(text.contains("delivery")); XCTAssertTrue(command.valid)
    }

    func testUploadFromAnotherAccountCannotEnterProtectedJournal() async throws {
        let order = try JSONDecoder().decode(DastakV1MerchantFulfilment.self, from: operationFulfilment())
        let upload = DastakMerchantOperationCommand.Upload(path: "merchant-ready/\(UUID().uuidString.lowercased())/photo.jpg",
            bucket: "dastak-evidence", data: Data([1]), contentType: "image/jpeg")
        let record = DastakMerchantJournalRecord(accountID: account, command: .operation(.init(
            operation: .evidence(.init(order), upload), key: IdempotencyKey(rawValue: UUID().uuidString)!)))
        XCTAssertFalse(record.valid)
        do {
            try await DastakMerchantMemoryJournal().replace(record, accountID: account, expectedRevision: nil)
            XCTFail("A foreign upload path was accepted")
        } catch {}
    }

    func testAutomaticRecoveryHasBackoffAndBudgetWithManualRetryStillAvailable() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let merchant = model(functions, store: store); await merchant.refreshOrders()
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 2)
        let now = Date().addingTimeInterval(60)
        for _ in 0..<3 { await merchant.recoverPendingActionIfNeeded(now: now) }
        let first = await functions.writes; XCTAssertEqual(first.count, 2)
        for minute in 1...10 { await merchant.recoverPendingActionIfNeeded(now: now.addingTimeInterval(Double(minute * 60))) }
        let bounded = await functions.writes; XCTAssertEqual(bounded.count, 6)
        await merchant.retryMerchantJournal()
        let manual = await functions.writes; XCTAssertEqual(manual.count, 7)
        XCTAssertTrue(manual.allSatisfy { $0 == manual[0] })
    }

    func testIdentityChangePreventsReplayAndPreservesOriginalAccountFile() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore(), identity = MerchantJournalTestIdentity()
        let originalID = await identity.id
        let merchant = DastakMerchantModel(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }), journalStorage: store)
        await merchant.refreshOrders()
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 2)
        await identity.change(); await merchant.retryMerchantJournal()
        let writes = await functions.writes, original = try await store.load(originalID)
        XCTAssertEqual(writes.count, 1); XCTAssertNotNil(original)
        XCTAssertFalse(merchant.merchantJournalRestored); XCTAssertTrue(merchant.v1Fulfilments.isEmpty)
    }

    func testExpiredSessionIsExplicitAndDoesNotEraseUnknownAction() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let merchant = model(functions, store: store); await merchant.refreshOrders()
        await merchant.declareV1Packages(try XCTUnwrap(merchant.v1Fulfilments.first), count: 2)
        await functions.enqueue(.api(401)); await merchant.retryMerchantJournal()
        XCTAssertTrue(merchant.sessionNeedsAttention); XCTAssertNotNil(merchant.merchantJournal)
        await merchant.recoverPendingActionIfNeeded(now: .distantFuture)
        let writes = await functions.writes; XCTAssertEqual(writes.count, 2)
    }

    func testAdditiveJournalCodecLoadsOlderRecordWithoutUploadStage() throws {
        let command = DastakMerchantRestaurantCommand(branchID: UUID(), key: IdempotencyKey(rawValue: UUID().uuidString)!,
            operation: .operating(isOpen: false, acceptingOrders: false, expectedVersion: 1))
        let original = DastakMerchantJournalRecord(accountID: account, command: .restaurant(command))
        var json = try object(JSONEncoder().encode(original)); json.removeValue(forKey: "uploadCompleted")
        let decoded = try JSONDecoder().decode(DastakMerchantJournalRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original); XCTAssertTrue(decoded.valid)
    }

    func testDeadlineReleasesActionEvenIfTransportIgnoresCancellationAndLateReceiptCannotClearJournal() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore()
        let merchant = model(functions, store: store); await merchant.refreshOrders()
        let order = try XCTUnwrap(merchant.v1Fulfilments.first)
        await functions.suspendNextWrite()
        let task = Task { await merchant.declareV1Packages(order, count: 2) }
        await functions.waitUntilSuspended()
        await task.value
        XCTAssertNil(merchant.busyIdentity); XCTAssertNotNil(merchant.pendingOperationCommand)
        let retained = merchant.merchantJournal
        await functions.release(operationFulfilment(version: 4, count: 2))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(merchant.merchantJournal, retained)
        XCTAssertEqual(merchant.v1Fulfilments.first?.version, 3)
        let singleAttempt = await functions.allWritesSingleAttempt
        XCTAssertTrue(singleAttempt)
    }

    func testPhotoBytesCannotUploadIfJournalSaveFails() async throws {
        let functions = OperationFunctions(), store = MerchantJournalTestStore(), uploads = OperationUploads()
        let merchant = model(functions, store: store, uploads: uploads); await merchant.refreshOrders()
        await store.failSave()
        await merchant.addV1ReadyEvidence(try XCTUnwrap(merchant.v1Fulfilments.first), data: Data([9]),
            contentType: "image/jpeg", fileExtension: "jpg")
        let files = await uploads.files, writes = await functions.writes
        XCTAssertTrue(files.isEmpty); XCTAssertTrue(writes.isEmpty)
    }

    func testStockAndOperatingRelaunchKeepOriginalPayloadAndKey() async throws {
        let branch = UUID(), sku = UUID()
        let operations: [DastakMerchantOperationCommand.Operation] = [
            .selections(branchID: branch, [.init(skuID: sku, selected: true, expectedVersion: 7, stockQuantity: 12)]),
            .operating(branchID: branch, open: true, accepting: false, version: 9)
        ]
        for operation in operations {
            let functions = OperationFunctions(), store = MerchantJournalTestStore()
            let record = DastakMerchantJournalRecord(accountID: account,
                command: .operation(.init(operation: operation, key: IdempotencyKey(rawValue: UUID().uuidString)!)))
            try await store.replace(record, accountID: account, expectedRevision: nil)
            let first = model(functions, store: store); await first.restoreMerchantCommands(); await first.retryMerchantJournal()
            let restored = model(functions, store: store); await restored.restoreMerchantCommands(); await restored.retryMerchantJournal()
            let calls = await functions.writes
            XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0], calls[1])
            if case .selections = operation {
                let selections = try XCTUnwrap(try object(calls[0].body)["selections"] as? [[String: Any]])
                XCTAssertEqual(selections[0]["stockQuantity"] as? Int, 12)
                XCTAssertEqual(selections[0]["expectedVersion"] as? Int, 7)
            }
        }
    }

    func testMatchingStockReceiptAcknowledgesOriginalBatch() async throws {
        let branch = UUID(), sku = UUID(), functions = OperationFunctions(), store = MerchantJournalTestStore()
        let command = DastakMerchantOperationCommand(operation: .selections(branchID: branch,
            [.init(skuID: sku, selected: true, expectedVersion: 7, stockQuantity: 12)]),
            key: IdempotencyKey(rawValue: UUID().uuidString)!)
        try await store.replace(.init(accountID: account, command: .operation(command)), accountID: account, expectedRevision: nil)
        await functions.enqueue(.data(Data("""
        {"branchId":"\(branch)","updatedCount":1,"selections":[{"branchId":"\(branch)","skuId":"\(sku)","selected":true,"state":"ACTIVE","version":8,"updatedAt":"2026-10-18T00:00:00Z"}]}
        """.utf8)))
        let merchant = model(functions, store: store); await merchant.restoreMerchantCommands()
        let success = await merchant.retryOperationCommand()
        XCTAssertTrue(success); XCTAssertNil(merchant.merchantJournal)
        XCTAssertNotNil(merchant.catalogueRefreshFailure, "A failed follow-up read must not pretend the save itself failed.")
    }

    func testLegacyDraftCodecPreservesCreationIdentityAndUpload() throws {
        var draft = DastakMerchantProductDraft(categoryID: UUID())
        draft.name = "Tea"; draft.priceRupees = "12.50"; draft.unitLabel = "1 pack"
        let upload = DastakMerchantOperationCommand.Upload(path: "merchant/\(account.uuidString.lowercased())/photo.jpg",
            bucket: "dastak-catalogue", data: Data([1, 3, 5]), contentType: "image/jpeg")
        let operations: [DastakMerchantOperationCommand.Operation] = [
            .legacyProduct(draft, paise: 1250, upload: upload),
            .legacyCategory(id: nil, name: "Drinks", sort: 2, active: true),
            .legacyStore(name: "Test store", address: "Store street", location: .init(latitude: 12, longitude: 78), published: true, accepting: false),
            .legacyOrder(.reject, orderID: UUID(), version: 2, reason: "Unavailable")
        ]
        for operation in operations {
            let original = DastakMerchantJournalRecord(accountID: account,
                command: .operation(.init(operation: operation, key: IdempotencyKey(rawValue: UUID().uuidString)!)))
            let decoded = try JSONDecoder().decode(DastakMerchantJournalRecord.self, from: JSONEncoder().encode(original))
            XCTAssertTrue(decoded.valid); XCTAssertEqual(decoded, original)
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor OperationUploads {
    struct File: Sendable { let bucket: String; let path: String; let data: Data; let type: String }
    var files: [File] = []
    func record(_ bucket: String, _ path: String, _ data: Data, _ type: String) { files.append(.init(bucket: bucket, path: path, data: data, type: type)) }
}

private actor OperationFunctions: FunctionClient {
    struct Call: Equatable, Sendable { let key: String; let body: Data }
    enum Result: Sendable { case data(Data), api(Int) }
    var writes: [Call] = []
    var allWritesSingleAttempt = true
    private var results: [Result] = []
    private var suspendWrite = false
    private var suspended: CheckedContinuation<Data, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func enqueue(_ result: Result) { results.append(result) }
    func suspendNextWrite() { suspendWrite = true }
    func waitUntilSuspended() async {
        if suspended != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release(_ data: Data) { suspended?.resume(returning: data); suspended = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let operation = body?["operation"] as? String ?? name
        let json: Data
        switch operation {
        case "merchantFulfilments":
            json = Data("{\"fulfilments\":[\(String(decoding: operationFulfilment(), as: UTF8.self))],\"recoveryOpportunities\":[],\"returnReceipts\":[],\"settlements\":[]}".utf8)
        case "merchantOpportunities": json = Data("{\"opportunities\":[]}".utf8)
        case "restaurantRequests": json = Data("{\"requests\":[]}".utf8)
        case "declareFulfilmentPackages", "addFulfilmentReadyEvidence", "markFulfilmentReady", "updateMerchantSelections", "updateBranchOperationalState":
            writes.append(.init(key: idempotencyKey.rawValue, body: data))
            allWritesSingleAttempt = allWritesSingleAttempt && request is any SingleAttemptFunctionRequest
            if suspendWrite {
                suspendWrite = false
                json = await withCheckedContinuation { suspended = $0; started?.resume(); started = nil }
                break
            }
            guard !results.isEmpty else { throw URLError(.timedOut) }
            switch results.removeFirst() {
            case let .data(value): json = value
            case let .api(status): throw FunctionClientError.api(statusCode: status, code: "stale_version", message: "Fixture rejection")
            }
        default: throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: json)
    }
}

private func operationFulfilment(version: Int = 3, count: Int? = nil) -> Data {
    Data("""
    {"id":"91000000-0000-4000-8000-000000000005","orderId":"91000000-0000-4000-8000-000000000004","displayOrderNumber":"DSK-002","orderStatus":"PREPARING","status":"PREPARING","version":\(version),"branch":{"id":"91000000-0000-4000-8000-000000000001","displayName":"Test store"},"promisedPrepMinutes":15,"secondsRemaining":120,"runningLate":false,"evidence":[],"packageCount":\(count.map(String.init) ?? "null"),"canDeclarePackages":true,"canAddEvidence":true,"canMarkReady":false,"lines":[],"delivery":{"riderAssigned":true,"pickupCode":"1234"}}
    """.utf8)
}
