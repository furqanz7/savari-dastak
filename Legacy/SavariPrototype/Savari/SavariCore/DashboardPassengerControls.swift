import SwiftUI

struct DashboardPassengerControls: View {
    @ObservedObject var vm: DashboardViewModelRealtime
    let onCancelMidTrip: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            passengerStatus
        }
    }

    @ViewBuilder
    private var passengerStatus: some View {
        switch rideStatus {
        case "arrived":
            if let code = vm.activeRideRow?["boarding_code"] as? String {
                VStack(spacing: 10) {
                    BoardingCodeView(
                        code: code,
                        ttlSeconds: vm.activeRideRow?["boarding_code_ttl"] as? Int
                    )
                    Text("Share this PIN with your driver")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 12)
            }
        case "boarded":
            statusChip("Boarding confirmed", systemImage: "checkmark.circle.fill", color: .green)
        case "in_progress":
            VStack(spacing: 10) {
                statusChip("Trip in progress", systemImage: "location.fill", color: .blue)
                Button(role: .destructive, action: onCancelMidTrip) {
                    Label("Cancel trip", systemImage: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(LiquidGlassButtonStyle())
            }
        case "completed":
            statusChip("Ride completed", systemImage: "checkmark.circle.fill", color: .green)
        case "ride_finished":
            statusChip(
                "Ride finished - Pay ₹\(RideRowFormatter.fareString(for: vm.activeRideRow ?? [:]))",
                systemImage: "indianrupeesign.circle.fill",
                color: .orange
            )
        case "passenger_cancelled_in_trip":
            statusChip(
                "Trip cancelled - Pay ₹\(RideRowFormatter.fareString(for: vm.activeRideRow ?? [:]))",
                systemImage: "indianrupeesign.circle.fill",
                color: .orange
            )
        case "payment_collected":
            statusChip(
                "Payment collected",
                systemImage: "checkmark.circle.fill",
                color: .green
            )
        default:
            EmptyView()
        }
    }

    private var rideStatus: String {
        (vm.activeRideRow?["status"] as? String)?.lowercased() ?? ""
    }

    private func statusChip(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Material.ultraThin)
            .cornerRadius(14)
            .foregroundColor(color)
    }
}
