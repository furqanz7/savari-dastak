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

struct DastakRefreshNotice: View {
    let failure: DastakCustomerRefreshFailure
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: failure.symbol)
                .font(.title3)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(failure.title)
                    .font(.subheadline.bold())
                Text(failure.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: MarketplaceSpacing.small)

            Button(failure.actionTitle, action: action)
                .font(.footnote.bold())
                .buttonStyle(.bordered)
                .tint(MarketplaceColors.dastakAccent.color)
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }
}

struct DastakProductArtwork: View {
    private let kind: CatalogueKind?
    private let customSymbol: String?
    private let imageKey: String?

    init(kind: CatalogueKind) {
        self.kind = kind
        customSymbol = nil
        imageKey = nil
    }

    init(symbol: String) {
        kind = nil
        customSymbol = symbol
        imageKey = nil
    }

    init(imageKey: String?, fallbackSymbol: String = "basket") {
        kind = nil
        customSymbol = fallbackSymbol
        self.imageKey = imageKey
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MarketplaceColors.accent(for: colorScheme).opacity(0.08)
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
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

    private var fallback: some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(MarketplaceColors.accent(for: colorScheme))
    }

    private var imageURL: URL? {
        guard let imageKey,
              let base = Bundle.main.object(forInfoDictionaryKey: "MarketplaceSupabaseURL") as? String
        else { return nil }
        let segments = imageKey.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty,
              segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") })
        else { return nil }
        let encoded = segments.compactMap {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        }
        guard encoded.count == segments.count else { return nil }
        return URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) +
            "/storage/v1/object/public/dastak-catalogue/" + encoded.joined(separator: "/"))
    }

    private var symbol: String {
        if let customSymbol { return customSymbol }
        return switch kind {
        case .general, .none: "shippingbox"
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

struct DastakApplicationProgress: View {
    let currentStep: Int
    private let steps = ["Account", "Application", "Review"]

    init(currentStep: Int = 2) {
        self.currentStep = currentStep
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                let step = index + 1
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(step <= currentStep
                                    ? MarketplaceColors.dastakAccent.color
                                    : MarketplaceColors.dastakSurface.color)
                                .overlay {
                                    Circle().stroke(
                                        step <= currentStep
                                            ? MarketplaceColors.dastakAccent.color
                                            : MarketplaceColors.dividerDark.color,
                                        lineWidth: 1
                                    )
                                }
                            if step < currentStep {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(MarketplaceColors.dastakIconBackground.color)
                            } else {
                                Text(step.formatted())
                                    .font(.caption.bold())
                                    .foregroundStyle(step == currentStep
                                        ? MarketplaceColors.dastakIconBackground.color
                                        : .secondary)
                            }
                        }
                        .frame(width: 28, height: 28)

                        if step < steps.count {
                            Rectangle()
                                .fill(MarketplaceColors.dividerDark.color)
                                .frame(height: 1)
                                .padding(.horizontal, 6)
                        }
                    }
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(step <= currentStep ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep) of \(steps.count), \(steps[currentStep - 1])")
    }
}
