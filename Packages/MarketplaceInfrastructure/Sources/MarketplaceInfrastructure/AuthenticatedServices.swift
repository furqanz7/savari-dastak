import Foundation

actor MarketplaceAccessTokenBroker {
    typealias Loader = @Sendable () async throws -> String?

    private let loader: Loader
    private var inFlight: Task<String?, Error>?

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func accessToken() async throws -> String? {
        if let inFlight {
            return try await inFlight.value
        }

        let loader = loader
        let task = Task { try await loader() }
        inFlight = task
        do {
            let token = try await task.value
            inFlight = nil
            return token
        } catch {
            inFlight = nil
            throw error
        }
    }
}

public enum MarketplaceAuthenticatedServicesError: Error, Equatable, Sendable {
    case authenticationRequired
    case identityMismatch
    case invalidObjectPath
}

public struct MarketplaceCheckoutCustomer: Equatable, Sendable {
    public let displayName: String
    public let email: String?
    public let phoneNumber: String

    public init(displayName: String, email: String?, phoneNumber: String) {
        self.displayName = displayName
        self.email = email
        self.phoneNumber = phoneNumber
    }
}

public struct MarketplaceAuthenticatedServices: Sendable {
    public let functions: any FunctionClient
    public let orderEvents: any OrderEventClient

    private let accountIDProvider: @Sendable () async throws -> UUID
    private let objectUploader: @Sendable (
        String,
        String,
        Data,
        String,
        String
    ) async throws -> Void
    private let checkoutCustomerProvider: @Sendable () async throws -> MarketplaceCheckoutCustomer?
    private let appAccessProvider: @Sendable (MarketplaceApplicationAccess) async throws -> AccountRoute
    private let oauthIdentityLinker: @Sendable (MarketplaceOAuthProvider) async throws -> Void
    private let oauthReauthenticator: @Sendable (MarketplaceOAuthProvider) async throws -> Void

    init(
        functions: any FunctionClient,
        orderEvents: any OrderEventClient = NoopOrderEventClient(),
        accountIDProvider: @escaping @Sendable () async throws -> UUID,
        objectUploader: @escaping @Sendable (
            String,
            String,
            Data,
            String,
            String
        ) async throws -> Void,
        checkoutCustomerProvider: @escaping @Sendable () async throws -> MarketplaceCheckoutCustomer? = { nil },
        appAccessProvider: @escaping @Sendable (MarketplaceApplicationAccess) async throws -> AccountRoute = { _ in
            .accessDenied
        },
        oauthIdentityLinker: @escaping @Sendable (MarketplaceOAuthProvider) async throws -> Void = { _ in
            throw MarketplaceAuthenticatedServicesError.authenticationRequired
        },
        oauthReauthenticator: @escaping @Sendable (MarketplaceOAuthProvider) async throws -> Void = { _ in
            throw MarketplaceAuthenticatedServicesError.authenticationRequired
        }
    ) {
        self.functions = functions
        self.orderEvents = orderEvents
        self.accountIDProvider = accountIDProvider
        self.objectUploader = objectUploader
        self.checkoutCustomerProvider = checkoutCustomerProvider
        self.appAccessProvider = appAccessProvider
        self.oauthIdentityLinker = oauthIdentityLinker
        self.oauthReauthenticator = oauthReauthenticator
    }

    public func accountID() async throws -> UUID {
        try await accountIDProvider()
    }

    public func checkoutCustomer() async throws -> MarketplaceCheckoutCustomer? {
        try await checkoutCustomerProvider()
    }

    public func resolveAppAccess(_ application: MarketplaceApplicationAccess) async throws -> AccountRoute {
        try await appAccessProvider(application)
    }

    public func linkOAuthIdentity(_ provider: MarketplaceOAuthProvider) async throws {
        try await oauthIdentityLinker(provider)
    }

    public func reauthenticateOAuthIdentity(_ provider: MarketplaceOAuthProvider) async throws {
        try await oauthReauthenticator(provider)
    }

    public func uploadObject(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        cacheControl: String = "3600"
    ) async throws {
        guard Self.validBucket(bucket), Self.validPath(path) else {
            throw MarketplaceAuthenticatedServicesError.invalidObjectPath
        }
        try await objectUploader(bucket, path, data, contentType, cacheControl)
    }

    private static func validBucket(_ value: String) -> Bool {
        guard (3...63).contains(value.count) else { return false }
        return value.allSatisfy {
            $0.isLowercase || $0.isNumber || $0 == "-" || $0 == "_"
        }
    }

    private static func validPath(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 1_024 else { return false }
        let segments = value.split(separator: "/", omittingEmptySubsequences: false)
        return segments.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\")
        }
    }
}
