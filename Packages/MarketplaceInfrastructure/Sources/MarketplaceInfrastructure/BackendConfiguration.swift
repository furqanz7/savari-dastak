import Foundation

public enum MarketplaceProduct: String, Equatable, Sendable {
    case savari = "Savari"
    case dastak = "Dastak"
}

public enum BackendConfigurationError: Error, Equatable, Sendable {
    case invalidProduct
    case notConfigured
}

public struct BackendConfiguration: Equatable, Sendable {
    public let product: String
    public let supabaseURL: URL
    public let publishableKey: String

    public init(product: String, supabaseURL: URL, publishableKey: String) {
        self.product = product
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
    }

    public static func runtime(
        product: MarketplaceProduct,
        bundle: Bundle = .main
    ) throws -> BackendConfiguration {
        try runtime(product: product, infoDictionary: bundle.infoDictionary ?? [:])
    }

    public static func runtime(
        product: MarketplaceProduct,
        infoDictionary: [String: Any]
    ) throws -> BackendConfiguration {
        guard infoDictionary["MarketplaceProduct"] as? String == product.rawValue else {
            throw BackendConfigurationError.invalidProduct
        }

        let urlValue = (infoDictionary["MarketplaceSupabaseURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (infoDictionary["MarketplaceSupabasePublishableKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let urlValue,
            let url = URL(string: urlValue),
            url.scheme == "https",
            url.host != nil,
            url.host != "not-configured.invalid",
            let key,
            !key.isEmpty,
            key != "not-configured"
        else {
            throw BackendConfigurationError.notConfigured
        }

        return BackendConfiguration(
            product: product.rawValue,
            supabaseURL: url,
            publishableKey: key
        )
    }
}
