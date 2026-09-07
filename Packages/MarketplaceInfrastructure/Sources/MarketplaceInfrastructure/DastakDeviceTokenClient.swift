import Foundation
import MarketplaceFoundation

public struct DastakDeviceTokenRegistration: Encodable, Sendable {
    public let token: String
    public let platform: String
    public let applicationId: String
    public let apnsEnvironment: String?

    public init(token: String, platform: String = "ios", applicationId: String = "com.dastak.app", apnsEnvironment: String? = nil) {
        self.token = token
        self.platform = platform
        self.applicationId = applicationId
        self.apnsEnvironment = apnsEnvironment
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
    public func register(
        token: String, applicationId: String = "com.dastak.app",
        apnsEnvironment: String? = nil, idempotencyKey: IdempotencyKey
    ) async throws -> Bool {
        let response: DastakDeviceTokenRegistrationResponse = try await functions.invoke(
            "register-device-token",
            request: DastakDeviceTokenRegistration(token: token, applicationId: applicationId, apnsEnvironment: apnsEnvironment),
            idempotencyKey: idempotencyKey
        )
        return response.registered
    }
}
