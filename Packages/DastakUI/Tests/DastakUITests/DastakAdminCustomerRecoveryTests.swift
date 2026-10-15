import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakAdminCustomerRecoveryTests: XCTestCase {
    func testReadOnlyDirectoryUsesServerSearchAndCompleteSessionProjection() async throws {
        let (model, functions, _) = await setup()
        XCTAssertTrue(model.current)
        XCTAssertEqual(model.rows.first?.activeSessionCount, 1)
        await model.load(query: "  test@example.invalid  ")
        let lastRead = await functions.lastRead()
        let request = try object(try XCTUnwrap(lastRead))
        XCTAssertEqual(request["query"] as? String, "test@example.invalid")
        XCTAssertEqual(request["limit"] as? Int, 40)
        XCTAssertEqual(request["operation"] as? String, "adminCustomerRecoveryPage")
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
    }
    func testConfirmationFreshnessAndActiveCustomerRequired() async throws {
        let (model, _, _) = await setup()
        let intent = try phoneIntent(model)
        XCTAssertTrue(model.canConfirm(intent, reason: "Customer request", confirmation: replacement, acknowledged: true))
        XCTAssertFalse(model.canConfirm(intent, reason: "Customer request", confirmation: replacement, acknowledged: false))
        XCTAssertFalse(model.canConfirm(intent, reason: "Customer request", confirmation: "wrong", acknowledged: true))
        XCTAssertFalse(model.canConfirm(intent, reason: "Customer request", confirmation: replacement, acknowledged: true, now: Date().addingTimeInterval(61)))
        XCTAssertFalse(model.canConfirm(intent, reason: "  ", confirmation: replacement, acknowledged: true))
        model.markStale()
        XCTAssertFalse(model.canConfirm(intent, reason: "Customer request", confirmation: replacement, acknowledged: true))
    }
    func testMissingClaimDisablesPhoneNotSessionRecovery() async throws {
        let (model, _, _) = await setup(page: recoveryPage(claimVersion: 0))
        let intent = try phoneIntent(model)
        XCTAssertFalse(model.canConfirm(intent, reason: "Customer request", confirmation: replacement, acknowledged: true))
        let session = DastakAdminCustomerRecoveryIntent(row: try XCTUnwrap(model.rows.first), action: .sessions, sessionID: recoverySession, replacementPhone: nil)
        XCTAssertTrue(model.canConfirm(session, reason: "Lost device", confirmation: recoveryCustomer.uuidString, acknowledged: true))
    }
    func testSameVersionRowChangeInvalidatesReview() async throws {
        let (model, functions, _) = await setup()
        let reviewed = try phoneIntent(model)
        var row = recoveryRow(); row["activeSessionCount"] = 0; row["sessions"] = []
        await functions.page(recoveryData(["customers": [row], "hasMore": false]))
        await model.load()
        XCTAssertFalse(model.canConfirm(reviewed, reason: "Customer request", confirmation: replacement, acknowledged: true))
    }
    func testInvalidPhoneOrSamePhoneCannotConfirm() async throws {
        let (model, _, _) = await setup()
        let row = try XCTUnwrap(model.rows.first)
        for phone in [row.account.currentPhoneNumber, "9876543210", "+0123456789", "+919876543210\n", "+٩١٩٨٧٦٥٤٣٢١٠", "+9198765432101234"] {
            let intent = DastakAdminCustomerRecoveryIntent(row: row, action: .phone, sessionID: nil, replacementPhone: phone)
            XCTAssertFalse(model.canConfirm(intent, reason: "Customer request", confirmation: phone, acknowledged: true))
        }
    }
    func testPhoneTimeoutRelaunchRetriesOriginalNumberReasonVersionAndKey() async throws {
        let (model, functions, store) = await setup()
        await model.submit(try phoneIntent(model), reason: " Customer request ", confirmation: replacement, acknowledged: true)
        let original = try XCTUnwrap(model.pending)
        XCTAssertEqual(original.attempts, 1)
        XCTAssertEqual(original.reason, "Customer request")
        let saved = await store.load(recoveryActor); XCTAssertEqual(saved, original)
        let restored = makeModel(functions, store); await restored.restore(); await restored.load()
        let changed = try phoneIntent(restored, replacement: "+919999999998")
        await restored.submit(changed, reason: "Changed reason", confirmation: "+919999999998", acknowledged: true)
        let before = await functions.writes; XCTAssertEqual(before.count, 1)
        await functions.reply(.data(phoneAcknowledgement()))
        let retried = await restored.retry(); XCTAssertTrue(retried)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes[0].body, writes[1].body); XCTAssertEqual(writes[0].key, writes[1].key)
        let body = try object(writes[0].body)
        XCTAssertEqual(Set(body.keys), ["operation", "accountId", "reviewedCurrentPhone", "replacementPhone", "expectedPhoneClaimVersion", "reason"])
        XCTAssertNil(restored.pending)
        XCTAssertTrue(restored.notice?.contains("OAuth sign-in identity") == true)
    }
    func testSessionTimeoutKeepsSingleScopeAndCannotBecomeRevokeAll() async throws {
        let (model, functions, store) = await setup()
        let row = try XCTUnwrap(model.rows.first)
        let intent = DastakAdminCustomerRecoveryIntent(row: row, action: .sessions, sessionID: recoverySession, replacementPhone: nil)
        await model.submit(intent, reason: "Lost device", confirmation: recoveryCustomer.uuidString, acknowledged: true)
        let restored = makeModel(functions, store); await restored.restore()
        await functions.reply(.data(sessionAcknowledgement()))
        let retried = await restored.retry(); XCTAssertTrue(retried)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes[0].body, writes[1].body)
        XCTAssertEqual(try object(writes[1].body)["scope"] as? String, "SINGLE")
        XCTAssertEqual(try object(writes[1].body)["sessionId"] as? String, recoverySession.uuidString)
    }
    func testFileFailurePreventsNetworkWrite() async throws {
        let (model, functions, store) = await setup()
        await store.failSave()
        await model.submit(try phoneIntent(model), reason: "Contact correction", confirmation: replacement, acknowledged: true)
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertFalse(model.restored); XCTAssertTrue(model.blocksActions)
    }
    func testAccountSwitchPreventsWrite() async throws {
        let identity = RecoveryIdentity(); let functions = RecoveryFunctions(); let store = RecoveryStorage()
        let model = DastakAdminCustomerRecoveryModel(services: MarketplaceAuthenticatedServices(functions: functions, accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }), storage: store)
        await model.load(); let intent = try phoneIntent(model)
        await identity.change()
        await model.submit(intent, reason: "Contact correction", confirmation: replacement, acknowledged: true)
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(model.rows.isEmpty, "An account switch must not leave the prior actor's customer data visible")
    }
    func testWrongPhoneReceiptOrVerificationVersionRetainsAction() async throws {
        for field in ["accountId", "phoneClaimVersion", "phoneVerificationState", "maskedPhoneNumber", "updatedAt"] {
            let (model, functions, _) = await setup()
            var reply = try object(phoneAcknowledgement())
            switch field {
            case "accountId": reply[field] = UUID().uuidString
            case "phoneClaimVersion": reply[field] = 1
            case "phoneVerificationState": reply[field] = "verified"
            case "maskedPhoneNumber": reply[field] = "wrong"
            default: reply[field] = "invalid"
            }
            await functions.reply(.data(recoveryData(reply)))
            await model.submit(try phoneIntent(model), reason: "Contact correction", confirmation: replacement, acknowledged: true)
            XCTAssertNotNil(model.pending, field); XCTAssertFalse(model.current)
        }
    }
    func testWrongSessionReceiptScopeOrTargetRetainsAction() async throws {
        let (model, functions, _) = await setup()
        let intent = DastakAdminCustomerRecoveryIntent(row: try XCTUnwrap(model.rows.first), action: .sessions, sessionID: recoverySession, replacementPhone: nil)
        await functions.reply(.data(sessionAcknowledgement(scope: "ALL")))
        await model.submit(intent, reason: "Lost device", confirmation: recoveryCustomer.uuidString, acknowledged: true)
        XCTAssertNotNil(model.pending)
    }
    func testFirstDefinitiveRejectionReleasesButLaterRejectionRetainsUncertainAction() async throws {
        for retry in [false, true] {
            let (model, functions, _) = await setup()
            if !retry { await functions.reply(.rejected(409)) }
            await model.submit(try phoneIntent(model), reason: "Contact correction", confirmation: replacement, acknowledged: true)
            if retry { await functions.reply(.rejected(403)); await model.retry() }
            XCTAssertEqual(model.pending == nil, !retry)
            XCTAssertNotNil(model.error, "Successful directory reload must not erase the rejected-action warning")
        }
    }
    func testThrottleDoesNotDiscardOriginalAction() async throws {
        let (model, functions, _) = await setup()
        await functions.reply(.rejected(429))
        await model.submit(try phoneIntent(model), reason: "Contact correction", confirmation: replacement, acknowledged: true)
        XCTAssertNotNil(model.pending)
    }
    func testAcknowledgedCleanupFailureReopensWithoutAnotherWrite() async throws {
        let (model, functions, store) = await setup()
        await store.failRemoval(); await functions.reply(.data(phoneAcknowledgement()))
        await model.submit(try phoneIntent(model), reason: "Contact correction", confirmation: replacement, acknowledged: true)
        XCTAssertTrue(model.pending?.acknowledged == true)
        let restored = makeModel(functions, store); await restored.restore(); await restored.retry()
        let writes = await functions.writes; XCTAssertEqual(writes.count, 1)
        XCTAssertNil(restored.pending)
    }
    func testSupersededDiskCommandNeverReplays() async throws {
        let (model, functions, store) = await setup()
        await model.submit(try phoneIntent(model), reason: "Contact correction", confirmation: replacement, acknowledged: true)
        let saved = try XCTUnwrap(model.pending); var other = saved; other.revision = UUID()
        try await store.replace(other, actorID: recoveryActor, expectedRevision: saved.revision)
        await model.retry()
        let writes = await functions.writes; XCTAssertEqual(writes.count, 1)
    }
    func testFailedReadPreservesRecordsButUnauthorizedReadClearsPII() async throws {
        let (model, functions, _) = await setup()
        await functions.failRead(503); await model.load()
        XCTAssertEqual(model.rows.count, 1); XCTAssertFalse(model.current)
        await functions.failRead(403); await model.load()
        XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.current)
    }
    func testMalformedSessionCountsAndCursorDoNotClaimEmptySuccess() async throws {
        let (model, functions, _) = await setup()
        var row = recoveryRow(); row["activeSessionCount"] = 0
        await functions.page(recoveryData(["customers": [row], "hasMore": false])); await model.load()
        XCTAssertFalse(model.current)
        await functions.page(recoveryData(["customers": [], "hasMore": true])); await model.load()
        XCTAssertFalse(model.current)
    }
    func testCursorPaginationAndSearchChangeClearOldRows() async throws {
        let (model, functions, _) = await setup()
        await functions.page(recoveryPage(hasMore: true)); await model.load()
        XCTAssertNotNil(model.cursor)
        await functions.page(recoveryData(["customers": [], "hasMore": false])); await model.load(append: true)
        XCTAssertEqual(model.rows.count, 1); XCTAssertNil(model.cursor)
        await functions.failRead(503); await model.load(query: "different")
        XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.current)
    }
    func testLateSearchCannotReplaceNewQuery() async throws {
        let (model, functions, _) = await setup()
        await functions.holdNextPage()
        let older = Task { await model.load(query: "old") }; await functions.waitForHold()
        await functions.page(recoveryData(["customers": [], "hasMore": false])); await model.load(query: "new")
        await functions.release(recoveryPage()); await older.value
        XCTAssertEqual(model.query, "new"); XCTAssertTrue(model.rows.isEmpty); XCTAssertTrue(model.current)
    }
    func testLateReadCrossingRetryDoesNotReplaceFreshPostActionRead() async throws {
        let (model, functions, _) = await setup()
        await model.submit(try phoneIntent(model), reason: "Contact correction", confirmation: replacement, acknowledged: true)
        await functions.holdNextPage(); let older = Task { await model.load() }; await functions.waitForHold()
        await functions.reply(.data(phoneAcknowledgement())); await functions.page(recoveryPage(phone: replacement, claimVersion: 2))
        await model.retry(); await functions.release(recoveryPage()); await older.value
        XCTAssertEqual(model.rows.first?.account.currentPhoneNumber, replacement)
        XCTAssertEqual(model.rows.first?.phoneClaim.version, 2)
    }
    func testAllSessionsAcknowledgementUsesActualCountNotReviewedCount() throws {
        let command = sessionCommand(scope: "ALL")
        let result = try JSONDecoder().decode(DastakAdminCustomerSessionResult.self, from: sessionAcknowledgement(scope: "ALL", count: 3, remaining: 1))
        XCTAssertTrue(DastakAdminCustomerRecoveryModel.acknowledges(command, result))
    }
    func testProtectedJournalIsActorScopedAndCompareAndSwap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DastakAdminCustomerRecoveryFileStore(directory: directory); let command = sessionCommand()
        try await store.replace(command, actorID: recoveryActor, expectedRevision: nil)
        let restored = try await store.load(recoveryActor); XCTAssertEqual(restored, command)
        let other = try await store.load(UUID()); XCTAssertNil(other)
        do { try await store.replace(nil, actorID: recoveryActor, expectedRevision: nil); XCTFail("Stale delete accepted") } catch {}
        let file = directory.appendingPathComponent(recoveryActor.uuidString.lowercased() + ".json")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        try await store.replace(nil, actorID: recoveryActor, expectedRevision: command.revision)
    }
    private func setup(page: Data = recoveryPage()) async -> (DastakAdminCustomerRecoveryModel, RecoveryFunctions, RecoveryStorage) {
        let functions = RecoveryFunctions(); await functions.page(page); let store = RecoveryStorage()
        let model = makeModel(functions, store); await model.load(); return (model, functions, store)
    }
    private func makeModel(_ functions: RecoveryFunctions, _ store: RecoveryStorage) -> DastakAdminCustomerRecoveryModel {
        .init(services: MarketplaceAuthenticatedServices(functions: functions, accountIDProvider: { recoveryActor }, objectUploader: { _, _, _, _, _ in }), storage: store)
    }
    private func phoneIntent(_ model: DastakAdminCustomerRecoveryModel, replacement: String = replacement) throws -> DastakAdminCustomerRecoveryIntent {
        .init(row: try XCTUnwrap(model.rows.first), action: .phone, sessionID: nil, replacementPhone: replacement)
    }
}
private actor RecoveryIdentity { var id = recoveryActor; func change() { id = UUID() } }
private actor RecoveryStorage: DastakAdminCustomerRecoveryStorage {
    var value: DastakAdminCustomerRecoveryCommand?
    private var failsSave = false; private var failsRemove = false
    func failSave() { failsSave = true }; func failRemoval() { failsRemove = true }
    func load(_ actorID: UUID) -> DastakAdminCustomerRecoveryCommand? { value?.actorID == actorID ? value : nil }
    func replace(_ command: DastakAdminCustomerRecoveryCommand?, actorID: UUID, expectedRevision: UUID?) throws {
        guard value?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        if command == nil && failsRemove { failsRemove = false; throw URLError(.cannotWriteToFile) }
        if command != nil && failsSave { failsSave = false; throw URLError(.cannotWriteToFile) }
        value = command
    }
}
private actor RecoveryFunctions: FunctionClient {
    enum Reply: Sendable { case data(Data), rejected(Int) }
    struct Write: Sendable { let body: Data; let key: String }
    var writes: [Write] = []
    private var reads: [Data] = []; private var pageData = recoveryPage(); private var replies: [Reply] = []
    private var readError: Int?; private var holds = false
    private var held: CheckedContinuation<Data, Never>?; private var waiting: CheckedContinuation<Void, Never>?
    func page(_ value: Data) { pageData = value }
    func reply(_ reply: Reply) { replies.append(reply) }
    func failRead(_ status: Int) { readError = status }
    func lastRead() -> Data? { reads.last }
    func holdNextPage() { holds = true }
    func waitForHold() async { if held == nil { await withCheckedContinuation { waiting = $0 } } }
    func release(_ data: Data) { held?.resume(returning: data); held = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; let body = try encoder.encode(request)
        if try object(body)["operation"] as? String == "adminCustomerRecoveryPage" {
            reads.append(body)
            if let status = readError { readError = nil; throw FunctionClientError.api(statusCode: status, code: "test", message: "Fixture rejection") }
            var result = pageData
            if holds { holds = false; result = await withCheckedContinuation { held = $0; waiting?.resume(); waiting = nil } }
            return try JSONDecoder().decode(Response.self, from: result)
        }
        writes.append(.init(body: body, key: idempotencyKey.rawValue))
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        switch replies.removeFirst() { case let .data(data): return try JSONDecoder().decode(Response.self, from: data)
        case let .rejected(status): throw FunctionClientError.api(statusCode: status, code: "test", message: "Fixture rejection") }
    }
}
private let recoveryActor = UUID(uuidString: "97000000-0000-4000-8000-000000000001")!
private let recoveryCustomer = UUID(uuidString: "97000000-0000-4000-8000-000000000002")!
private let recoverySession = UUID(uuidString: "97000000-0000-4000-8000-000000000003")!
private let replacement = "+919876543219"
private let recoveryTime = "2026-10-11T00:00:00Z"
private func recoveryData(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
private func object(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
private func recoveryRow(phone: String = "+919876543210", claimVersion: Int = 1) -> [String: Any] {
    ["account": ["accountId": recoveryCustomer.uuidString, "displayName": "Test Customer", "currentPhoneNumber": phone, "maskedPhoneNumber": DastakAdminCustomerRecoveryContract.mask(phone), "email": "test@example.invalid", "accountState": "ACTIVE", "customerState": "ACTIVE", "createdAt": recoveryTime],
     "phoneClaim": ["version": claimVersion, "state": claimVersion == 0 ? "MISSING" : "ACTIVE", "verificationSource": "PROFILE_ENTRY"], "identityProviders": ["apple"], "activeSessionCount": 1,
     "sessions": [["sessionId": recoverySession.uuidString, "deviceName": "Test phone", "platform": "ios", "appName": "Dastak", "createdAt": recoveryTime, "lastSeenAt": recoveryTime]], "updatedAt": recoveryTime]
}
private func recoveryPage(phone: String = "+919876543210", claimVersion: Int = 1, hasMore: Bool = false) -> Data {
    var page: [String: Any] = ["customers": [recoveryRow(phone: phone, claimVersion: claimVersion)], "hasMore": hasMore]
    if hasMore { page["nextCursor"] = ["updatedAt": recoveryTime, "accountId": recoveryCustomer.uuidString] }
    return recoveryData(page)
}
private func phoneAcknowledgement() -> Data { recoveryData(["accountId": recoveryCustomer.uuidString, "maskedPhoneNumber": DastakAdminCustomerRecoveryContract.mask(replacement), "phoneClaimVersion": 2, "phoneVerificationState": "unverified", "updatedAt": recoveryTime]) }
private func sessionAcknowledgement(scope: String = "SINGLE", count: Int = 1, remaining: Int = 0) -> Data {
    recoveryData(["accountId": recoveryCustomer.uuidString, "scope": scope, "revokedSessionCount": count, "revokedSessionId": scope == "SINGLE" ? recoverySession.uuidString as Any : NSNull(), "activeSessionCount": remaining, "updatedAt": recoveryTime])
}
private func sessionCommand(scope: String = "SINGLE") -> DastakAdminCustomerRecoveryCommand {
    .init(actorID: recoveryActor, accountID: recoveryCustomer, action: .sessions, scope: scope, sessionID: scope == "SINGLE" ? recoverySession : nil, currentPhone: nil, replacementPhone: nil, claimVersion: nil, reason: "Lost device", key: IdempotencyKey(rawValue: UUID().uuidString)!)
}
