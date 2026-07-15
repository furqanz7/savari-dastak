import SwiftUI
import MapKit

extension View {
    func dashboardSessionLifecycle(
        vm: DashboardViewModelRealtime,
        mapPosition: Binding<MapCameraPosition>,
        didCenterToUser: Binding<Bool>
    ) -> some View {
        modifier(
            DashboardSessionLifecycle(
                vm: vm,
                mapPosition: mapPosition,
                didCenterToUser: didCenterToUser
            )
        )
    }
}

private struct DashboardSessionLifecycle: ViewModifier {
    @ObservedObject var vm: DashboardViewModelRealtime
    @Binding var mapPosition: MapCameraPosition
    @Binding var didCenterToUser: Bool

    func body(content: Content) -> some View {
        content
            .onAppear(perform: startSession)
            .onDisappear {
                vm.stopAll()
            }
    }

    private func startSession() {
        GPSLocationPusher.shared.start()
        Task {
            await vm.start()
        }

        if let lastCoordinate = SavariSessionStore.lastCoordinate {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: lastCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        } else {
            mapPosition = .automatic
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !didCenterToUser, let first = vm.drivers.first else { return }

            mapPosition = .region(
                MKCoordinateRegion(
                    center: first.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                )
            )
        }
    }
}
