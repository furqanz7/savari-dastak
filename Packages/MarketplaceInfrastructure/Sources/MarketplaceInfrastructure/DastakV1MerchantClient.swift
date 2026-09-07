import Foundation
import MarketplaceFoundation

public struct DastakV1MerchantBranch: Codable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
}

public struct DastakV1MerchantLine: Codable, Equatable, Identifiable, Sendable {
    public let orderLineID: UUID
    public let name: String
    public let quantity: Int
    public let variant: String?
    public let packSize: String?
    public let selection: DastakV1FoodSelection?

    public var id: UUID { orderLineID }

    private enum CodingKeys: String, CodingKey {
        case name, quantity, variant, packSize, selection
        case orderLineID = "orderLineId"
    }
}

public struct DastakV1MerchantFulfilment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let orderID: UUID
    public let displayOrderNumber: String
    public let orderStatus: String
    public let status: String
    public let version: Int
    public let branch: DastakV1MerchantBranch
    public let promisedPrepMinutes: Int
    public let prepStartedAt: String?
    public let estimatedReadyAt: String?
    public let actualReadyAt: String?
    public let secondsRemaining: Int
    public let runningLate: Bool
    public let packageCount: Int?
    public let evidence: [DastakV1MerchantEvidence]
    public let canDeclarePackages: Bool
    public let canAddEvidence: Bool
    public let canMarkReady: Bool
    public let lines: [DastakV1MerchantLine]
    public let delivery: DastakV1MerchantDelivery?

    private enum CodingKeys: String, CodingKey {
        case id, displayOrderNumber, orderStatus, status, version, branch
        case promisedPrepMinutes, prepStartedAt, estimatedReadyAt, actualReadyAt
        case secondsRemaining, runningLate, packageCount, evidence
        case canDeclarePackages, canAddEvidence, canMarkReady, lines, delivery
        case orderID = "orderId"
    }
}

public struct DastakV1MerchantDelivery: Codable, Equatable, Sendable {
    public struct Rider: Codable, Equatable, Sendable {
        public let id: UUID
        public let displayName: String
    }
    public let rider: Rider?
    public let riderAssigned: Bool
    public let transportType: String?
    public let stopStatus: String?
    public let pickupCode: String?
    public let pickedUpAt: String?
}

public struct DastakV1MerchantEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let objectPath: String
    public let contentType: String
    public let capturedAt: String
}

public struct DastakV1MerchantCatalogueSnapshot: Codable, Equatable, Sendable {
    public struct OperationalState: Codable, Equatable, Sendable {
        public let isOpen: Bool
        public let acceptingOrders: Bool
        public let version: Int
        public let updatedAt: String?
    }

    public struct Capacity: Codable, Equatable, Sendable {
        public let limit: Int
        public let held: Int
        public let available: Int
    }

    public struct Branch: Codable, Equatable, Sendable {
        public let branchID: UUID
        public let branchName: String
        public let branchStatus: String
        public let branchVersion: Int
        public let organizationID: UUID
        public let organizationName: String
        public let merchantType: String
        public let operationalState: OperationalState
        public let capacity: Capacity

        private enum CodingKeys: String, CodingKey {
            case branchName, branchStatus, branchVersion, organizationName
            case merchantType, operationalState, capacity
            case branchID = "branchId"
            case organizationID = "organizationId"
        }
    }

    public struct CategoryType: Codable, Equatable, Identifiable, Sendable {
        public let categoryTypeID: UUID
        public let name: String
        public let slug: String
        public let imageKey: String?
        public let previewImageKeys: [String]?
        public let navigationSection: DastakV1CatalogueNavigationSection?
        public let status: String?
        public let requiresControlledFlow: Bool?
        public let sortOrder: Int
        public var id: UUID { categoryTypeID }

        private enum CodingKeys: String, CodingKey {
            case name, slug, imageKey, previewImageKeys, navigationSection
            case status, requiresControlledFlow, sortOrder
            case categoryTypeID = "categoryTypeId"
        }
    }

    public struct Category: Codable, Equatable, Identifiable, Sendable {
        public let categoryID: UUID
        public let categoryTypeID: UUID?
        public let name: String
        public let slug: String
        public let imageKey: String?
        public let previewImageKeys: [String]?
        public let status: String?
        public let requiresControlledFlow: Bool?
        public let sortOrder: Int
        public var id: UUID { categoryID }

        private enum CodingKeys: String, CodingKey {
            case name, slug, imageKey, previewImageKeys, status, requiresControlledFlow, sortOrder
            case categoryID = "categoryId"
            case categoryTypeID = "categoryTypeId"
        }
    }

