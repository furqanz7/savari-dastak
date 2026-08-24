import MarketplaceFoundation
@testable import MarketplaceInfrastructure
import XCTest

final class CustomerWishlistClientTests: XCTestCase {
    func testSnapshotUsesAuthenticatedWishlistFunction() async throws {
        let functions = RecordingFunctionClient(response: #"{"items":[]}"#)
        let client = SupabaseCustomerWishlistClient(functions: functions)

        let snapshot = try await client.snapshot(idempotencyKey: key("snapshot"))

        XCTAssertEqual(snapshot.items, [])
        let invocation = await functions.invocations.first
        XCTAssertEqual(invocation?.name, "customer-wishlist")
        XCTAssertTrue(invocation?.body.contains(#""operation":"snapshot""#) == true)
    }

    func testSetItemPreservesKindIdentityAndDesiredState() async throws {
        let itemID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let functions = RecordingFunctionClient(response: #"{"items":[]}"#)
        let client = SupabaseCustomerWishlistClient(functions: functions)

        _ = try await client.setItem(
            kind: .retailSKU,
            itemID: itemID,
            wished: true,
            idempotencyKey: key("set")
        )

        let body = await functions.invocations.first?.body ?? ""
        XCTAssertTrue(body.contains(#""itemKind":"RETAIL_SKU""#))
        XCTAssertTrue(body.contains(#""itemId":"22222222-2222-4222-8222-222222222222""#))
        XCTAssertTrue(body.contains(#""wished":true"#))
    }

    private func key(_ value: String) -> IdempotencyKey {
        IdempotencyKey(rawValue: "wishlist-\(value)")!
    }
}

private actor RecordingFunctionClient: FunctionClient {
    struct Invocation: Sendable {
        let name: String
        let body: String
    }

    private(set) var invocations: [Invocation] = []
    private let response: String

    init(response: String) {
        self.response = response
    }

    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        let data = try JSONEncoder().encode(request)
        invocations.append(Invocation(name: name, body: String(decoding: data, as: UTF8.self)))
        return try JSONDecoder().decode(Response.self, from: Data(response.utf8))
    }
}
