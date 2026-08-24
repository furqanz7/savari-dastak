import Foundation

public struct MarketplaceLegalLinks: Equatable, Sendable {
    public static let privacyPolicyKey = "MarketplacePrivacyPolicyURL"
    public static let termsKey = "MarketplaceTermsURL"
    public static let supportKey = "MarketplaceSupportURL"

    public let privacyPolicy: URL?
    public let terms: URL?
    public let support: URL?

    public init(bundle: Bundle = .main) {
        self.init(values: bundle.infoDictionary ?? [:])
    }

    public init(values: [String: Any]) {
        privacyPolicy = Self.validURL(values[Self.privacyPolicyKey], allowedSchemes: ["https"])
        terms = Self.validURL(values[Self.termsKey], allowedSchemes: ["https"])
        support = Self.validURL(values[Self.supportKey], allowedSchemes: ["https"])
    }

    private static func validURL(_ rawValue: Any?, allowedSchemes: Set<String>) -> URL? {
        guard let value = rawValue as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else { return nil }
        if scheme == "https" {
            guard url.host?.isEmpty == false else { return nil }
        }
        return url
    }
}
