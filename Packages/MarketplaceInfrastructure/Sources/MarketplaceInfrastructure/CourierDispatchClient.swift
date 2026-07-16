import Foundation
import MarketplaceFoundation

public enum CourierAssignmentStatus: String, Codable, Equatable, Sendable {
    case offered
    case accepted
}

public struct CourierAssignmentItem: Codable, Equatable, Sendable {
    public let productID: UUID
    public let name: String
    public let unitLabel: String
    public let quantity: Int

    private enum CodingKeys: String, CodingKey {
        case productID = "productId"
        case name
        case unitLabel
        case quantity
    }
}

public struct CourierAssignmentStore: Codable, Equatable, Sendable {
    public let storeID: UUID
    public let name: String
    public let address: String
    public let pickup: GeoPoint

    private enum CodingKeys: String, CodingKey {
        case storeID = "storeId"
        case name
        case address
        case pickup
    }
}

public struct CourierAssignment: Codable, Equatable, Sendable {
    public let assignmentID: UUID
    public let orderID: UUID
    public let assignmentStatus: CourierAssignmentStatus
    public let orderStatus: MerchantOrderStatus
    public let offeredAt: String
    public let respondBy: String
    public let acceptedAt: String?
    public let distanceMeters: Double
    public let store: CourierAssignmentStore
    public let dropoff: GeoPoint
    public let items: [CourierAssignmentItem]

    private enum CodingKeys: String, CodingKey {
        case assignmentID = "assignmentId"
        case orderID = "orderId"
        case assignmentStatus
        case orderStatus
        case offeredAt
        case respondBy
        case acceptedAt
        case distanceMeters
        case store
        case dropoff
        case items
    }
}

public struct CourierDispatchSnapshot: Codable, Equatable, Sendable {
    public let offer: CourierAssignment?
    public let currentJob: CourierAssignment?
}

public protocol CourierDispatchClient: Sendable {
    func partnerSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot

    func acceptOffer(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot

    func declineOffer(
        assignmentID: UUID,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot

    func startToStore(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot

    func arriveAtStore(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot

    func confirmPickup(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot

    func startDelivery(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot

    func completeDelivery(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot
}

public struct SupabaseCourierDispatchClient: CourierDispatchClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let assignmentId: UUID?
        let reason: String?

        init(
            operation: String,
            assignmentId: UUID? = nil,
            reason: String? = nil
        ) {
            self.operation = operation
            self.assignmentId = assignmentId
            self.reason = reason
        }
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func partnerSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await invoke(Request(operation: "partnerSnapshot"), key: idempotencyKey)
    }

    public func acceptOffer(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await invoke(
            Request(operation: "acceptOffer", assignmentId: assignmentID),
            key: idempotencyKey
        )
    }

    public func declineOffer(
        assignmentID: UUID,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await invoke(
            Request(
                operation: "declineOffer",
                assignmentId: assignmentID,
                reason: reason
            ),
            key: idempotencyKey
        )
    }

    public func startToStore(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await lifecycle(
            operation: "startToStore",
            assignmentID: assignmentID,
            idempotencyKey: idempotencyKey
        )
    }

    public func arriveAtStore(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await lifecycle(
            operation: "arriveAtStore",
            assignmentID: assignmentID,
            idempotencyKey: idempotencyKey
        )
    }

    public func confirmPickup(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await lifecycle(
            operation: "confirmPickup",
            assignmentID: assignmentID,
            idempotencyKey: idempotencyKey
        )
    }

    public func startDelivery(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await lifecycle(
            operation: "startDelivery",
            assignmentID: assignmentID,
            idempotencyKey: idempotencyKey
        )
    }

    public func completeDelivery(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await lifecycle(
            operation: "completeDelivery",
            assignmentID: assignmentID,
            idempotencyKey: idempotencyKey
        )
    }

    private func lifecycle(
        operation: String,
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await invoke(
            Request(operation: operation, assignmentId: assignmentID),
            key: idempotencyKey
        )
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke(
            "courier-dispatch",
            request: request,
            idempotencyKey: key
        )
    }
}
