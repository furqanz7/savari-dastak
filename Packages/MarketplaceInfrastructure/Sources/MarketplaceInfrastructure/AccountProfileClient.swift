import Foundation
import MarketplaceFoundation

public struct MarketplaceAccountProfile: Codable, Equatable, Sendable {
    public let displayName: String
    public let phoneNumber: String

    public init(displayName: String, phoneNumber: String) {
        self.displayName = displayName
        self.phoneNumber = phoneNumber
    }
}

public enum MarketplaceOAuthProvider: String, Codable, CaseIterable, Equatable, Sendable {
    case apple
    case google
}

public struct MarketplaceLinkedIdentity: Codable, Equatable, Sendable {
    public enum LinkKind: String, Codable, Equatable, Sendable {
        case origin = "ORIGIN"
        case explicit = "EXPLICIT"
    }

    public let provider: MarketplaceOAuthProvider
    public let linkKind: LinkKind
    public let linkedAt: Date
}

public protocol AccountProfileClient: Sendable {
    func snapshot(idempotencyKey: IdempotencyKey) async throws -> MarketplaceAccountProfile
    func update(
        displayName: String,
        phoneNumber: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MarketplaceAccountProfile
    func identitySnapshot(idempotencyKey: IdempotencyKey) async throws -> [MarketplaceLinkedIdentity]
    func beginIdentityLink(
        provider: MarketplaceOAuthProvider,
        idempotencyKey: IdempotencyKey
    ) async throws
    func exportAccount(idempotencyKey: IdempotencyKey) async throws -> MarketplaceAccountExport
    func deleteAccount(idempotencyKey: IdempotencyKey) async throws
}

public struct MarketplaceAccountExport: Equatable, Sendable {
    public let filename: String
    public let data: Data

    public init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }
}

public struct SupabaseAccountProfileClient: AccountProfileClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let displayName: String?
        let phoneNumber: String?
    }

    private struct ProfileResponse: Decodable, Sendable {
        let profile: MarketplaceAccountProfile
    }

    private struct DeleteResponse: Decodable, Sendable {
        let deleted: Bool
    }

    private struct IdentitySnapshotResponse: Decodable, Sendable {
        let providers: [MarketplaceLinkedIdentity]
    }

    private struct IdentityLinkResponse: Decodable, Sendable {
        let provider: MarketplaceOAuthProvider
    }

    private struct ExportResponse: Decodable, Sendable {
        let filename: String
        let export: MarketplaceJSONValue
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func snapshot(idempotencyKey: IdempotencyKey) async throws -> MarketplaceAccountProfile {
        let response: ProfileResponse = try await functions.invoke(
            "account-profile",
            request: Request(operation: "snapshot", displayName: nil, phoneNumber: nil),
            idempotencyKey: idempotencyKey
        )
        return response.profile
    }

    public func update(
        displayName: String,
        phoneNumber: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MarketplaceAccountProfile {
        let response: ProfileResponse = try await functions.invoke(
            "account-profile",
            request: Request(
                operation: "update",
                displayName: displayName,
                phoneNumber: phoneNumber
            ),
            idempotencyKey: idempotencyKey
        )
        return response.profile
    }

    public func deleteAccount(idempotencyKey: IdempotencyKey) async throws {
        let response: DeleteResponse = try await functions.invoke(
            "account-profile",
            request: Request(operation: "delete", displayName: nil, phoneNumber: nil),
            idempotencyKey: idempotencyKey
        )
        guard response.deleted else { throw FunctionClientError.invalidResponse }
    }

    public func exportAccount(idempotencyKey: IdempotencyKey) async throws -> MarketplaceAccountExport {
        let response: ExportResponse = try await functions.invoke(
            "account-profile",
            request: Request(operation: "export", displayName: nil, phoneNumber: nil),
            idempotencyKey: idempotencyKey
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return MarketplaceAccountExport(
            filename: response.filename,
            data: try encoder.encode(response.export)
        )
    }

    public func identitySnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> [MarketplaceLinkedIdentity] {
        let response: IdentitySnapshotResponse = try await functions.invoke(
            "account-profile",
            request: Request(operation: "identitySnapshot", displayName: nil, phoneNumber: nil),
            idempotencyKey: idempotencyKey
        )
        return response.providers
    }

    public func beginIdentityLink(
        provider: MarketplaceOAuthProvider,
        idempotencyKey: IdempotencyKey
    ) async throws {
        struct LinkRequest: Encodable, Sendable {
            let operation = "beginIdentityLink"
            let provider: MarketplaceOAuthProvider
        }
        let response: IdentityLinkResponse = try await functions.invoke(
            "account-profile",
            request: LinkRequest(provider: provider),
            idempotencyKey: idempotencyKey
        )
        guard response.provider == provider else { throw FunctionClientError.invalidResponse }
    }
}

private enum MarketplaceJSONValue: Codable, Equatable, Sendable {
    case object([String: MarketplaceJSONValue])
    case array([MarketplaceJSONValue])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: MarketplaceJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([MarketplaceJSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
