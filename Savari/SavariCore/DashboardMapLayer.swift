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

            withAnimation(.easeInOut(duration: 0.6)) {
                mapPosition = .region(
                    MKCoordinateRegion(
                        center: driver.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                )
            }
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
}
