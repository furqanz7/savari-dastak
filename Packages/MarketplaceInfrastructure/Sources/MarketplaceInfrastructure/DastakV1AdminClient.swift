import Foundation
import MarketplaceFoundation

public struct DastakV1AdminOrder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayOrderNumber: String
    public let orderType: String
    public let status: String
    public let version: Int
    public let paidAt: String?
    public let updatedAt: String
    public let deliveredAt: String?
}

public struct DastakV1AdminLaunchCommitment: Codable, Equatable, Sendable {
    public let id: UUID
    public let optionCode: String
    public let customerID: UUID
    public let amountPaise: Int
    public let currencyCode: String
    public let securedAt: String
    public let reservationExpiresAt: String
    public let committedAt: String
    public let version: Int

    private enum CodingKeys: String, CodingKey {
        case id, optionCode, amountPaise, currencyCode, securedAt
        case reservationExpiresAt, committedAt, version
        case customerID = "customerId"
    }
}

public struct DastakV1AdminCollectionAttempt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let outcome: String
    public let method: String
    public let riderID: UUID
    public let missionID: UUID
    public let reference: String?
    public let reason: String?
    public let attemptedAt: String
    public let collectedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, outcome, method, reference, reason, attemptedAt, collectedAt
        case riderID = "riderId"
        case missionID = "missionId"
    }
}

public struct DastakV1AdminPlatformFee: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let amountPaise: Int
    public let currencyCode: String
    public let postedAt: String
    public let balanced: Bool

    private enum CodingKeys: String, CodingKey {
        case amountPaise, currencyCode, postedAt, balanced
        case transactionID = "transactionId"
    }
}

public struct DastakV1AdminLaunchPayment: Codable, Equatable, Sendable {
    public let commitment: DastakV1AdminLaunchCommitment?
    public let collectionStatus: String
    public let attempts: [DastakV1AdminCollectionAttempt]
    public let platformFee: DastakV1AdminPlatformFee?
}

public struct DastakV1AdminExecutionTrace: Codable, Equatable, Sendable {
    public let order: DastakV1AdminOrder
    public let launchPayment: DastakV1AdminLaunchPayment?
}

public enum DastakAdminRole: String, Codable, Equatable, Sendable {
    case superadmin = "SUPERADMIN"
    case executiveAdmin = "EXECUTIVE_ADMIN"

    public var displayName: String {
        switch self {
        case .superadmin: "Superadmin"
        case .executiveAdmin: "Executive Admin"
        }
    }
}

public struct DastakAdminSlot: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { slot }
    public let slot: Int
    public let role: DastakAdminRole
    public let email: String?
    public let linked: Bool
    public let version: Int
}

public struct DastakAdminAccessSnapshot: Codable, Equatable, Sendable {
    public let role: DastakAdminRole
    public let canManageAdmins: Bool
    public let slots: [DastakAdminSlot]
}

public protocol DastakV1AdminClient: Sendable {
    func orders(limit: Int, idempotencyKey: IdempotencyKey) async throws -> [DastakV1AdminOrder]
    func trace(orderID: UUID, idempotencyKey: IdempotencyKey) async throws -> DastakV1AdminExecutionTrace
    func access(idempotencyKey: IdempotencyKey) async throws -> DastakAdminAccessSnapshot
    func setExecutiveAdmin(
        slot: Int,
        email: String?,
        expectedVersion: Int,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminSlot
}

public struct SupabaseDastakV1AdminClient: DastakV1AdminClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let limit: Int?
        let orderId: UUID?
        let slot: Int?
        let email: String?
        let expectedVersion: Int?
        let reason: String?
    }

    private struct OrderCollection: Decodable, Sendable {
        let orders: [DastakV1AdminOrder]
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func orders(
        limit: Int = 50,
        idempotencyKey: IdempotencyKey
    ) async throws -> [DastakV1AdminOrder] {
        precondition((1...100).contains(limit))
        let collection: OrderCollection = try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "adminExecutionOrders",
                limit: limit,
                orderId: nil,
                slot: nil,
                email: nil,
                expectedVersion: nil,
                reason: nil
            ),
            idempotencyKey: idempotencyKey
        )
        return collection.orders
    }

    public func trace(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1AdminExecutionTrace {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "adminExecutionTrace",
                limit: nil,
                orderId: orderID,
                slot: nil,
                email: nil,
                expectedVersion: nil,
                reason: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func access(
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminAccessSnapshot {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "adminAccess",
                limit: nil,
                orderId: nil,
                slot: nil,
                email: nil,
                expectedVersion: nil,
                reason: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func setExecutiveAdmin(
        slot: Int,
        email: String?,
        expectedVersion: Int,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminSlot {
        precondition((1...2).contains(slot))
        precondition(expectedVersion > 0)
        return try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "setExecutiveAdmin",
                limit: nil,
                orderId: nil,
                slot: slot,
                email: email,
                expectedVersion: expectedVersion,
                reason: reason
            ),
            idempotencyKey: idempotencyKey
        )
    }
}
