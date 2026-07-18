import Foundation
import MarketplaceFoundation

public enum CatalogueAvailability: String, Codable, Equatable, Sendable {
    case inStock = "in_stock"
    case outOfStock = "out_of_stock"
}

public enum CatalogueKind: String, Codable, Equatable, Sendable {
    case general
    case otcMedicine = "otc_medicine"
    case prescriptionMedicine = "prescription_medicine"
    case paanCorner = "paan_corner"
}

public enum RestrictedApprovalState: String, Codable, Equatable, Sendable {
    case notApplicable = "not_applicable"
    case pending
    case approved
    case rejected
    case suspended
}

public struct CatalogueStore: Codable, Equatable, Sendable {
    public let storeID: UUID
    public let name: String
    public let address: String
    public let location: GeoPoint
    public let serviceZoneID: UUID
    public let isPublished: Bool
    public let acceptingOrders: Bool

    private enum CodingKeys: String, CodingKey {
        case storeID = "storeId"
        case name
        case address
        case location
        case serviceZoneID = "serviceZoneId"
        case isPublished
        case acceptingOrders
    }
}

public struct CatalogueCategory: Codable, Equatable, Sendable {
    public let categoryID: UUID
    public let storeID: UUID
    public let name: String
    public let displayOrder: Int
    public let isActive: Bool

    private enum CodingKeys: String, CodingKey {
        case categoryID = "categoryId"
        case storeID = "storeId"
        case name
        case displayOrder
        case isActive
    }
}

public struct CatalogueProduct: Codable, Equatable, Sendable {
    public let productID: UUID
    public let storeID: UUID
    public let categoryID: UUID
    public let name: String
    public let description: String?
    public let unitLabel: String
    public let price: Money
    public let imageObjectPath: String?
    public let availability: CatalogueAvailability
    public let catalogueKind: CatalogueKind
    public let restrictedApprovalState: RestrictedApprovalState
    public let requiresPrescription: Bool?
    public let restrictedTobaccoKind: ControlledTobaccoKind?
    public let isActive: Bool

    private enum CodingKeys: String, CodingKey {
        case productID = "productId"
        case storeID = "storeId"
        case categoryID = "categoryId"
        case name
        case description
        case unitLabel
        case price
        case imageObjectPath
        case availability
        case catalogueKind
        case restrictedApprovalState
        case requiresPrescription
        case restrictedTobaccoKind
        case isActive
    }
}

public struct CatalogueSnapshot: Codable, Equatable, Sendable {
    public let serviceZoneID: UUID?
    public let stores: [CatalogueStore]
    public let categories: [CatalogueCategory]
    public let products: [CatalogueProduct]

    private enum CodingKeys: String, CodingKey {
        case serviceZoneID = "serviceZoneId"
        case stores
        case categories
        case products
    }
}

public protocol CatalogueClient: Sendable {
    func upsertStore(
        name: String,
        address: String,
        location: GeoPoint,
        isPublished: Bool,
        acceptingOrders: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueStore

    func upsertCategory(
        categoryID: UUID?,
        name: String,
        displayOrder: Int,
        isActive: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueCategory

    func upsertProduct(
        productID: UUID?,
        categoryID: UUID,
        name: String,
        description: String?,
        unitLabel: String,
        price: Money,
        imageObjectPath: String?,
        availability: CatalogueAvailability,
        catalogueKind: CatalogueKind,
        isActive: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueProduct

    func merchantSnapshot(idempotencyKey: IdempotencyKey) async throws -> CatalogueSnapshot
    func browse(
        at location: GeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueSnapshot
}

public struct SupabaseCatalogueClient: CatalogueClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let name: String?
        let address: String?
        let location: GeoPoint?
        let isPublished: Bool?
        let acceptingOrders: Bool?
        let categoryId: UUID?
        let displayOrder: Int?
        let isActive: Bool?
        let productId: UUID?
        let description: String?
        let unitLabel: String?
        let price: Money?
        let imageObjectPath: String?
        let availability: CatalogueAvailability?
        let catalogueKind: CatalogueKind?
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func upsertStore(
        name: String,
        address: String,
        location: GeoPoint,
        isPublished: Bool,
        acceptingOrders: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueStore {
        try await invoke(
            Request(
                operation: "upsertStore",
                name: name,
                address: address,
                location: location,
                isPublished: isPublished,
                acceptingOrders: acceptingOrders,
                categoryId: nil,
                displayOrder: nil,
                isActive: nil,
                productId: nil,
                description: nil,
                unitLabel: nil,
                price: nil,
                imageObjectPath: nil,
                availability: nil,
                catalogueKind: nil
            ),
            key: idempotencyKey
        )
    }

    public func upsertCategory(
        categoryID: UUID?,
        name: String,
        displayOrder: Int,
        isActive: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueCategory {
        try await invoke(
            Request(
                operation: "upsertCategory",
                name: name,
                address: nil,
                location: nil,
                isPublished: nil,
                acceptingOrders: nil,
                categoryId: categoryID,
                displayOrder: displayOrder,
                isActive: isActive,
                productId: nil,
                description: nil,
                unitLabel: nil,
                price: nil,
                imageObjectPath: nil,
                availability: nil,
                catalogueKind: nil
            ),
            key: idempotencyKey
        )
    }

    public func upsertProduct(
        productID: UUID?,
        categoryID: UUID,
        name: String,
        description: String?,
        unitLabel: String,
        price: Money,
        imageObjectPath: String?,
        availability: CatalogueAvailability,
        catalogueKind: CatalogueKind,
        isActive: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueProduct {
        try await invoke(
            Request(
                operation: "upsertProduct",
                name: name,
                address: nil,
                location: nil,
                isPublished: nil,
                acceptingOrders: nil,
                categoryId: categoryID,
                displayOrder: nil,
                isActive: isActive,
                productId: productID,
                description: description,
                unitLabel: unitLabel,
                price: price,
                imageObjectPath: imageObjectPath,
                availability: availability,
                catalogueKind: catalogueKind
            ),
            key: idempotencyKey
        )
    }

    public func merchantSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueSnapshot {
        try await invoke(emptyRequest(operation: "merchantSnapshot"), key: idempotencyKey)
    }

    public func browse(
        at location: GeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueSnapshot {
        try await invoke(
            Request(
                operation: "browse",
                name: nil,
                address: nil,
                location: location,
                isPublished: nil,
                acceptingOrders: nil,
                categoryId: nil,
                displayOrder: nil,
                isActive: nil,
                productId: nil,
                description: nil,
                unitLabel: nil,
                price: nil,
                imageObjectPath: nil,
                availability: nil,
                catalogueKind: nil
            ),
            key: idempotencyKey
        )
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke("catalogue", request: request, idempotencyKey: key)
    }

    private func emptyRequest(operation: String) -> Request {
        Request(
            operation: operation,
            name: nil,
            address: nil,
            location: nil,
            isPublished: nil,
            acceptingOrders: nil,
            categoryId: nil,
            displayOrder: nil,
            isActive: nil,
            productId: nil,
            description: nil,
            unitLabel: nil,
            price: nil,
            imageObjectPath: nil,
            availability: nil,
            catalogueKind: nil
        )
    }
}
