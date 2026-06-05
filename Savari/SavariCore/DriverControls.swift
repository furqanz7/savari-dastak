import SwiftUI

struct DriverControls: View {
    let isOnline: Bool
    let activeDriverCount: Int
    let onGoOnline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onGoOnline) {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text(isOnline ? "Online" : "Go Online")
                }
            }
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
            .frame(maxWidth: 220)
            .disabled(isOnline)

            Spacer().frame(width: 8)

            VStack(alignment: .trailing) {
                Text("Active drivers: \(activeDriverCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
