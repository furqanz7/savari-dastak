import SwiftUI

struct RideFlowCard: View {
    let flow: PassengerFlowState
    let vm: DashboardViewModelRealtime
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(Color.white.opacity(0.08))
                )

            content
                .padding(24)
        }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: flow)
    }

    @ViewBuilder
    private var content: some View {
        switch flow {
        case .confirming:
            ConfirmRideSheet(vm: vm, onConfirm: onConfirm)

        case .matching:
            RideStatusCard(
                state: .matching,
                onCancel: onCancel,
                onContact: {}
            )

        case .accepted:
            if let driver = vm.assignedDriver {
                RideStatusCard(
                    state: .accepted(
                        driver: driver,
                        etaSeconds: vm.assignedDriverETASeconds ?? 0
                    ),
                    onCancel: onCancel,
                    onContact: {}
                )
            } else {
                RideStatusCard(
                    state: .matching,
                    onCancel: onCancel,
                    onContact: {}
                )
            }

        default:
            EmptyView()
        }
    }
}
