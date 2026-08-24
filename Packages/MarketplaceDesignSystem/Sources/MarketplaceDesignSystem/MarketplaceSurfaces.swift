import SwiftUI

/// Dastak's shared dark canvas with a quiet, deterministic matte grain.
public struct DastakMatteBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            MarketplaceColors.dastakBackground.color

            RadialGradient(
                colors: [
                    MarketplaceColors.dastakAccent.color.opacity(0.19),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    Color(red: 58 / 255, green: 36 / 255, blue: 26 / 255).opacity(0.34),
                    .clear,
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 420
            )

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )

            DastakMatteGrain()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct DastakMatteGrain: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let area = size.width * size.height
            let speckCount = min(6_000, max(1_200, Int(area / 90)))
            var random = DastakMatteRandom(seed: 0xDA57_A4C1_7E23)

            for index in 0..<speckCount {
                let x = random.unitInterval() * size.width
                let y = random.unitInterval() * size.height
                let diameter = 0.35 + (random.unitInterval() * 0.90)
                let alpha = 0.045 + (random.unitInterval() * 0.085)
                let color = index.isMultiple(of: 4)
                    ? Color.black.opacity(alpha)
                    : Color(red: 232 / 255, green: 224 / 255, blue: 211 / 255).opacity(alpha)

                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                    with: .color(color)
                )
            }
        }
        .blendMode(.softLight)
        .opacity(0.72)
    }
}

private struct DastakMatteRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func unitInterval() -> Double {
        state = 6_364_136_223_846_793_005 &* state &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / 9_007_199_254_740_992
    }
}

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
