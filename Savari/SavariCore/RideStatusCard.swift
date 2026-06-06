import SwiftUI
import UIKit

struct RideStatusCard: View {
    enum RideStatus {
        case matching
        case accepted(driverName: String, etaSeconds: Int?, boardingCode: String?)
    }

    let state: RideStatus
    let onCancel: () -> Void
    let onContact: () -> Void

    @State private var animate = false

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4)

            switch state {
            case .matching:
                matchingContent

            case .accepted(let driverName, let eta, let boardingCode):
                acceptedContent(driverName: driverName, eta: eta, boardingCode: boardingCode)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(Color.white.opacity(0.08))
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
        .onAppear { animate = true }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: animate)
    }

    private var matchingContent: some View {
        VStack(spacing: 12) {
            Text("Finding your ride")
                .font(.system(size: 17, weight: .semibold))

            Text("Searching nearby drivers")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 0.6 : 1)
                        .opacity(animate ? 0.25 : 1)
                        .animation(
                            .easeInOut(duration: 0.9)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: animate
                        )
                }
            }

            Button("Cancel Request", action: onCancel)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule()
                        .stroke(Color.primary.opacity(0.18))
                )
        }
    }

    private func acceptedContent(driverName: String, eta: Int?, boardingCode: String?) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)

                Text("Driver found")
                    .font(.system(size: 17, weight: .semibold))

                Text(driverName)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Divider().opacity(0.4)

            if let boardingCode, !boardingCode.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Boarding code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(boardingCode)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "number.square.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                }
                .padding(12)
                .background(Color.green.opacity(0.12))
                .cornerRadius(14)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ETA")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let eta, eta > 0 {
                        Text("~\(max(1, eta / 60)) min")
                            .font(.system(size: 16, weight: .semibold))
                    } else {
                        Text("Updating")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }

                Spacer()

                Button(action: onContact) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(12)
                        .background(Circle().fill(Color.primary))
                        .foregroundColor(Color(UIColor.systemBackground))
                        .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                }
            }

            Button(role: .destructive, action: onCancel) {
                Text("Cancel Ride")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        Capsule()
                            .stroke(Color.red.opacity(0.4))
                    )
            }
            .padding(.top, 4)
        }
    }
}
