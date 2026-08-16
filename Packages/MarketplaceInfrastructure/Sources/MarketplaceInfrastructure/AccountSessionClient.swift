import Foundation
import MarketplaceFoundation

public struct AccountSession: Codable, Equatable, Sendable, Identifiable {
    public let sessionID: UUID
    public let deviceName: String
    public let platform: String
    public let appName: String
    public let createdAt: String
    public let lastSeenAt: String
    public let isCurrent: Bool

    public var id: UUID { sessionID }

    public init(
        sessionID: UUID,
        deviceName: String,
        platform: String,
        appName: String,
        createdAt: String,
        lastSeenAt: String,
        isCurrent: Bool
    ) {
        self.sessionID = sessionID
        self.deviceName = deviceName
        self.platform = platform
        self.appName = appName
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.isCurrent = isCurrent
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case deviceName
        case platform
        case appName
        case createdAt
        case lastSeenAt
        case isCurrent
    }
}

public struct AccountSessionCollection: Codable, Equatable, Sendable {
    public let sessions: [AccountSession]

    public init(sessions: [AccountSession]) {
        self.sessions = sessions
    }
}

public struct AccountSessionDevice: Codable, Equatable, Sendable {
    public let deviceName: String
    public let platform: String
    public let appName: String
    public let userAgent: String?

    public init(deviceName: String, platform: String, appName: String, userAgent: String? = nil) {
        self.deviceName = deviceName
        self.platform = platform
        self.appName = appName
        self.userAgent = userAgent
    }
}

public protocol AccountSessionClient: Sendable {
    func snapshot(
        device: AccountSessionDevice,
        idempotencyKey: IdempotencyKey
    ) async throws -> AccountSessionCollection

    func signOutOthers(
        device: AccountSessionDevice,
        idempotencyKey: IdempotencyKey
    ) async throws -> AccountSessionCollection

    func endCurrent(idempotencyKey: IdempotencyKey) async throws
}

public struct SupabaseAccountSessionClient: AccountSessionClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let deviceName: String?
        let platform: String?
        let appName: String?
        let userAgent: String?
    }

    private struct EndResponse: Decodable, Sendable {
        let ended: Bool
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func snapshot(
        device: AccountSessionDevice,
        idempotencyKey: IdempotencyKey
    ) async throws -> AccountSessionCollection {
        try await invoke("snapshot", device: device, idempotencyKey: idempotencyKey)
    }

    public func signOutOthers(
        device: AccountSessionDevice,
        idempotencyKey: IdempotencyKey
    ) async throws -> AccountSessionCollection {
        try await invoke("signOutOthers", device: device, idempotencyKey: idempotencyKey)
    }

    public func endCurrent(idempotencyKey: IdempotencyKey) async throws {
        let _: EndResponse = try await functions.invoke(
            "account-sessions",
            request: Request(
                operation: "endCurrent",
                deviceName: nil,
                platform: nil,
                appName: nil,
                userAgent: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    private func invoke(
        _ operation: String,
        device: AccountSessionDevice,
        idempotencyKey: IdempotencyKey
    ) async throws -> AccountSessionCollection {
        try await functions.invoke(
            "account-sessions",
            request: Request(
                operation: operation,
                deviceName: device.deviceName,
                platform: device.platform,
                appName: device.appName,
                userAgent: device.userAgent
            ),
            idempotencyKey: idempotencyKey
        )
    }
}
