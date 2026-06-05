import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct MapPickerView: View {
    @Binding var selectedItem: MKMapItem?
    var onPick: (MKMapItem) -> Void

    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var pickedPlacemark: MKPlacemark?
    @State private var distanceMeters: CLLocationDistance?
    @State private var etaSeconds: TimeInterval?
    @State private var showHint = true
    @State private var showTopCloseHint = true
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack(alignment: .top) {
            MapPickerRepresentable(
                pickedCoordinate: $pickedCoordinate,
                pickedPlacemark: $pickedPlacemark,
                onSelectPlacemark: handlePlacemarkSelection,
                onRouteComputed: handleRouteComputed
            )
            .edgesIgnoringSafeArea(.all)

            MapPickerOverlay(
                pickedPlacemark: pickedPlacemark,
                distanceMeters: distanceMeters,
                etaSeconds: etaSeconds,
                showHint: $showHint,
                showTopCloseHint: $showTopCloseHint,
                onDismiss: dismiss,
                onCancelSelection: resetSelection,
                onPick: handlePickedLocation
            )
        }
        .interactiveDismissDisabled(false)
    }

    private func handlePlacemarkSelection(_ placemark: MKPlacemark) {
        pickedPlacemark = placemark
        selectedItem = MKMapItem(placemark: placemark)

        withAnimation(.easeOut(duration: 0.22)) {
            showHint = false
            showTopCloseHint = false
        }
    }

    private func handleRouteComputed(distance: CLLocationDistance?, eta: TimeInterval?) {
        distanceMeters = distance
        etaSeconds = eta
    }

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    private func resetSelection() {
        pickedCoordinate = nil
        pickedPlacemark = nil
        distanceMeters = nil
        etaSeconds = nil
        selectedItem = nil

        withAnimation(.easeInOut) {
            showHint = true
            showTopCloseHint = true
        }
    }

    private func handlePickedLocation(_ placemark: MKPlacemark) {
        onPick(MKMapItem(placemark: placemark))
        presentationMode.wrappedValue.dismiss()
    }
}
