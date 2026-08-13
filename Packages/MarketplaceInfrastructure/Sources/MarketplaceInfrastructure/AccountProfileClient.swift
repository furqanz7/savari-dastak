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

public protocol AccountProfileClient: Sendable {
    func snapshot(idempotencyKey: IdempotencyKey) async throws -> MarketplaceAccountProfile
    func update(
        displayName: String,
        phoneNumber: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MarketplaceAccountProfile
    func deleteAccount(idempotencyKey: IdempotencyKey) async throws
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
}
