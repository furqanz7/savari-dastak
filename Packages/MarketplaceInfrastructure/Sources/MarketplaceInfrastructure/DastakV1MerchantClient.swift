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

    public var id: UUID { orderLineID }

    private enum CodingKeys: String, CodingKey {
        case name, quantity
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

    private enum CodingKeys: String, CodingKey {
        case id, displayOrderNumber, orderStatus, status, version, branch
        case promisedPrepMinutes, prepStartedAt, estimatedReadyAt, actualReadyAt
        case secondsRemaining, runningLate, packageCount, evidence
        case canDeclarePackages, canAddEvidence, canMarkReady, lines
        case orderID = "orderId"
    }
}

public struct DastakV1MerchantEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let objectPath: String
    public let contentType: String
    public let capturedAt: String
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
