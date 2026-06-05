import SwiftUI
import CoreLocation
import UIKit

struct DistanceETABox: View {
    let distanceMeters: CLLocationDistance?
    let etaSeconds: TimeInterval?
    var onUse: () -> Void

    @State private var pressed = false

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                if let distanceMeters {
                    Text(RideFormat.distance(distanceMeters))
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Text("—")
                        .font(.system(size: 16, weight: .semibold))
                }

                if let etaSeconds, etaSeconds > 0 {
                    Text("~\(Int(etaSeconds / 60)) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 4)

            Spacer()

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onUse()
            }) {
                HStack(spacing: 10) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .buttonStyle(LiquidGlassButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            pressed
                            ? Color.white.opacity(0.22)
                            : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        .scaleEffect(pressed ? 0.985 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: pressed)
        .onLongPressGesture(minimumDuration: 0.01, pressing: { isPressing in
            pressed = isPressing
        }, perform: {})
        .padding(.horizontal)
    }
}
