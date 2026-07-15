import SwiftUI

extension View {
    func savariCardStyle(paddingV: CGFloat = 20, paddingH: CGFloat = 16, cornerRadius: CGFloat = 16) -> some View {
        modifier(SavariCardStyleModifier(paddingV: paddingV, paddingH: paddingH, cornerRadius: cornerRadius))
    }
}

private struct SavariCardStyleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let paddingV: CGFloat
    let paddingH: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .padding(.horizontal, paddingH)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(cornerRadius)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                .padding(.vertical, paddingV)
        } else {
            content
                .padding(.horizontal, paddingH)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(cornerRadius)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                .padding(.vertical, paddingV)
        }
    }
}
