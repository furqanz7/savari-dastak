import MarketplaceDesignSystem
import SwiftUI

struct DastakActionNotice: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(MarketplaceSpacing.compact)
        .background(MarketplaceColors.dastakSurface.color)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MarketplaceColors.dividerDark.color, lineWidth: 1)
        }
    }
}
