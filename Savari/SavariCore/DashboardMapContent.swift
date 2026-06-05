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
        ForEach(drivers) { driver in
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

        currentUserAnnotation
        assignedDriverAnnotation
        activeDriverPickupAnnotation
    }

    private var isPassenger: Bool {
        role.lowercased().contains("passenger")
    }

    private var isDriver: Bool {
        role.lowercased().contains("driver")
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
                    Text("You")
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
                    Text("You")
                        .font(.caption2)
                        .padding(6)
                        .background(Material.ultraThin)
                        .cornerRadius(6)
                }
                .accessibilityLabel("You")
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
                .accessibilityLabel("Assigned driver")
            }
        }
    }

    @MapContentBuilder
    private var activeDriverPickupAnnotation: some MapContent {
        if isDriver,
           let activeRideRow,
           let pickupLatitude = activeRideRow["pickup_lat"] as? Double,
           let pickupLongitude = activeRideRow["pickup_lon"] as? Double {
            let pickupCoordinate = CLLocationCoordinate2D(latitude: pickupLatitude, longitude: pickupLongitude)
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
}
