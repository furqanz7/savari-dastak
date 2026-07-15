import SwiftUI

struct DashboardPassengerRideOverlayLayer: View {
    @ObservedObject var vm: DashboardViewModelRealtime
    let onUsePreview: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        previewOverlay
        rideFlowOverlay
    }

    @ViewBuilder
    private var previewOverlay: some View {
        if vm.passengerFlow == .preview {
            VStack {
                Spacer()
                DistanceETABox(
                    distanceMeters: vm.selectedRide.distanceMeters,
                    etaSeconds: TimeInterval(vm.selectedRide.etaSeconds),
                    onUse: onUsePreview
                )
                .padding(.bottom, 28)
            }
            .zIndex(7)
        }
    }

    @ViewBuilder
    private var rideFlowOverlay: some View {
        if vm.passengerFlow == .confirming
            || vm.passengerFlow == .matching
            || vm.passengerFlow == .accepted {
            VStack {
                Spacer()
                RideFlowCard(
                    flow: vm.passengerFlow,
                    vm: vm,
                    onConfirm: onConfirm,
                    onCancel: onCancel
                )
                .frame(maxHeight: vm.passengerFlow == .confirming ? 360 : 220)
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .zIndex(6)
        }
    }
}
