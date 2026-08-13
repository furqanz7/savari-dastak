import SwiftUI

public struct MarketplaceRGB: Equatable, Sendable {
    public let hex: UInt32

    public init(hex: UInt32) {
        self.hex = hex
    }

    public var color: Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

public enum MarketplaceColors {
    public static let dastakBrand = MarketplaceRGB(hex: 0x3A241A)
    public static let dastakIconBackground = MarketplaceRGB(hex: 0x21130E)
    public static let dastakAccent = MarketplaceRGB(hex: 0xB08D57)
    public static let dastakAccentDark = MarketplaceRGB(hex: 0xD1B37E)
    public static let dastakAccentSoft = MarketplaceRGB(hex: 0x2A2018)
    public static let savariAccent = MarketplaceRGB(hex: 0x138A5B)
    public static let route = MarketplaceRGB(hex: 0x007AFF)

    public static let primaryAction = MarketplaceRGB(hex: 0x21130E)
    public static let primaryActionForeground = MarketplaceRGB(hex: 0xF5F2EC)
    public static let destructive = MarketplaceRGB(hex: 0xA65A45)
    public static let success = MarketplaceRGB(hex: 0x5F7650)
    public static let warning = MarketplaceRGB(hex: 0xB08D57)

    public static let canvasLight = MarketplaceRGB(hex: 0xF4EBDD)
    public static let canvasDark = MarketplaceRGB(hex: 0x0F0F10)
    public static let surfaceLight = MarketplaceRGB(hex: 0xFFF9F2)
    public static let surfaceDark = MarketplaceRGB(hex: 0x181716)
    public static let textPrimaryLight = MarketplaceRGB(hex: 0x21130E)
    public static let textPrimaryDark = MarketplaceRGB(hex: 0xF5F2EC)
    public static let textSecondaryLight = MarketplaceRGB(hex: 0x9A938B)
    public static let textSecondaryDark = MarketplaceRGB(hex: 0xB8B1A8)
    public static let dividerLight = MarketplaceRGB(hex: 0xD9CCBF)
    public static let dividerDark = MarketplaceRGB(hex: 0x2D2520)

    // Explicit Dastak aliases keep product views on the shared palette.
    public static let dastakBackground = canvasDark
    public static let dastakSurface = surfaceDark
    public static let dastakText = textPrimaryDark
    public static let dastakSecondaryText = textSecondaryDark

    public static func accent(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? dastakAccentDark : dastakAccent).color
    }

    public static func canvas(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? canvasDark : canvasLight).color
    }

    public static func surface(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? surfaceDark : surfaceLight).color
    }

    public static func primaryText(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? textPrimaryDark : textPrimaryLight).color
    }

    public static func secondaryText(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? textSecondaryDark : textSecondaryLight).color
    }

    public static func divider(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? dividerDark : dividerLight).color
    }
}

public enum MarketplaceSpacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let compact: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
    public static let xxLarge: CGFloat = 48
}

public enum MarketplaceMetrics {
    public static let minimumTouchTarget: CGFloat = 44
    public static let compactCornerRadius: CGFloat = 8
    public static let controlCornerRadius: CGFloat = 14
    public static let sheetCornerRadius: CGFloat = 28
    public static let contentMaxWidth: CGFloat = 720
}

public enum MarketplaceTypography {
    public static var hero: Font {
        .system(.largeTitle, design: .default, weight: .bold)
    }

    public static var sectionTitle: Font {
        .system(.title2, design: .default, weight: .bold)
    }

    public static var itemTitle: Font {
        .system(.headline, design: .default, weight: .semibold)
    }

    public static var body: Font {
        .system(.body, design: .default, weight: .regular)
    }

    public static var supporting: Font {
        .system(.subheadline, design: .default, weight: .regular)
    }

    public static var caption: Font {
        .system(.caption, design: .default, weight: .medium)
    }
}
