import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure

final class DastakMerchantJournalTransportTests: XCTestCase {
    func testRecoveryReportHasOneExplicitTransportAttempt() async throws {
        let transport = MerchantJournalTransport(mode: .failure)
        let client = SupabaseDastakV1MerchantRecoveryClient(functions: functions(transport))
        do { _ = try await client.reportProblem(fulfilmentID: UUID(), reason: "Package damaged", version: 1, key: key()); XCTFail("Expected transport failure") } catch {}
        let count = await transport.count; XCTAssertEqual(count, 1)
        let body = await transport.lastBody
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
        XCTAssertNil(object["allowsAutomaticRetries"], "Transport policy must not alter the wire contract")
    }
    func testGovernedRestaurantMediaHasOneExplicitMultipartAttempt() async throws {
        let transport = MerchantJournalTransport(mode: .failure)
        let client = SupabaseDastakV1MerchantClient(functions: functions(transport))
        do { _ = try await client.uploadGovernedRestaurantMedia(entityType: "RESTAURANT_BRANCH_BANNER", entityID: UUID(), expectedMediaVersion: 1, data: Data([1]), contentType: "image/jpeg", fileName: "photo.jpg", sourceReference: "Merchant-owned image", reason: "Update banner", idempotencyKey: key()); XCTFail("Expected transport failure") } catch {}
        let count = await transport.count; XCTAssertEqual(count, 1)
    }
    func testRecoveryReadStillUsesExistingTransientRetryPolicy() async throws {
        let transport = MerchantJournalTransport(mode: .read)
        let feeds = try await SupabaseDastakV1MerchantRecoveryClient(functions: functions(transport)).feeds(idempotencyKey: key())
        XCTAssertEqual(feeds.fulfilments?.count, 0)
        let count = await transport.count; XCTAssertEqual(count, 2)
    }
    private func functions(_ transport: MerchantJournalTransport) -> SupabaseFunctionClient {
        .init(configuration: .init(product: "Dastak", supabaseURL: URL(string: "https://example.invalid")!, publishableKey: "fixture"), accessTokenProvider: { "fixture-token" }, transport: { try await transport.send($0) })
    }
    private func key() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
}
private actor MerchantJournalTransport {
    enum Mode { case failure, read }
    let mode: Mode
    var count = 0
    var lastBody: Data?
    init(mode: Mode) { self.mode = mode }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        count += 1; lastBody = request.httpBody
        if mode == .failure { throw URLError(.networkConnectionLost) }
        let status = count == 1 ? 503 : 200
        let body = status == 503 ? #"{"error":{"code":"fixture","message":"Unavailable"}}"# : #"{"fulfilments":[],"recoveryOpportunities":[],"returnReceipts":[],"settlements":[]}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
