import Foundation

/// Lossless read-only trace values. Mutations use a separate allow-listed request type.
public enum DastakAdminTraceValue: Codable, Equatable, Sendable {
    case object([String: Self]), array([Self]), string(String), integer(Int), number(Double), boolean(Bool), null
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .boolean(v) }
        else if let v = try? value.decode(Int.self) { self = .integer(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([Self].self) { self = .array(v) }
        else { self = .object(try value.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .object(v): try value.encode(v)
        case let .array(v): try value.encode(v)
        case let .string(v): try value.encode(v)
        case let .integer(v): try value.encode(v)
        case let .number(v): try value.encode(v)
        case let .boolean(v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }
}

public struct DastakAdminTraceRecord: Codable, Equatable, Sendable {
    public let fields: [String: DastakAdminTraceValue]
    public init(fields: [String: DastakAdminTraceValue]) { self.fields = fields }
    public init(from decoder: Decoder) throws { fields = try decoder.singleValueContainer().decode([String: DastakAdminTraceValue].self) }
    public func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(fields) }
    public func text(_ key: String) -> String? { if case let .string(v) = fields[key] { v } else { nil } }
    public func integer(_ key: String) -> Int? { if case let .integer(v) = fields[key] { v } else { nil } }
    public func flag(_ key: String) -> Bool? { if case let .boolean(v) = fields[key] { v } else { nil } }
    public func uuid(_ key: String = "id") -> UUID? { text(key).flatMap(UUID.init(uuidString:)) }
    public func record(_ key: String) -> Self? { if case let .object(v) = fields[key] { Self(fields: v) } else { nil } }
    public func rows(_ key: String) -> [Self]? {
        guard case let .array(values) = fields[key] else { return nil }
        let rows: [Self] = values.compactMap { if case let .object(v) = $0 { Self(fields: v) } else { nil } }
        return rows.count == values.count ? rows : nil
    }
}

public struct DastakAdminFailureFinance: Decodable, Equatable, Sendable {
    public let record: DastakAdminTraceRecord
    public init(from decoder: Decoder) throws {
        let record = try DastakAdminTraceRecord(from: decoder)
        let feeds = ["recoveryCases", "customerIssues", "returns", "refunds", "settlements", "platformFees", "royaltyLedger", "royaltyBalances", "withdrawals"]
        guard feeds.allSatisfy({ record.rows($0) != nil }), let permissions = record.record("permissions"),
              ["canManageRecovery", "canApproveReturns", "canApproveRefunds", "canProcessRefunds", "canManageSettlements"].allSatisfy({ permissions.flag($0) != nil }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Incomplete finance trace"))
        }
        for key in ["recoveryCases", "customerIssues", "returns", "refunds", "settlements"] {
            let rows = record.rows(key)!
            guard rows.allSatisfy({ $0.uuid() != nil && ($0.integer("version") ?? 0) > 0 && $0.text("status") != nil }),
                  Set(rows.compactMap { $0.uuid() }).count == rows.count else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid finance identity/version"))
            }
        }
        self.record = record
    }
}

public struct DastakAdminExecutionCursor: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let orderId: UUID
}
public struct DastakAdminExecutionPage: Decodable, Sendable {
    public let orders: [DastakV1AdminOrder]
    public let scope: String
    public let hasMore: Bool
    public let nextCursor: DastakAdminExecutionCursor?
}
