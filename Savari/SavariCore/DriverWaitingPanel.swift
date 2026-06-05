import SwiftUI

struct DriverWaitingPanel: View {
    let isRealtimeActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Waiting for ride requests", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .semibold))

            Text(isRealtimeActive ? "New passenger requests will appear here." : "Connecting to live requests...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Material.ultraThin)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }
}
