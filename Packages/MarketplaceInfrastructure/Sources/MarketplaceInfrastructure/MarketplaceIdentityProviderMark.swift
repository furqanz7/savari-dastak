import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct MarketplaceIdentityProviderMark: View {
    private let provider: MarketplaceOAuthProvider

    public init(_ provider: MarketplaceOAuthProvider) {
        self.provider = provider
    }

    public var body: some View {
        if provider == .apple {
            Image(systemName: "apple.logo")
                .font(.system(size: 18, weight: .semibold))
                .accessibilityHidden(true)
        } else {
            googleMark
        }
    }

    @ViewBuilder
    private var googleMark: some View {
        #if canImport(UIKit)
        if let url = Bundle.module.url(forResource: "GoogleG", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 19, height: 19)
                .accessibilityHidden(true)
        } else {
            fallbackGoogleMark
        }
        #else
        fallbackGoogleMark
        #endif
    }

    private var fallbackGoogleMark: some View {
        Image("GoogleG", bundle: .module)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 19, height: 19)
            .accessibilityHidden(true)
    }
}
