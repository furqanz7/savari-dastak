import SwiftUI

struct DashboardDriverOverlayLayer: View {
    @ObservedObject var vm: DashboardViewModelRealtime

    var body: some View {
        incomingRequests
        activeRide
    }

    @ViewBuilder
    private var incomingRequests: some View {
        if vm.isOnline, !vm.rideAccepted, vm.incomingRideRequests.isEmpty {
            VStack {
                Spacer()
                DriverWaitingPanel(isRealtimeActive: vm.isRealtimeActive)
                    .padding(.horizontal)
                    .padding(.bottom, 96)
            }
        } else if !vm.rideAccepted, !vm.incomingRideRequests.isEmpty {
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
                if vm.driverFlow == .awaitingOTP, let rideId = active["id"] as? String {
                    DriverBoardingCodeEntryPanel(
                        vm: vm,
                        onCancel: {
                            vm.driverFlow = .idle
                            vm.driverBoardingCodeEntry = ""
                            vm.driverBoardingCodeError = nil
                        },
                        onVerify: {
                            handleVerifyCode(rideId: rideId)
                        }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

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
        vm.driverBoardingCodeError = nil
        vm.driverFlow = .awaitingOTP
    }

    private func handleVerifyCode(rideId: String) {
        let code = vm.driverBoardingCodeEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !vm.isVerifyingBoardingCode else { return }

        Task {
            await MainActor.run {
                vm.isVerifyingBoardingCode = true
                vm.driverBoardingCodeError = nil
            }
            let ok = await vm.verifyBoardingCodeAndBoard(rideId: rideId, code: code)
            await MainActor.run {
                vm.isVerifyingBoardingCode = false
                if !ok, vm.driverBoardingCodeError == nil {
                    vm.driverBoardingCodeError = "Code does not match"
                }
            }
        }
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

private struct DriverBoardingCodeEntryPanel: View {
    @ObservedObject var vm: DashboardViewModelRealtime
    let onCancel: () -> Void
    let onVerify: () -> Void

    private var trimmedCode: String {
        vm.driverBoardingCodeEntry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Confirm boarding", systemImage: "number.square.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close code entry")
            }

            TextField("Enter passenger code", text: $vm.driverBoardingCodeEntry)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(12)
                .onChange(of: vm.driverBoardingCodeEntry) { _, value in
                    let filtered = value.filter(\.isNumber)
                    let limited = String(filtered.prefix(6))
                    if limited != value {
                        vm.driverBoardingCodeEntry = limited
                    }
                }

            if let error = vm.driverBoardingCodeError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button(action: onVerify) {
                HStack {
                    if vm.isVerifyingBoardingCode {
                        ProgressView()
                    }
                    Text(vm.isVerifyingBoardingCode ? "Verifying" : "Verify code")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .disabled(trimmedCode.count < 4 || vm.isVerifyingBoardingCode)
            .opacity(trimmedCode.count >= 4 && !vm.isVerifyingBoardingCode ? 1 : 0.45)
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
        }
        .padding(14)
        .background(Material.ultraThin)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }
}
