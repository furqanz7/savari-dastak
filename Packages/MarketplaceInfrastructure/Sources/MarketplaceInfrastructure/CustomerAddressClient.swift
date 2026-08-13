import Foundation
import MarketplaceFoundation

public struct CustomerDeliveryAddress: Codable, Equatable, Sendable {
    public let addressID: UUID
    public let label: String
    public let address: String
    public let details: String
    public let displayAddress: String
    public let location: GeoPoint
    public let isDefault: Bool
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case addressID = "addressId"
        case label
        case address
        case details
        case displayAddress
        case location
        case isDefault
        case updatedAt
    }
}

public struct CustomerDeliveryAddressCollection: Codable, Equatable, Sendable {
    public let addresses: [CustomerDeliveryAddress]
}

public protocol CustomerAddressClient: Sendable {
    func snapshot(idempotencyKey: IdempotencyKey) async throws -> CustomerDeliveryAddressCollection

    func saveDefault(
        label: String,
        address: String,
        details: String,
        location: GeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection
}

public struct SupabaseCustomerAddressClient: CustomerAddressClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let label: String?
        let address: String?
        let details: String?
        let location: GeoPoint?
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func snapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection {
        try await functions.invoke(
            "customer-addresses",
            request: Request(
                operation: "snapshot",
                label: nil,
                address: nil,
                details: nil,
                location: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func saveDefault(
        label: String,
        address: String,
        details: String,
        location: GeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection {
        try await functions.invoke(
            "customer-addresses",
            request: Request(
                operation: "saveDefault",
                label: label,
                address: address,
                details: details,
                location: location
            ),
            idempotencyKey: idempotencyKey
        )
    }
}
