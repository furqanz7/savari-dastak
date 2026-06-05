import SwiftUI
import MapKit

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
                rideSummary
                Spacer()
                fareSummary
            }

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
            Text("Pickup")
                .font(.caption2)
            if let pickup = pickupCoordinate {
                Text(String(format: "%.5f, %.5f", pickup.latitude, pickup.longitude))
                    .font(.caption2)
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

    private var driverActions: some View {
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
    }

    private var rideLifecycleActions: some View {
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
