import SwiftUI

struct DashboardPassengerControls: View {
    @ObservedObject var vm: DashboardViewModelRealtime

    var body: some View {
        HStack(spacing: 12) {
            if vm.rideAccepted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Driver on the way", systemImage: "location")
                    if let eta = vm.assignedDriverETASeconds {
                        Text("Driver ETA \(eta / 60)m")
                    }
                }
                .padding(10)
                .background(Material.ultraThin)
                .cornerRadius(12)
            }

            if let code = vm.activeRideRow?["boarding_code"] as? String {
                VStack {
                    BoardingCodeView(
                        code: code,
                        ttlSeconds: vm.activeRideRow?["boarding_code_ttl"] as? Int
                    )

                    Button("I've boarded") {}
                        .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                }
                .padding(.top, 12)
            }
        }
    }
}
