import Foundation
import MarketplaceFoundation

public struct DastakDeviceTokenRegistration: Encodable, Sendable {
    public let token: String
    public let platform: String

    public init(token: String, platform: String = "ios") {
        self.token = token
        self.platform = platform
    }
}

public struct DastakDeviceTokenRegistrationResponse: Decodable, Sendable {
    public let registered: Bool
}

public struct SupabaseDastakDeviceTokenClient: Sendable {
    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    @discardableResult
    public func register(token: String, idempotencyKey: IdempotencyKey) async throws -> Bool {
        let response: DastakDeviceTokenRegistrationResponse = try await functions.invoke(
            "register-device-token",
            request: DastakDeviceTokenRegistration(token: token),
            idempotencyKey: idempotencyKey
        )
        return response.registered
    }
}
