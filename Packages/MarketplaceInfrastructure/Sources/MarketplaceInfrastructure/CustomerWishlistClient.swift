import Foundation
import MarketplaceFoundation

public enum CustomerWishlistItemKind: String, Codable, Equatable, Sendable {
    case retailSKU = "RETAIL_SKU"
    case menuItem = "MENU_ITEM"
}

public struct CustomerWishlistItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let kind: CustomerWishlistItemKind
    public let itemID: UUID
    public let createdAt: String

    public var id: String { "\(kind.rawValue):\(itemID.uuidString.lowercased())" }

    private enum CodingKeys: String, CodingKey {
        case kind
        case itemID = "itemId"
        case createdAt
    }
}

public struct CustomerWishlistSnapshot: Codable, Equatable, Sendable {
    public let items: [CustomerWishlistItem]
}

public protocol CustomerWishlistClient: Sendable {
    func snapshot(idempotencyKey: IdempotencyKey) async throws -> CustomerWishlistSnapshot

    func setItem(
        kind: CustomerWishlistItemKind,
        itemID: UUID,
        wished: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerWishlistSnapshot
}

public struct SupabaseCustomerWishlistClient: CustomerWishlistClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let itemKind: CustomerWishlistItemKind?
        let itemId: UUID?
        let wished: Bool?
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func snapshot(idempotencyKey: IdempotencyKey) async throws -> CustomerWishlistSnapshot {
        try await functions.invoke(
            "customer-wishlist",
            request: Request(operation: "snapshot", itemKind: nil, itemId: nil, wished: nil),
            idempotencyKey: idempotencyKey
        )
    }

    public func setItem(
        kind: CustomerWishlistItemKind,
        itemID: UUID,
        wished: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerWishlistSnapshot {
        try await functions.invoke(
            "customer-wishlist",
            request: Request(operation: "set", itemKind: kind, itemId: itemID, wished: wished),
            idempotencyKey: idempotencyKey
        )
    }
}
