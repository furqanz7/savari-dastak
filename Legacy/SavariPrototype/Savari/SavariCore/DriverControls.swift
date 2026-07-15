import SwiftUI

struct DriverControls: View {
    let isOnline: Bool
    let isRideActive: Bool
    let onGoOnline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isOnline {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Online")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(isRideActive ? "Ride active" : "Waiting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Material.ultraThin)
                .cornerRadius(16)
            } else {
                Button(action: onGoOnline) {
                    HStack {
                        Image(systemName: "power.circle.fill")
                        Text("Go Online")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
            }
        }
        .frame(maxWidth: 360)
    }
}
