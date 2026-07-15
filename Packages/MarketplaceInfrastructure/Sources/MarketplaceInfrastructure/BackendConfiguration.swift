import Foundation

public struct BackendConfiguration: Equatable, Sendable {
    public let product: String
    public let supabaseURL: URL
    public let publishableKey: String

    public init(product: String, supabaseURL: URL, publishableKey: String) {
        self.product = product
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
    }
}
