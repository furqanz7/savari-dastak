import SwiftUI
import MapKit
import CoreLocation

struct DashboardMapContent: MapContent {
    let role: String
    let drivers: [Driver]
    let selectedRide: Ride
    let assignedDriver: Driver?
    let activeRideRow: [String: Any]?
    let pickupCoordinate: CLLocationCoordinate2D?
    let destCoordinate: CLLocationCoordinate2D?
    let showRouteOverlay: Bool
    let onDriverTap: (CLLocationCoordinate2D) -> Void

    var body: some MapContent {
        ForEach(visibleDriverMarkers) { driver in
            Annotation("", coordinate: driver.coordinate) {
                DriverAnnotationView(driver: driver)
                    .accessibilityLabel(driver.name)
                    .onTapGesture {
                        onDriverTap(driver.coordinate)
                    }
            }
        }

        if showRouteOverlay && !selectedRide.routeCoordinates.isEmpty {
            MapPolyline(coordinates: selectedRide.routeCoordinates)
                .stroke(Color.blue, lineWidth: 4)
        }

        if isPassenger {
            passengerPickupAnnotation
            passengerDestinationAnnotation
        }

        if shouldShowCurrentUserAnnotation {
            currentUserAnnotation
        }
        assignedDriverAnnotation
        activeDriverPickupAnnotation
        activeDriverDropoffAnnotation
    }

    private var isPassenger: Bool {
        role.lowercased().contains("passenger")
    }

    private var isDriver: Bool {
        role.lowercased().contains("driver")
    }

    private var visibleDriverMarkers: [Driver] {
        if isDriver {
            return []
        }

        if isPassenger {
            return []
        }

        return drivers
    }

    private var shouldShowCurrentUserAnnotation: Bool {
        if isPassenger, pickupCoordinate != nil {
            return false
        }

        return true
    }

    @MapContentBuilder
    private var passengerPickupAnnotation: some MapContent {
        if let pickupCoordinate {
            Annotation("", coordinate: pickupCoordinate) {
                VStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .resizable()
                        .frame(width: 18, height: 18)
                        .foregroundColor(.blue)
                    Text("Pickup")
                        .font(.caption2)
                        .padding(6)
                        .background(Material.ultraThin)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Pickup")
            }
        }
    }

    @MapContentBuilder
    private var passengerDestinationAnnotation: some MapContent {
        if let destCoordinate {
            Annotation("", coordinate: destCoordinate) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 34, height: 34)
                            .shadow(radius: 3)
                        Image(systemName: "mappin")
                            .foregroundColor(.white)
                    }
                    Text("Destination")
                        .font(.caption2)
                        .padding(6)
                        .background(Material.ultraThin)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Destination")
            }
        }
    }

    @MapContentBuilder
    private var currentUserAnnotation: some MapContent {
        if let userCoordinate = GPSLocationPusher.shared.current {
            Annotation("", coordinate: userCoordinate) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .shadow(radius: 6)
                        Circle()
                            .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                            .frame(width: 48, height: 48)
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text("Current location")
                        .font(.caption2)
                        .padding(6)
                        .background(Material.ultraThin)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Current location")
            }
        }
    }

    @MapContentBuilder
    private var assignedDriverAnnotation: some MapContent {
        if let assignedDriver, isPassenger {
            Annotation("", coordinate: assignedDriver.coordinate) {
                VStack {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 48, height: 48)
                            .shadow(radius: 3)
                        Image(systemName: "car.fill")
                            .foregroundColor(.white)
                    }
                    Text("Driver")
                        .font(.caption2)
                        .padding(6)
                        .background(Material.ultraThin)
                        .cornerRadius(6)
                }
                .fixedSize()
                .accessibilityLabel("Driver location")
            }
        }
    }

    @MapContentBuilder
    private var activeDriverPickupAnnotation: some MapContent {
        if isDriver,
           let activeRideRow,
           let pickupCoordinate = coordinate(
            from: activeRideRow,
            latitudeKeys: ["pickup_lat"],
            longitudeKeys: ["pickup_lon"]
           ) {
            Annotation("", coordinate: pickupCoordinate) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 34, height: 34)
                            .shadow(radius: 3)
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                    }
                    Text("Pickup")
                        .font(.caption2)
                        .padding(6)
                        .background(Material.ultraThin)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Pickup")
            }
        }
    }

    @MapContentBuilder
    private var activeDriverDropoffAnnotation: some MapContent {
        if isDriver,
           let activeRideRow,
           let dropoffCoordinate = coordinate(
            from: activeRideRow,
            latitudeKeys: ["drop_lat", "dest_lat"],
            longitudeKeys: ["drop_lon", "dest_lon"]
           ) {
            Annotation("", coordinate: dropoffCoordinate) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 34, height: 34)
                            .shadow(radius: 3)
                        Image(systemName: "mappin")
                            .foregroundColor(.white)
                    }
                    Text("Drop-off")
                        .font(.caption2)
                        .padding(6)
                        .background(Material.ultraThin)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Drop-off")
            }
        }
    }

    private func coordinate(
        from row: [String: Any],
        latitudeKeys: [String],
        longitudeKeys: [String]
    ) -> CLLocationCoordinate2D? {
        guard let latitude = firstCoordinateValue(in: row, keys: latitudeKeys),
              let longitude = firstCoordinateValue(in: row, keys: longitudeKeys) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func firstCoordinateValue(in row: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = row[key] as? Double {
                return value
            }
            if let value = row[key] as? Int {
                return Double(value)
            }
            if let value = row[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = row[key] as? String {
                return Double(value)
            }
        }
        return nil
    }
}
