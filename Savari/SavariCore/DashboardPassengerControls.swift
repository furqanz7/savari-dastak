import SwiftUI

struct DashboardPassengerControls: View {
    @ObservedObject var vm: DashboardViewModelRealtime

    var body: some View {
        HStack(spacing: 12) {
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
                    Text("Share this code with your driver")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 12)
            }
        case "boarded":
            statusChip("Boarding confirmed", systemImage: "checkmark.circle.fill", color: .green)
        case "in_progress":
            statusChip("Trip in progress", systemImage: "location.fill", color: .blue)
        case "completed":
            statusChip("Ride completed", systemImage: "checkmark.circle.fill", color: .green)
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
