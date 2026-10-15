import MarketplaceDesignSystem
import SwiftUI

struct DastakActionNotice: View {
    let message: String
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var messageHeightLimit: CGFloat { dynamicTypeSize >= .xxxLarge ? 140 : 96 }

    private var messageText: some View {
        Text(message)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MarketplaceColors.accent(for: colorScheme))
                    .accessibilityHidden(true)
                Text("Update").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                MarketplaceFeedbackButton(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: MarketplaceMetrics.minimumTouchTarget, height: MarketplaceMetrics.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
                .accessibilityIdentifier("dastak.notice.dismiss")
            }
            // Short copy keeps its natural height; long copy stays fully
            // available through scrolling instead of consuming the whole panel.
            ViewThatFits(in: .vertical) {
                messageText
                ScrollView {
                    messageText
                }
                .frame(height: messageHeightLimit)
            }
            .frame(maxHeight: messageHeightLimit, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MarketplaceSpacing.compact)
        .foregroundStyle(MarketplaceColors.primaryText(for: colorScheme))
        .background(MarketplaceColors.surface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke((colorScheme == .dark ? MarketplaceColors.dividerDark : MarketplaceColors.dividerLight).color, lineWidth: 1)
        }
    }
}
