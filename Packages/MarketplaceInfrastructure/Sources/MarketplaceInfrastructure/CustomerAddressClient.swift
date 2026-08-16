import Foundation
import MarketplaceFoundation

public struct CustomerDeliveryAddress: Codable, Equatable, Sendable, Identifiable {
    public let addressID: UUID
    public let label: String
    public let address: String
    public let building: String?
    public let floor: String?
    public let landmark: String?
    public let deliveryNotes: String?
    public let details: String
    public let displayAddress: String
    public let location: GeoPoint
    public let isDefault: Bool
    public let updatedAt: String

    public var id: UUID { addressID }

    public var doorstepBuilding: String {
        building ?? details.components(separatedBy: " • ").first ?? details
    }

    private enum CodingKeys: String, CodingKey {
        case addressID = "addressId"
        case label
        case address
        case building
        case floor
        case landmark
        case deliveryNotes
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

    func save(
        addressID: UUID?,
        label: String,
        address: String,
        building: String,
        floor: String?,
        landmark: String?,
        deliveryNotes: String?,
        location: GeoPoint,
        makeDefault: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection

    func setDefault(
        addressID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection

    func delete(
        addressID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection

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
        let addressID: UUID?
        let label: String?
        let address: String?
        let building: String?
        let floor: String?
        let landmark: String?
        let deliveryNotes: String?
        let details: String?
        let location: GeoPoint?
        let makeDefault: Bool?

        init(
            operation: String,
            addressID: UUID? = nil,
            label: String? = nil,
            address: String? = nil,
            building: String? = nil,
            floor: String? = nil,
            landmark: String? = nil,
            deliveryNotes: String? = nil,
            details: String? = nil,
            location: GeoPoint? = nil,
            makeDefault: Bool? = nil
        ) {
            self.operation = operation
            self.addressID = addressID
            self.label = label
            self.address = address
            self.building = building
            self.floor = floor
            self.landmark = landmark
            self.deliveryNotes = deliveryNotes
            self.details = details
            self.location = location
            self.makeDefault = makeDefault
        }

        private enum CodingKeys: String, CodingKey {
            case operation
            case addressID = "addressId"
            case label
            case address
            case building
            case floor
            case landmark
            case deliveryNotes
            case details
            case location
            case makeDefault
        }
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func snapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection {
        try await invoke(Request(operation: "snapshot"), idempotencyKey: idempotencyKey)
    }

    public func save(
        addressID: UUID?,
        label: String,
        address: String,
        building: String,
        floor: String?,
        landmark: String?,
        deliveryNotes: String?,
        location: GeoPoint,
        makeDefault: Bool = true,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection {
        try await invoke(
            Request(
                operation: "save",
                addressID: addressID,
                label: label,
                address: address,
                building: building,
                floor: floor,
                landmark: landmark,
                deliveryNotes: deliveryNotes,
                location: location,
                makeDefault: makeDefault
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func setDefault(
        addressID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection {
        try await invoke(
            Request(operation: "setDefault", addressID: addressID),
            idempotencyKey: idempotencyKey
        )
    }

    public func delete(
        addressID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection {
        try await invoke(
            Request(operation: "delete", addressID: addressID),
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
        try await invoke(
            Request(
                operation: "saveDefault",
                label: label,
                address: address,
                details: details,
                location: location
            ),
            idempotencyKey: idempotencyKey
        )
    }

    private func invoke(
        _ request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> CustomerDeliveryAddressCollection {
        try await functions.invoke(
            "customer-addresses",
            request: request,
            idempotencyKey: idempotencyKey
        )
    }
}
