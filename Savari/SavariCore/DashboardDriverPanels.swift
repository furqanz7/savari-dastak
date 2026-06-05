import SwiftUI
import MapKit

struct DriverControls: View {
    let isOnline: Bool
    let activeDriverCount: Int
    let onGoOnline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onGoOnline) {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text(isOnline ? "Online" : "Go Online")
                }
            }
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
            .frame(maxWidth: 220)
            .disabled(isOnline)

            Spacer().frame(width: 8)

            VStack(alignment: .trailing) {
                Text("Active drivers: \(activeDriverCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DriverIncomingRequestsPanel: View {
    let requests: [[String: Any]]
    let onAccept: ([String: Any]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ride requests", systemImage: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(requests.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
            }

            ForEach(Array(requests.prefix(3).enumerated()), id: \.offset) { _, ride in
                DriverIncomingRequestRow(ride: ride) {
                    onAccept(ride)
                }
            }
        }
        .padding(14)
        .background(Material.ultraThin)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }
}

private struct DriverIncomingRequestRow: View {
    let ride: [String: Any]
    let onAccept: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ride \(RideRowFormatter.shortId(ride))")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(RideRowFormatter.distanceString(for: ride)) • \(RideRowFormatter.vehicleType(for: ride))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("₹\(RideRowFormatter.fareString(for: ride))")
                .font(.system(size: 14, weight: .semibold))

            Button("Accept", action: onAccept)
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
        }
        .padding(10)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(12)
    }
}

struct DriverActiveRidePanel: View {
    let active: [String: Any]
    let boardingCodeVerified: Bool
    let onArrive: (String) -> Void
    let onEnterCode: () -> Void
    let onStartRide: (String) -> Void
    let onEndRide: (String) -> Void

    private var rideId: String? {
        active["id"] as? String
    }

    private var status: String {
        active["status"] as? String ?? "—"
    }

    private var canShowRideControls: Bool {
        boardingCodeVerified || status == "boarded" || status == "in_progress"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Ride: \(rideId ?? "—")")
                        .font(.headline)
                    if let passengerId = active["passenger_id"] as? String {
                        Text("Passenger: \(String(passengerId.prefix(6)))")
                            .font(.caption)
                    }
                    Text("Pickup")
                        .font(.caption2)
                    if let pickup = pickupCoordinate {
                        Text(String(format: "%.5f, %.5f", pickup.latitude, pickup.longitude))
                            .font(.caption2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Fare ₹\(RideRowFormatter.fareString(for: active))")
                        .bold()
                    Text("Status: \(status)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Navigate", action: openPickupInMaps)
                    .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))

                Button("Arrive") {
                    if let rideId {
                        onArrive(rideId)
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))

                Button("Enter Code", action: onEnterCode)
                    .buttonStyle(LiquidGlassButtonStyle())
            }

            if canShowRideControls {
                HStack(spacing: 12) {
                    Button("Start Ride") {
                        if let rideId {
                            onStartRide(rideId)
                        }
                    }
                    .disabled(status == "in_progress")
                    .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))

                    Button("End Ride & Unlock Fare") {
                        if let rideId {
                            onEndRide(rideId)
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle())
                }
            }
        }
        .padding()
        .background(Material.ultraThin)
        .cornerRadius(16)
    }

    private var pickupCoordinate: CLLocationCoordinate2D? {
        guard
            let latitude = active["pickup_lat"] as? Double,
            let longitude = active["pickup_lon"] as? Double
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func openPickupInMaps() {
        guard let pickupCoordinate else { return }
        let placemark = MKPlacemark(coordinate: pickupCoordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Pickup"
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

enum RideRowFormatter {
    static func fareString(for ride: [String: Any]) -> String {
        if let estimatedFare = doubleValue(ride["estimated_fare"]) {
            return String(format: "%.2f", estimatedFare)
        }
        if let fare = doubleValue(ride["fare"]) {
            return String(format: "%.2f", fare)
        }
        return String(format: "%.2f", 0.0)
    }

    static func shortId(_ ride: [String: Any]) -> String {
        guard let id = ride["id"] as? String, !id.isEmpty else { return "NEW" }
        return String(id.prefix(8)).uppercased()
    }

    static func vehicleType(for ride: [String: Any]) -> String {
        (ride["vehicle_type"] as? String) ?? "Ride"
    }

    static func distanceString(for ride: [String: Any]) -> String {
        guard let meters = doubleValue(ride["estimated_distance_meters"]), meters > 0 else {
            return "Distance pending"
        }
        return String(format: "%.1f km", meters / 1000.0)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
