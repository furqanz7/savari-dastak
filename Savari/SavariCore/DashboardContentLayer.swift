import SwiftUI
import MapKit
import CoreLocation

struct DashboardContentLayer: View {
    let role: String
    @ObservedObject var vm: DashboardViewModelRealtime
    @Binding var mapPosition: MapCameraPosition
    @Binding var didCenterToUser: Bool
    @Binding var isTrackingUser: Bool
    let pickupCoordinate: CLLocationCoordinate2D?
    let destCoordinate: CLLocationCoordinate2D?
    let showingInlineSearch: Bool
    let onUsePreview: () -> Void
    let onConfirmPassengerRide: () -> Void
    let onCancelPassengerRideRequest: () -> Void
    let onDismissInlineSearch: () -> Void
    let onGoOnline: () -> Void

    var body: some View {
        ZStack {
            DashboardMapLayer(
                role: role,
                vm: vm,
                mapPosition: $mapPosition,
                didCenterToUser: $didCenterToUser,
                isTrackingUser: $isTrackingUser,
                pickupCoordinate: pickupCoordinate,
                destCoordinate: destCoordinate
            )

            DashboardPassengerRideOverlayLayer(
                vm: vm,
                onUsePreview: onUsePreview,
                onConfirm: onConfirmPassengerRide,
                onCancel: onCancelPassengerRideRequest
            )

            DashboardInlineSearchDismissLayer(
                isPresented: vm.passengerFlow == .searching && showingInlineSearch,
                onDismiss: onDismissInlineSearch
            )

            DashboardManualDragLayer(isTrackingUser: $isTrackingUser)

            DashboardBottomControlsLayer(
                isPassenger: isPassenger,
                vm: vm,
                onCancelPassengerRideRequest: onCancelPassengerRideRequest,
                onGoOnline: onGoOnline
            )

            if isDriver {
                DashboardDriverOverlayLayer(vm: vm)
            }
        }
    }

    private var isPassenger: Bool {
        role.lowercased().contains("passenger")
    }

    private var isDriver: Bool {
        role.lowercased().contains("driver")
    }
}