    public struct Subcategory: Codable, Equatable, Identifiable, Sendable {
        public let subcategoryID: UUID
        public let categoryID: UUID
        public let name: String
        public let slug: String
        public let imageKey: String?
        public let previewImageKeys: [String]?
        public let status: String?
        public let requiresControlledFlow: Bool?
        public let sortOrder: Int
        public var id: UUID { subcategoryID }

        private enum CodingKeys: String, CodingKey {
            case name, slug, imageKey, previewImageKeys, status, requiresControlledFlow, sortOrder
            case subcategoryID = "subcategoryId"
            case categoryID = "categoryId"
        }
    }

    public struct SKU: Codable, Equatable, Identifiable, Sendable {
        public let skuID: UUID
        public let categoryTypeID: UUID?
        public let categoryID: UUID
        public let subcategoryID: UUID
        public let brandName: String?
        public let name: String
        public let variant: String?
        public let packSize: String
        public let description: String?
        public let imageKey: String?
        public let galleryImageKeys: [String]
        public let quantityValue: Double?
        public let quantityUnit: String?
        public let packCount: Int?
        public let dietType: String?
        public let searchTerms: [String]
        public let listPricePaise: Int
        public let sellingPricePaise: Int
        public let currencyCode: String
        public let catalogueStatus: String
        public let selected: Bool
        public let selectionState: String?
        public let selectionVersion: Int
        public let stockQuantity: Int?
        public let stockReservedQuantity: Int?
        public let selectionUpdatedAt: String?
        public var id: UUID { skuID }

        private enum CodingKeys: String, CodingKey {
            case brandName, name, variant, packSize, description, imageKey
            case galleryImageKeys, quantityValue, quantityUnit, packCount
            case dietType, searchTerms, listPricePaise, sellingPricePaise
            case currencyCode, catalogueStatus, selected, selectionState
            case selectionVersion, selectionUpdatedAt, stockQuantity, stockReservedQuantity
            case skuID = "skuId"
            case categoryTypeID = "categoryTypeId"
            case categoryID = "categoryId"
            case subcategoryID = "subcategoryId"
        }
    }

    public let branch: Branch
    public let categoryTypes: [CategoryType]
    public let categories: [Category]
    public let subcategories: [Subcategory]
    public let skus: [SKU]
    public let truncated: Bool
}

public struct DastakV1MerchantSelectionMutation: Codable, Equatable, Sendable {
    public let branchID: UUID
    public let skuID: UUID
    public let selected: Bool
    public let state: String
    public let version: Int
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case selected, state, version, updatedAt
        case branchID = "branchId"
        case skuID = "skuId"
    }
}

public struct DastakV1MerchantSelectionCommand: Codable, Equatable, Sendable {
    public let skuID: UUID
    public let selected: Bool
    public let expectedVersion: Int
    public let stockQuantity: Int?

    public init(skuID: UUID, selected: Bool, expectedVersion: Int, stockQuantity: Int? = nil) {
        self.skuID = skuID
        self.selected = selected
        self.expectedVersion = expectedVersion
        self.stockQuantity = stockQuantity
    }

    private enum CodingKeys: String, CodingKey {
        case selected, expectedVersion, stockQuantity
        case skuID = "skuId"
    }
}

public struct DastakV1MerchantSelectionBatchMutation: Codable, Equatable, Sendable {
    public let branchID: UUID
    public let updatedCount: Int
    public let selections: [DastakV1MerchantSelectionMutation]

    private enum CodingKeys: String, CodingKey {
        case updatedCount, selections
        case branchID = "branchId"
    }
}

public struct DastakV1MerchantBranchStateMutation: Codable, Equatable, Sendable {
    public let branchID: UUID
    public let isOpen: Bool
    public let acceptingOrders: Bool
    public let version: Int
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case isOpen, acceptingOrders, version, updatedAt
        case branchID = "branchId"
    }
}

