import SwiftUI

struct DashboardDriverOverlayLayer: View {
    @ObservedObject var vm: DashboardViewModelRealtime

    var body: some View {
        incomingRequests
        activeRide
    }

    @ViewBuilder
    private var incomingRequests: some View {
        let hasActiveRide = vm.rideAccepted || vm.activeRideRow != nil

        if vm.isOnline, !hasActiveRide, vm.incomingRideRequests.isEmpty {
            VStack {
                Spacer()
                DriverWaitingPanel(isRealtimeActive: vm.isRealtimeActive)
                    .padding(.horizontal)
                    .padding(.bottom, 96)
            }
        } else if !hasActiveRide, !vm.incomingRideRequests.isEmpty {
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
        if let active = vm.activeRideRow {
            let status = (active["status"] as? String)?.lowercased() ?? ""
            VStack {
                Spacer()
                if isPassengerCancelledBeforeTrip(active, status: status) || vm.driverFlow == .passengerCancelled {
                    DriverPassengerCancelledPanel(
                        onBackToWaiting: vm.acknowledgePassengerCancellationBeforeTrip
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 80)
                } else if status == "passenger_cancelled_in_trip" || status == "ride_finished" || status == "completed" || vm.driverFlow == .collectPayment {
                    DriverCollectPaymentPanel(
                        active: active,
                        onPaymentCollected: {
                            handlePaymentCollected(active: active)
                        }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 80)
                } else {
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
    }

    private func isPassengerCancelledBeforeTrip(_ active: [String: Any], status: String) -> Bool {
        guard status == "cancelled" else { return false }
        return ((active["cancelled_by"] as? String)?.lowercased() ?? "") == "passenger"
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
                    vm.driverBoardingCodeError = "PIN does not match"
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

    private func handlePaymentCollected(active: [String: Any]) {
        guard let rideId = active["id"] as? String else { return }
        Task {
            let ok = await vm.collectRidePayment(rideId: rideId)
            if !ok {
                SavariLog.debug("payment collection update failed")
            }
        }
    }
}

private struct DriverPassengerCancelledPanel: View {
    let onBackToWaiting: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Passenger cancelled")
                        .font(.system(size: 17, weight: .semibold))
                    Text("This ride is closed. Return to waiting for the next request.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Button(action: onBackToWaiting) {
                Label("Back to waiting", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
        }
        .padding(16)
        .background(Material.ultraThin)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }
}

private struct DriverCollectPaymentPanel: View {
    let active: [String: Any]
    let onPaymentCollected: () -> Void

    private var status: String {
        (active["status"] as? String)?.lowercased() ?? ""
    }

    private var isCancellation: Bool {
        status == "passenger_cancelled_in_trip"
    }

    private var title: String {
        isCancellation ? "Passenger cancelled" : "Ride finished"
    }

    private var subtitle: String {
        isCancellation
            ? "Stop safely and collect the fare."
            : "Collect the fare before returning to waiting."
    }

    private var cancellationDistance: String? {
        guard isCancellation else { return nil }
        guard let meters = doubleValue(active["cancellation_distance_m"]) else { return nil }
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "indianrupeesign.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Amount due")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("₹\(RideRowFormatter.fareString(for: active))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }

                Spacer()

                if let cancellationDistance {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Trip covered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(cancellationDistance)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(12)

            Button(action: onPaymentCollected) {
                Label("Payment collected", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
        }
        .padding(16)
        .background(Material.ultraThin)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
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
                Label("Passenger PIN", systemImage: "number.square.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close PIN entry")
            }

            TextField("Enter passenger PIN", text: $vm.driverBoardingCodeEntry)
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
                    Text(vm.isVerifyingBoardingCode ? "Verifying" : "Verify PIN")
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
