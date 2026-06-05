import SwiftUI
import Foundation
import MapKit

struct DriverActiveRidePanel: View {
    let active: [String: Any]
    let boardingCodeVerified: Bool
    let onArrive: (String) -> Void
    let onEnterCode: () -> Void
    let onStartRide: (String) -> Void
    let onEndRide: (String) -> Void
    @ObservedObject private var locationPusher = GPSLocationPusher.shared

    private let arrivalThresholdMeters: CLLocationDistance = 100

    private var rideId: String? {
        active["id"] as? String
    }

    private var status: String {
        active["status"] as? String ?? "—"
    }

    private var normalizedStatus: String {
        status.lowercased()
    }

    private var canShowRideControls: Bool {
        boardingCodeVerified || normalizedStatus == "boarded" || normalizedStatus == "in_progress"
    }

    private var isPickupLeg: Bool {
        normalizedStatus != "boarded" &&
        normalizedStatus != "in_progress" &&
        normalizedStatus != "completed"
    }

    private var navigationTarget: DriverNavigationTarget? {
        if isPickupLeg {
            return pickupCoordinate.map { DriverNavigationTarget(kind: .pickup, coordinate: $0) }
        }
        return dropoffCoordinate.map { DriverNavigationTarget(kind: .dropoff, coordinate: $0) }
    }

    private var currentTargetDistance: CLLocationDistance? {
        guard let current = locationPusher.current,
              let target = navigationTarget?.coordinate else { return nil }
        return distanceMetersBetween(current, target)
    }

    private var isAtPickup: Bool {
        guard let current = locationPusher.current,
              let pickup = pickupCoordinate else { return false }
        return distanceMetersBetween(current, pickup) <= arrivalThresholdMeters
    }

    private var canArrive: Bool {
        isAtPickup &&
        (
            normalizedStatus == "assigned" ||
            normalizedStatus == "accepted" ||
            normalizedStatus == "driver_en_route"
        )
    }

    private var canEnterCode: Bool {
        normalizedStatus == "arrived" || normalizedStatus == "boarded"
    }

    private var canStartRide: Bool {
        (boardingCodeVerified || normalizedStatus == "boarded") &&
        normalizedStatus != "in_progress" &&
        normalizedStatus != "completed"
    }

    private var canEndRide: Bool {
        normalizedStatus == "in_progress"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                rideSummary
                Spacer()
                fareSummary
            }

            targetSummary
            driverActions

            if canShowRideControls {
                rideLifecycleActions
            }
        }
        .padding()
        .background(Material.ultraThin)
        .cornerRadius(16)
    }

    private var rideSummary: some View {
        VStack(alignment: .leading) {
            Text("Ride: \(rideId ?? "—")")
                .font(.headline)
            if let passengerId = active["passenger_id"] as? String {
                Text("Passenger: \(String(passengerId.prefix(6)))")
                    .font(.caption)
            }
        }
    }

    private var fareSummary: some View {
        VStack(alignment: .trailing) {
            Text("Fare ₹\(RideRowFormatter.fareString(for: active))")
                .bold()
            Text("Status: \(status)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var targetSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(navigationTarget?.title ?? "Navigation target unavailable")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let distance = currentTargetDistance {
                    Text("\(formatDistance(distance)) away")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if locationPusher.current == nil {
                    Text("Waiting for current driver location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Ride location is missing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isPickupLeg {
                Text(arrivalHint)
                    .font(.caption2)
                    .foregroundColor(canArrive ? .green : .secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }

    private var driverActions: some View {
        HStack(spacing: 12) {
            Button(action: openNavigationTargetInMaps) {
                actionLabel("Navigate", systemImage: "map")
            }
                .disabled(navigationTarget == nil)
                .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))

            Button("Arrive") {
                if let rideId {
                    onArrive(rideId)
                }
            }
            .disabled(!canArrive)
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))

            Button(action: onEnterCode) {
                actionLabel("Code", systemImage: "number")
            }
                .disabled(!canEnterCode)
                .buttonStyle(LiquidGlassButtonStyle())
        }
    }

    private var rideLifecycleActions: some View {
        HStack(spacing: 12) {
            Button {
                if let rideId {
                    onStartRide(rideId)
                }
            } label: {
                actionLabel("Start", systemImage: "play.fill")
            }
            .disabled(!canStartRide)
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))

            Button {
                if let rideId {
                    onEndRide(rideId)
                }
            } label: {
                actionLabel("Complete", systemImage: "checkmark")
            }
            .disabled(!canEndRide)
            .buttonStyle(LiquidGlassButtonStyle())
        }
    }

    private var pickupCoordinate: CLLocationCoordinate2D? {
        guard let latitude = coordinateValue(for: "pickup_lat"),
              let longitude = coordinateValue(for: "pickup_lon") else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var dropoffCoordinate: CLLocationCoordinate2D? {
        guard let latitude = coordinateValue(for: "drop_lat"),
              let longitude = coordinateValue(for: "drop_lon") else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var arrivalHint: String {
        guard pickupCoordinate != nil else { return "Pickup unavailable" }
        guard locationPusher.current != nil else { return "GPS required" }
        guard let distance = currentTargetDistance else { return "Distance unavailable" }
        if canArrive { return "Ready to arrive" }
        return "Needs \(formatDistance(arrivalThresholdMeters)); now \(formatDistance(distance))"
    }

    private func coordinateValue(for key: String) -> Double? {
        if let value = active[key] as? Double { return value }
        if let value = active[key] as? Int { return Double(value) }
        if let value = active[key] as? NSNumber { return value.doubleValue }
        if let value = active[key] as? String { return Double(value) }
        return nil
    }

    private func openNavigationTargetInMaps() {
        guard let navigationTarget else { return }
        let placemark = MKPlacemark(coordinate: navigationTarget.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = navigationTarget.title
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
    }
}

private struct DriverNavigationTarget {
    enum Kind {
        case pickup
        case dropoff
    }

    let kind: Kind
    let coordinate: CLLocationCoordinate2D

    var title: String {
        switch kind {
        case .pickup:
            return "Pickup"
        case .dropoff:
            return "Drop-off"
        }
    }

}