public protocol DastakV1MerchantClient: Sendable {
    func fulfilments(limit: Int, idempotencyKey: IdempotencyKey) async throws -> [DastakV1MerchantFulfilment]
    func declarePackages(
        fulfilmentID: UUID,
        packageCount: Int,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantFulfilment
    func addEvidence(
        fulfilmentID: UUID,
        objectPath: String,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantFulfilment
    func markReady(
        fulfilmentID: UUID,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantFulfilment
    func canonicalCatalogue(
        branchID: UUID?,
        limit: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantCatalogueSnapshot
    func updateCatalogueSelection(
        branchID: UUID,
        skuID: UUID,
        selected: Bool,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantSelectionMutation
    func updateCatalogueSelections(
        branchID: UUID,
        selections: [DastakV1MerchantSelectionCommand],
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantSelectionBatchMutation
    func updateBranchState(
        branchID: UUID,
        isOpen: Bool,
        acceptingOrders: Bool,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantBranchStateMutation
}

public struct SupabaseDastakV1MerchantClient: DastakV1MerchantClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let limit: Int?
        let fulfilmentId: UUID?
        let packageCount: Int?
        let objectPath: String?
        let expectedVersion: Int?
    }

    private struct Collection: Decodable, Sendable {
        let fulfilments: [DastakV1MerchantFulfilment]
    }

    private struct CatalogueRequest: Encodable, Sendable {
        let operation: String
        let branchId: UUID?
        let limit: Int?
        let skuId: UUID?
        let selected: Bool?
        let expectedVersion: Int?
        let selections: [DastakV1MerchantSelectionCommand]?
        let isOpen: Bool?
        let acceptingOrders: Bool?
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func fulfilments(
        limit: Int = 50,
        idempotencyKey: IdempotencyKey
    ) async throws -> [DastakV1MerchantFulfilment] {
        let result: Collection = try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "merchantFulfilments",
                limit: limit,
                fulfilmentId: nil,
                packageCount: nil,
                objectPath: nil,
                expectedVersion: nil
            ),
            idempotencyKey: idempotencyKey
        )
        return result.fulfilments
    }

    public func declarePackages(
        fulfilmentID: UUID,
        packageCount: Int,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantFulfilment {
        try await invoke(
            operation: "declareFulfilmentPackages",
            fulfilmentID: fulfilmentID,
            packageCount: packageCount,
            objectPath: nil,
            expectedVersion: expectedVersion,
            key: idempotencyKey
        )
    }

    public func addEvidence(
        fulfilmentID: UUID,
        objectPath: String,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantFulfilment {
        try await invoke(
            operation: "addFulfilmentReadyEvidence",
            fulfilmentID: fulfilmentID,
            packageCount: nil,
            objectPath: objectPath,
            expectedVersion: expectedVersion,
            key: idempotencyKey
        )
    }

    public func markReady(
        fulfilmentID: UUID,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantFulfilment {
        try await invoke(
            operation: "markFulfilmentReady",
            fulfilmentID: fulfilmentID,
            packageCount: nil,
            objectPath: nil,
            expectedVersion: expectedVersion,
            key: idempotencyKey
        )
    }

    public func canonicalCatalogue(
        branchID: UUID? = nil,
        limit: Int = 5_000,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantCatalogueSnapshot {
        precondition((1...5_000).contains(limit))
        return try await functions.invoke(
            "dastak-v1-catalogue",
            request: CatalogueRequest(
                operation: "merchantSnapshot",
                branchId: branchID,
                limit: limit,
                skuId: nil,
                selected: nil,
                expectedVersion: nil,
                selections: nil,
                isOpen: nil,
                acceptingOrders: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func updateCatalogueSelection(
        branchID: UUID,
        skuID: UUID,
        selected: Bool,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantSelectionMutation {
        precondition(expectedVersion >= 0)
        return try await functions.invoke(
            "dastak-v1-catalogue",
            request: CatalogueRequest(
                operation: "updateMerchantSelection",
                branchId: branchID,
                limit: nil,
                skuId: skuID,
                selected: selected,
                expectedVersion: expectedVersion,
                selections: nil,
                isOpen: nil,
                acceptingOrders: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func updateCatalogueSelections(
        branchID: UUID,
        selections: [DastakV1MerchantSelectionCommand],
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantSelectionBatchMutation {
        precondition((1...1_000).contains(selections.count))
        precondition(selections.allSatisfy { $0.expectedVersion >= 0 })
        return try await functions.invoke(
            "dastak-v1-catalogue",
            request: CatalogueRequest(
                operation: "updateMerchantSelections",
                branchId: branchID,
                limit: nil,
                skuId: nil,
                selected: nil,
                expectedVersion: nil,
                selections: selections,
                isOpen: nil,
                acceptingOrders: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func updateBranchState(
        branchID: UUID,
        isOpen: Bool,
        acceptingOrders: Bool,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1MerchantBranchStateMutation {
        precondition(expectedVersion >= 0)
        return try await functions.invoke(
            "dastak-v1-catalogue",
            request: CatalogueRequest(
                operation: "updateBranchOperationalState",
                branchId: branchID,
                limit: nil,
                skuId: nil,
                selected: nil,
                expectedVersion: expectedVersion,
                selections: nil,
                isOpen: isOpen,
                acceptingOrders: acceptingOrders
            ),
            idempotencyKey: idempotencyKey
        )
    }

    private func invoke(
        operation: String,
        fulfilmentID: UUID,
        packageCount: Int?,
        objectPath: String?,
        expectedVersion: Int,
        key: IdempotencyKey
    ) async throws -> DastakV1MerchantFulfilment {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: operation,
                limit: nil,
                fulfilmentId: fulfilmentID,
                packageCount: packageCount,
                objectPath: objectPath,
                expectedVersion: expectedVersion
            ),
            idempotencyKey: key
        )
    }
}
