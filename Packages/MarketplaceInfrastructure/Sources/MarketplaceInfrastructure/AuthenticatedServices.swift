import Foundation

public enum MarketplaceAuthenticatedServicesError: Error, Equatable, Sendable {
    case authenticationRequired
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

    private let accountIDProvider: @Sendable () async throws -> UUID
    private let objectUploader: @Sendable (
        String,
        String,
        Data,
        String,
        String
    ) async throws -> Void
    private let checkoutCustomerProvider: @Sendable () async throws -> MarketplaceCheckoutCustomer?

    init(
        functions: any FunctionClient,
        accountIDProvider: @escaping @Sendable () async throws -> UUID,
        objectUploader: @escaping @Sendable (
            String,
            String,
            Data,
            String,
            String
        ) async throws -> Void,
        checkoutCustomerProvider: @escaping @Sendable () async throws -> MarketplaceCheckoutCustomer? = { nil }
    ) {
        self.functions = functions
        self.accountIDProvider = accountIDProvider
        self.objectUploader = objectUploader
        self.checkoutCustomerProvider = checkoutCustomerProvider
    }

    public func accountID() async throws -> UUID {
        try await accountIDProvider()
    }

    public func checkoutCustomer() async throws -> MarketplaceCheckoutCustomer? {
        try await checkoutCustomerProvider()
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
