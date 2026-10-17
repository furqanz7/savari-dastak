import Foundation

actor MarketplaceAccessTokenBroker {
    typealias Loader = @Sendable () async throws -> String?

    private let loader: Loader
    private let timeout: Duration
    private var inFlight: (id: UUID, task: Task<String?, Error>)?

    init(timeout: Duration = .seconds(8), loader: @escaping Loader) {
        self.loader = loader
        self.timeout = timeout
    }

    func accessToken() async throws -> String? {
        if let inFlight {
            return try await inFlight.task.value
        }

        let loader = loader, timeout = timeout, id = UUID()
        let task = Task { try await MarketplaceRequestDeadline.run(after: timeout, operation: loader) }
        inFlight = (id, task)
        defer { if inFlight?.id == id { inFlight = nil } }
        return try await task.value
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
    /// Explicit local environment; never inferred from an account, URL or remote claim.
    public let isDemonstration: Bool
    public let functions: any FunctionClient
    public let orderEvents: any OrderEventClient
    public let adminEvents: any AdminEventClient

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
    private let sessionRefresher: @Sendable () async throws -> Void

    init(
        functions: any FunctionClient,
        isDemonstration: Bool = false,
        orderEvents: any OrderEventClient = NoopOrderEventClient(),
        adminEvents: any AdminEventClient = NoopAdminEventClient(),
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
        },
        sessionRefresher: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.isDemonstration = isDemonstration
        self.functions = functions
        self.orderEvents = orderEvents
        self.adminEvents = adminEvents
        self.accountIDProvider = accountIDProvider
        self.objectUploader = objectUploader
        self.checkoutCustomerProvider = checkoutCustomerProvider
        self.appAccessProvider = appAccessProvider
        self.oauthIdentityLinker = oauthIdentityLinker
        self.oauthReauthenticator = oauthReauthenticator
        self.sessionRefresher = sessionRefresher
    }

    public func accountID() async throws -> UUID {
        try await accountIDProvider()
    }

    public func refreshSession() async throws {
        try await sessionRefresher()
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
