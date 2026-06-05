import SwiftUI
import CoreLocation
import UIKit

struct DistanceETABox: View {
    let distanceMeters: CLLocationDistance?
    let etaSeconds: TimeInterval?
    var onUse: () -> Void

    @State private var pressed = false

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                if let distanceMeters {
                    Text(RideFormat.distance(distanceMeters))
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Text("—")
                        .font(.system(size: 16, weight: .semibold))
                }

                if let etaSeconds, etaSeconds > 0 {
                    Text("~\(Int(etaSeconds / 60)) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 4)

            Spacer()

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onUse()
            }) {
                HStack(spacing: 10) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .buttonStyle(LiquidGlassButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            pressed
                            ? Color.white.opacity(0.22)
                            : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        .scaleEffect(pressed ? 0.985 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: pressed)
        .onLongPressGesture(minimumDuration: 0.01, pressing: { isPressing in
            pressed = isPressing
        }, perform: {})
        .padding(.horizontal)
    }
}

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

struct TransportCard: View {
    let title: String
    let fare: Double?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                if let fare {
                    Text("₹\(Int(fare))")
                        .font(.system(size: 20, weight: .bold))
                } else {
                    Text("—")
                        .font(.headline)
                }
            }
            .frame(width: 144, height: 96)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            isSelected
                            ? LinearGradient(colors: [Color.primary.opacity(0.96), Color.primary.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(.secondarySystemBackground), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                        .blendMode(.overlay)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.12) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 18 : 12, x: 0, y: isSelected ? 10 : 8)
            .shadow(color: Color.white.opacity(0.06), radius: 1, x: 0, y: 1)
            .foregroundColor(
                isSelected
                ? Color(UIColor.systemBackground)
                : Color.primary.opacity(0.92)
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSelected)
        }
        .buttonStyle(LiquidGlassButtonStyle())
    }
}

struct RideStatusCard: View {
    enum RideStatus {
        case matching
        case accepted(driver: Driver, etaSeconds: Int)
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

            case .accepted(let driver, let eta):
                acceptedContent(driver: driver, eta: eta)
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

    private func acceptedContent(driver: Driver, eta: Int) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)

                Text("Driver found")
                    .font(.system(size: 17, weight: .semibold))

                Text(driver.name)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Divider().opacity(0.4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ETA")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("~\(eta / 60) min")
                        .font(.system(size: 16, weight: .semibold))
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
