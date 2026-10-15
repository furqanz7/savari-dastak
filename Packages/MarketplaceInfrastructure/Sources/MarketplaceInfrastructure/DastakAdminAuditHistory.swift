import Foundation
import MarketplaceFoundation

public enum DastakAdminAuditValue: Decodable, Equatable, Sendable {
    case text(String), number(Double), boolean(Bool)
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { self = .text(String(text.prefix(160))) }
        else if let boolean = try? value.decode(Bool.self) { self = .boolean(boolean) }
        else { self = .number(try value.decode(Double.self)) }
    }
    public var display: String {
        switch self {
        case let .text(value): return value
        case let .number(value): return String(value)
        case let .boolean(value): return value ? "Yes" : "No"
        }
    }
}

public struct DastakAdminAuditSummary: Decodable, Equatable, Sendable {
    public let values: [String: DastakAdminAuditValue]
    // Match the reviewed server projection, never render arbitrary audit metadata.
    private enum Key: String, CodingKey, CaseIterable {
        case beforeStatus, afterStatus, beforeVersion, afterVersion, fromStatus, toStatus, status, decision, outcome, scope, version
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var values: [String: DastakAdminAuditValue] = [:]
        for key in Key.allCases {
            if let value = try container.decodeIfPresent(DastakAdminAuditValue.self, forKey: key) { values[key.rawValue] = value }
        }
        self.values = values
    }
}
public struct DastakAdminAuditEvent: Decodable, Equatable, Identifiable, Sendable {
    public enum Source: String, Decodable, Sendable { case legacy = "LEGACY", current = "V1" }
    public struct Actor: Decodable, Equatable, Sendable { public let id: UUID?; public let displayName: String }
    public struct Resource: Decodable, Equatable, Sendable { public let type: String; public let id: UUID? }
    public struct References: Decodable, Equatable, Sendable {
        public let orderId: UUID?
        public let branchId: UUID?
        public let accountId: UUID?
    }
    public let source: Source
    public let eventId: String
    public let occurredAt: String
    public let actor: Actor
    public let action: String
    public let resource: Resource
    public let reason: String?
    public let summary: DastakAdminAuditSummary
    public let references: References
    public var id: String { eventId }
}
public struct DastakAdminAuditCursor: Codable, Equatable, Sendable {
    public let occurredAt: String
    public let eventId: String
}
public struct DastakAdminAuditPage: Decodable, Sendable {
    public let events: [DastakAdminAuditEvent]
    public let hasMore: Bool
    public let nextCursor: DastakAdminAuditCursor?
}
public struct DastakAdminAuditFilters: Encodable, Equatable, Sendable {
    public var fromOccurredAt: String?
    public var toOccurredAt: String?
    public var actorQuery: String?
    public var action: String?
    public var resourceType: String?
    public var resourceId: UUID?
    public var orderId: UUID?
    public var branchId: UUID?
    public var accountId: UUID?
    public var eventId: String?
    public init() {}
    public var isValid: Bool {
        if let fromOccurredAt, DastakAdminContract.date(fromOccurredAt) == nil { return false }
        if let toOccurredAt, DastakAdminContract.date(toOccurredAt) == nil { return false }
        if let from = fromOccurredAt.flatMap(DastakAdminContract.date), let to = toOccurredAt.flatMap(DastakAdminContract.date), from > to { return false }
        return (actorQuery?.count ?? 0) <= 100 && (action?.count ?? 0) <= 120 && (resourceType?.count ?? 0) <= 120 &&
            (eventId == nil || DastakAdminContract.isAuditID(eventId!))
    }
}
public protocol DastakAdminAuditHistoryClient: Sendable {
    func auditHistory(filters: DastakAdminAuditFilters, limit: Int, cursor: DastakAdminAuditCursor?,
        idempotencyKey: IdempotencyKey) async throws -> DastakAdminAuditPage
}
extension SupabaseDastakV1AdminClient {
    private struct AuditRequest: Encodable, Sendable {
        let filters: DastakAdminAuditFilters
        let limit: Int
        let cursor: DastakAdminAuditCursor?
        enum CodingKeys: String, CodingKey { case operation, limit, cursor }
        func encode(to encoder: any Encoder) throws {
            try filters.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("adminAuditHistory", forKey: .operation)
            try container.encode(limit, forKey: .limit)
            try container.encodeIfPresent(cursor, forKey: .cursor)
        }
    }
    public func auditHistory(filters: DastakAdminAuditFilters, limit: Int, cursor: DastakAdminAuditCursor?,
        idempotencyKey: IdempotencyKey) async throws -> DastakAdminAuditPage {
        guard filters.isValid, (1...100).contains(limit) else { throw FunctionClientError.invalidResponse }
        if let cursor, DastakAdminContract.date(cursor.occurredAt) == nil || !DastakAdminContract.isAuditID(cursor.eventId) {
            throw FunctionClientError.invalidResponse
        }
        return try await functions.invoke("dastak-v1-orders", request: AuditRequest(filters: filters, limit: limit, cursor: cursor), idempotencyKey: idempotencyKey)
    }
}
