import SwiftUI
import MapKit
import CoreLocation
import Combine

struct DashboardMapLayer: View {
    let role: String
    @ObservedObject var vm: DashboardViewModelRealtime
    @Binding var mapPosition: MapCameraPosition
    @Binding var didCenterToUser: Bool
    @Binding var isTrackingUser: Bool
    let pickupCoordinate: CLLocationCoordinate2D?
    let destCoordinate: CLLocationCoordinate2D?

    var body: some View {
        Map(position: $mapPosition) {
            DashboardMapContent(
                role: role,
                drivers: vm.drivers,
                selectedRide: vm.selectedRide,
                assignedDriver: vm.assignedDriver,
                activeRideRow: vm.activeRideRow,
                pickupCoordinate: pickupCoordinate,
                destCoordinate: destCoordinate,
                showRouteOverlay: true,
                onDriverTap: centerMap(on:)
            )
        }
        .ignoresSafeArea()
        .onReceive(GPSLocationPusher.shared.$current.compactMap { $0 }) { coordinate in
            if isTrackingUser || !didCenterToUser {
                centerMap(on: coordinate)
                didCenterToUser = true
            }
        }
        .onChange(of: vm.passengerFlow) { _, flow in
            guard flow == .accepted, let driver = vm.assignedDriver else {
                return
            }

            focusAcceptedPassengerRide(on: driver)
        }
        .onChange(of: vm.assignedDriver) { _, driver in
            guard vm.passengerFlow == .accepted, let driver else {
                return
            }

            focusAcceptedPassengerRide(on: driver)
        }
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }
    }

    private func focusAcceptedPassengerRide(on driver: Driver) {
        let region: MKCoordinateRegion
        if let pickupCoordinate {
            region = regionFitting([pickupCoordinate, driver.coordinate])
        } else {
            region = MKCoordinateRegion(
                center: driver.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        withAnimation(.easeInOut(duration: 0.6)) {
            mapPosition = .region(region)
        }
    }

    private func regionFitting(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return MKCoordinateRegion(
                center: coordinates.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLatitude - minLatitude) * 1.8),
            longitudeDelta: max(0.01, (maxLongitude - minLongitude) * 1.8)
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}
