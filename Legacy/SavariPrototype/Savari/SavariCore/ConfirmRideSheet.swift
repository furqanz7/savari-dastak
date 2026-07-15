import SwiftUI
import UIKit

struct ConfirmRideSheet: View {
    @ObservedObject var vm: DashboardViewModelRealtime
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("Choose your ride")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 4)

            HStack(spacing: 12) {
                TransportCard(
                    title: "Auto",
                    fare: vm.fareAuto,
                    isSelected: vm.chosenTransportOption == "Auto"
                ) {
                    vm.chosenTransportOption = "Auto"
                    vm.selectedRide.amount = vm.fareAuto ?? vm.selectedRide.amount
                }

                TransportCard(
                    title: "Bike",
                    fare: vm.fareBike,
                    isSelected: vm.chosenTransportOption == "Bike"
                ) {
                    vm.chosenTransportOption = "Bike"
                    vm.selectedRide.amount = vm.fareBike ?? vm.selectedRide.amount
                }
            }
            .padding(.top, 4)

            if vm.selectedRide.amount > 0 {
                Text("₹\(Int(vm.selectedRide.amount))")
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.top, 4)
            }

            HStack(spacing: 12) {
                if let distanceMeters = vm.selectedRide.distanceMeters {
                    Text(String(format: "%.1f km", distanceMeters / 1000))
                }
                if vm.selectedRide.etaSeconds > 0 {
                    Text("~\(vm.selectedRide.etaSeconds / 60)m")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            let canConfirm = vm.chosenTransportOption != nil && vm.selectedRide.amount > 0

            Button(action: {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onConfirm()
            }) {
                Text("Confirm Ride")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                    .foregroundColor(Color(UIColor.systemBackground))
            }
            .disabled(!canConfirm)
            .opacity(canConfirm ? 1 : 0.4)
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
