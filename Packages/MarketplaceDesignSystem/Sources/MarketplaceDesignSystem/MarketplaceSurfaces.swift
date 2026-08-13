import SwiftUI

public struct MarketplacePageBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(MarketplaceColors.primaryText(for: colorScheme))
            .background(MarketplaceColors.canvas(for: colorScheme).ignoresSafeArea())
    }
}

public struct MarketplaceGlassSurface: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = MarketplaceMetrics.sheetCornerRadius) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

public struct MarketplaceFlatSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content
            .background(MarketplaceColors.surface(for: colorScheme))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MarketplaceMetrics.compactCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MarketplaceMetrics.compactCornerRadius,
                    style: .continuous
                )
                .stroke(MarketplaceColors.divider(for: colorScheme), lineWidth: 1)
            }
    }
}

public struct MarketplacePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .foregroundStyle(MarketplaceColors.primaryActionForeground.color)
            .background(MarketplaceColors.primaryAction.color)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MarketplaceMetrics.controlCornerRadius,
                    style: .continuous
                )
            )
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

public struct MarketplaceSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .foregroundStyle(MarketplaceColors.primaryText(for: colorScheme))
            .background(MarketplaceColors.surface(for: colorScheme))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MarketplaceMetrics.controlCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MarketplaceMetrics.controlCornerRadius,
                    style: .continuous
                )
                .stroke(MarketplaceColors.divider(for: colorScheme), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

public struct MarketplaceIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                width: MarketplaceMetrics.minimumTouchTarget,
                height: MarketplaceMetrics.minimumTouchTarget
            )
            .foregroundStyle(MarketplaceColors.primaryText(for: colorScheme))
            .background(.regularMaterial, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

public extension View {
    func marketplacePage() -> some View {
        modifier(MarketplacePageBackground())
    }

    func marketplaceGlass(
        cornerRadius: CGFloat = MarketplaceMetrics.sheetCornerRadius
    ) -> some View {
        modifier(MarketplaceGlassSurface(cornerRadius: cornerRadius))
    }

    func marketplaceFlatSurface() -> some View {
        modifier(MarketplaceFlatSurface())
    }
}
