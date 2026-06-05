import SwiftUI

struct DashboardDriverOverlayLayer: View {
    @ObservedObject var vm: DashboardViewModelRealtime

    var body: some View {
        incomingRequests
        activeRide
    }

    @ViewBuilder
    private var incomingRequests: some View {
        if !vm.rideAccepted, !vm.incomingRideRequests.isEmpty {
            VStack {
                Spacer()
                DriverIncomingRequestsPanel(
                    requests: vm.incomingRideRequests,
                    onAccept: vm.acceptIncomingRide
                )
                .padding(.horizontal)
                .padding(.bottom, 96)
            }
        }
    }

    @ViewBuilder
    private var activeRide: some View {
        if vm.rideAccepted, let active = vm.activeRideRow {
            VStack {
                Spacer()
                DriverActiveRidePanel(
                    active: active,
                    boardingCodeVerified: vm.boardingCodeVerified,
                    onArrive: handleArrive,
                    onEnterCode: handleEnterCode,
                    onStartRide: handleStartRide,
                    onEndRide: handleEndRide
                )
                .padding(.bottom, 80)
                .padding(.horizontal)
            }
        }
    }

    private func handleArrive(rideId: String) {
        guard let driverId = SavariSessionStore.authToken else { return }
        Task {
            let ok = await vm.driverArrived(rideId: rideId, driverId: driverId)
            if !ok {
                SavariLog.debug("arrive failed")
            }
        }
    }

    private func handleEnterCode() {
        vm.driverBoardingCodeEntry = ""
        vm.driverFlow = .awaitingOTP
    }

    private func handleStartRide(rideId: String) {
        Task {
            let ok = await vm.startRideNow(rideId: rideId)
            if !ok {
                SavariLog.debug("start failed")
            }
        }
    }

    private func handleEndRide(rideId: String) {
        Task {
            let ok = await vm.endRideNow(rideId: rideId)
            if !ok {
                SavariLog.debug("end failed")
            }
        }
    }
}
