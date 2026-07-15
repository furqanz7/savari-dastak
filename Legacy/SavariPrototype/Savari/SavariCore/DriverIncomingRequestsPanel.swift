import SwiftUI

struct DriverIncomingRequestsPanel: View {
    let requests: [[String: Any]]
    let onAccept: ([String: Any]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ride requests", systemImage: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(requests.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
            }

            ForEach(Array(requests.prefix(3).enumerated()), id: \.offset) { _, ride in
                DriverIncomingRequestRow(ride: ride) {
                    onAccept(ride)
                }
            }
        }
        .padding(14)
        .background(Material.ultraThin)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }
}

private struct DriverIncomingRequestRow: View {
    let ride: [String: Any]
    let onAccept: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ride \(RideRowFormatter.shortId(ride))")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(RideRowFormatter.distanceString(for: ride)) • \(RideRowFormatter.vehicleType(for: ride))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("₹\(RideRowFormatter.fareString(for: ride))")
                .font(.system(size: 14, weight: .semibold))

            Button("Accept", action: onAccept)
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
        }
        .padding(10)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(12)
    }
}
