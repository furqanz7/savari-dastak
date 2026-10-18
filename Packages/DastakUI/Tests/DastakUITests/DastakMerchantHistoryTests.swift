import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantHistoryTests: XCTestCase {
    func testCompletedFulfilmentIsHistoricalWithoutTerminalOrder() throws {
        let page = try JSONDecoder().decode(DastakMerchantHistoryPage.self, from: historyPage())
        let row = try XCTUnwrap(page.fulfilments.first)
        XCTAssertEqual(row.orderStatus, "PREPARING")
        XCTAssertTrue(DastakMerchantQueue.isHistory(row)); XCTAssertFalse(DastakMerchantQueue.all.includes(row))
    }
    func testClientSendsExactBranchAndLosslessCursorWithoutActorOverride() async throws {
        let functions = HistoryFunctions([historyPage(count: 1, more: true)])
        let client = SupabaseDastakMerchantHistoryClient(functions: functions)
        let first = try await client.page(branch: historyBranch, before: nil, limit: 1, key: historyKey())
        await functions.enqueue(historyPage(start: 2))
        _ = try await client.page(branch: historyBranch, before: first.nextCursor, key: historyKey())
        let calls = await functions.calls
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[1]) as? [String: Any])
        XCTAssertEqual(body["operation"] as? String, "merchantFulfilmentHistory")
        XCTAssertEqual(body["branchId"] as? String, historyBranch.uuidString)
        XCTAssertEqual(body["beforeAt"] as? String, "2026-10-01T00:00:00.123456+00:00")
        XCTAssertEqual(body["beforeId"] as? String, historyID(1).uuidString)
        XCTAssertNil(body["actorId"]); XCTAssertNil(body["customerId"])
    }
    func testMalformedBranchActiveRowsDuplicateAndMissingContinuationFailClosed() async throws {
        for patch in ["branch", "active", "duplicate", "missing", "cursor"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: historyPage()) as? [String: Any])
            var rows = object["fulfilments"] as! [[String: Any]]
            switch patch {
            case "branch": object["branchId"] = UUID().uuidString
            case "active": rows[0]["status"] = "PREPARING"; object["fulfilments"] = rows
            case "duplicate": object["fulfilments"] = rows + rows
            case "missing": object.removeValue(forKey: "nextCursor")
            default: object["nextCursor"] = ["id": UUID().uuidString, "committedAt": "2026-10-01T00:00:00Z"]
            }
            let functions = HistoryFunctions([try JSONSerialization.data(withJSONObject: object)])
            do { _ = try await SupabaseDastakMerchantHistoryClient(functions: functions).page(branch: historyBranch, before: nil, key: historyKey()); XCTFail("Accepted \(patch)") } catch {}
        }
    }
    func testPagesAppendDeduplicateAndRefreshResetsContinuation() async {
        let functions = HistoryFunctions([historyPage(count: 50, more: true), historyPage(start: 50, count: 2), historyPage(start: 70)])
        let model = makeModel(functions)
        await model.load(); XCTAssertEqual(model.rows.count, 50); XCTAssertNotNil(model.cursor)
        await model.load(older: true); XCTAssertEqual(model.rows.count, 51); XCTAssertNil(model.cursor)
        await model.load(); XCTAssertEqual(model.rows.map(\.id), [historyID(70)])
    }
    func testTransientFailureRetainsReadOnlyRecordsAndDenialClearsThem() async {
        let functions = HistoryFunctions([historyPage()])
        let model = makeModel(functions)
        await model.load(); await functions.fail(denied: false); await model.load()
        XCTAssertEqual(model.rows.count, 1); XCTAssertNotNil(model.failure); XCTAssertFalse(model.loading)
        await functions.fail(denied: true); await model.load()
        XCTAssertTrue(model.rows.isEmpty); XCTAssertNil(model.cursor); XCTAssertNil(model.checkedAt)
    }
    func testIdentityChangeCannotPublishPreviousAccountHistory() async {
        let functions = HistoryFunctions([historyPage()]), identity = MerchantJournalTestIdentity()
        let model = DastakMerchantHistoryModel(branch: historyBranch, services: .init(functions: functions,
            accountIDProvider: { await identity.id }, objectUploader: { _, _, _, _, _ in }))
        await functions.hold()
        let read = Task { await model.load() }
        await functions.wait(); await identity.change(); await functions.release(); await read.value
        XCTAssertTrue(model.rows.isEmpty); XCTAssertNotNil(model.failure)
    }
    func testCoalescesReadsAndDeadlineReleasesLoading() async {
        let functions = HistoryFunctions([historyPage()])
        let model = makeModel(functions, timeout: .milliseconds(60))
        await functions.hold()
        let read = Task { await model.load() }
        await functions.wait(); await model.load(); await read.value
        XCTAssertFalse(model.loading); XCTAssertNotNil(model.failure)
        let calls = await functions.calls; XCTAssertEqual(calls.count, 1)
        await functions.release()
        await model.load(); XCTAssertEqual(model.rows.count, 1)
    }
    private func makeModel(_ functions: HistoryFunctions, timeout: Duration = .seconds(1)) -> DastakMerchantHistoryModel {
        let account = UUID()
        return .init(branch: historyBranch, services: .init(functions: functions,
            accountIDProvider: { account }, objectUploader: { _, _, _, _, _ in }), timeout: timeout)
    }
}
private let historyBranch = UUID(uuidString: "96000000-0000-4000-8000-000000000001")!
private func historyID(_ value: Int) -> UUID { UUID(uuidString: String(format: "96000000-0000-4000-8000-%012d", value + 100))! }
private func historyKey() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
private func historyPage(start: Int = 1, count: Int = 1, more: Bool = false) -> Data {
    let rows = (start..<(start + count)).map { index -> [String: Any] in
        ["id": historyID(index).uuidString, "orderId": historyID(900).uuidString, "displayOrderNumber": "DSK-\(index)",
         "orderStatus": "PREPARING", "status": "COMPLETED", "version": 3,
         "branch": ["id": historyBranch.uuidString, "displayName": "Store A"],
         "promisedPrepMinutes": 15, "secondsRemaining": 0, "runningLate": false,
         "evidence": [], "lines": [], "canDeclarePackages": false, "canAddEvidence": false, "canMarkReady": false]
    }
    return try! JSONSerialization.data(withJSONObject: ["branchId": historyBranch.uuidString, "fulfilments": rows,
        "nextCursor": more ? ["id": historyID(start + count - 1).uuidString, "committedAt": "2026-10-01T00:00:00.123456+00:00"] : NSNull()])
}
private actor HistoryFunctions: FunctionClient {
    var calls: [Data] = []
    private var data: [Data], denied: Bool?, holding = false
    private var continuation: CheckedContinuation<Void, Never>?, started: CheckedContinuation<Void, Never>?
    init(_ data: [Data]) { self.data = data }
    func enqueue(_ value: Data) { data.append(value) }
    func fail(denied: Bool) { self.denied = denied }
    func hold() { holding = true }
    func wait() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func release() { continuation?.resume(); continuation = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        calls.append(try JSONEncoder().encode(request))
        if holding { holding = false; await withCheckedContinuation { continuation = $0; started?.resume(); started = nil } }
        if let denied { self.denied = nil
            if denied { throw FunctionClientError.api(statusCode: 403, code: "access_denied", message: "Denied") }
            throw URLError(.notConnectedToInternet)
        }
        return try JSONDecoder().decode(Response.self, from: data.isEmpty ? historyPage() : data.removeFirst())
    }
}
