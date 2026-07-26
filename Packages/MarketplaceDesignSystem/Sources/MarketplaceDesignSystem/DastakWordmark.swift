import SwiftUI

public enum MarketplaceWordmark {
    public static let dastakLatin = "Dastak"
    public static let dastakUrdu = "دستک"
    public static let savariLatin = "Savari"
    public static let savariUrdu = "سواری"
}

public enum MarketplaceBrand: Sendable {
    case dastak
    case savari

    var latinName: String {
        switch self {
        case .dastak: MarketplaceWordmark.dastakLatin
        case .savari: MarketplaceWordmark.savariLatin
        }
    }

    var urduName: String {
        switch self {
        case .dastak: MarketplaceWordmark.dastakUrdu
        case .savari: MarketplaceWordmark.savariUrdu
        }
    }
}

public struct MarketplaceBilingualWordmark: View {
    private let brand: MarketplaceBrand
    private let size: CGFloat

    public init(
        brand: MarketplaceBrand,
        size: CGFloat = 34
    ) {
        self.brand = brand
        self.size = size
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.22) {
            Text(brand.latinName)
                .font(.system(size: size, weight: .light, design: .default))

            Text(brand.urduName)
                .font(.system(size: size * 0.84, weight: .regular))
                .environment(\.layoutDirection, .rightToLeft)
                .baselineOffset(size * 0.04)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(brand.latinName)
    }
}

public struct DastakWordmark: View {
    private let size: CGFloat

    public init(size: CGFloat = 34) {
        self.size = size
    }

    public var body: some View {
        MarketplaceBilingualWordmark(brand: .dastak, size: size)
    }
}
