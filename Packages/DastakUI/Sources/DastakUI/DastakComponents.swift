import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .frame(maxWidth: 320)
            }
        }
    }
}

struct DastakProductArtwork: View {
    let kind: CatalogueKind

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MarketplaceColors.accent(for: colorScheme).opacity(0.08)
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(MarketplaceColors.accent(for: colorScheme))
        }
        .aspectRatio(1.18, contentMode: .fit)
        .clipShape(
            RoundedRectangle(
                cornerRadius: MarketplaceMetrics.compactCornerRadius,
                style: .continuous
            )
        )
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch kind {
        case .general: "shippingbox"
        case .otcMedicine, .prescriptionMedicine: "cross.case"
        case .paanCorner: "checkmark.shield"
        }
    }
}

struct DastakQuantityControl: View {
    let quantity: Int
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: decrement) {
                Image(systemName: "minus")
            }
            .accessibilityLabel("Remove one")

            Text(quantity.formatted())
                .font(.subheadline.monospacedDigit().bold())
                .frame(minWidth: 32)

            Button(action: increment) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add one")
        }
        .buttonStyle(.plain)
        .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
        .padding(.horizontal, MarketplaceSpacing.small)
        .background(.thinMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: MarketplaceMetrics.controlCornerRadius,
                style: .continuous
            )
        )
    }
}

struct DastakStatusPill: View {
    let text: String
    var emphasis = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, MarketplaceSpacing.compact)
            .frame(minHeight: 30)
            .foregroundStyle(
                emphasis
                    ? MarketplaceColors.accent(for: colorScheme)
                    : MarketplaceColors.secondaryText(for: colorScheme)
            )
            .background(
                emphasis
                    ? MarketplaceColors.accent(for: colorScheme).opacity(0.12)
                    : MarketplaceColors.surface(for: colorScheme)
            )
            .clipShape(Capsule())
    }
}

struct DastakLoadingOverlay: View {
    let title: String

    var body: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            ProgressView()
            Text(title)
                .font(.subheadline)
        }
        .padding(.horizontal, MarketplaceSpacing.medium)
        .frame(minHeight: 48)
        .marketplaceGlass(cornerRadius: MarketplaceMetrics.controlCornerRadius)
    }
}
