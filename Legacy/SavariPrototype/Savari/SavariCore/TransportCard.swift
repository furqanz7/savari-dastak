import SwiftUI
import UIKit

struct TransportCard: View {
    let title: String
    let fare: Double?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                if let fare {
                    Text("₹\(Int(fare))")
                        .font(.system(size: 20, weight: .bold))
                } else {
                    Text("—")
                        .font(.headline)
                }
            }
            .frame(width: 144, height: 96)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            isSelected
                            ? LinearGradient(colors: [Color.primary.opacity(0.96), Color.primary.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(.secondarySystemBackground), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                        .blendMode(.overlay)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.12) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 18 : 12, x: 0, y: isSelected ? 10 : 8)
            .shadow(color: Color.white.opacity(0.06), radius: 1, x: 0, y: 1)
            .foregroundColor(
                isSelected
                ? Color(UIColor.systemBackground)
                : Color.primary.opacity(0.92)
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSelected)
        }
        .buttonStyle(LiquidGlassButtonStyle())
    }
}
