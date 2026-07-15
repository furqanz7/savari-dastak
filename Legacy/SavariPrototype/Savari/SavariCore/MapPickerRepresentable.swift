import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct MapPickerRepresentable: UIViewRepresentable {
    @Binding var pickedCoordinate: CLLocationCoordinate2D?
    @Binding var pickedPlacemark: MKPlacemark?
    var onSelectPlacemark: (MKPlacemark) -> Void
    var onRouteComputed: (CLLocationDistance?, TimeInterval?) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.mapType = .mutedStandard

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        map.addGestureRecognizer(longPress)

        if let userCoordinate = GPSLocationPusher.shared.current {
            map.setRegion(
                MKCoordinateRegion(
                    center: userCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ),
                animated: false
            )
        }

        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let pickedCoordinate {
            context.coordinator.updateSelectionAnnotation(on: uiView, coordinate: pickedCoordinate)
        } else {
            context.coordinator.clearSelectionAnnotation(on: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, onSelectPlacemark: onSelectPlacemark, onRouteComputed: onRouteComputed)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapPickerRepresentable
        weak var selectionAnnotation: MKPointAnnotation?
        var activeDirections: MKDirections?
        var onSelectPlacemark: (MKPlacemark) -> Void
        var onRouteComputed: (CLLocationDistance?, TimeInterval?) -> Void

        init(
            _ parent: MapPickerRepresentable,
            onSelectPlacemark: @escaping (MKPlacemark) -> Void,
            onRouteComputed: @escaping (CLLocationDistance?, TimeInterval?) -> Void
        ) {
            self.parent = parent
            self.onSelectPlacemark = onSelectPlacemark
            self.onRouteComputed = onRouteComputed
            super.init()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else {
                return
            }

            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)

            DispatchQueue.main.async {
                self.parent.pickedCoordinate = coordinate
                self.updateSelectionAnnotation(on: map, coordinate: coordinate)
                self.select(placemark: MKPlacemark(coordinate: coordinate))
            }

            reverseGeocode(coordinate)
            computeRoute(to: coordinate, on: map)
        }

        func updateSelectionAnnotation(on mapView: MKMapView, coordinate: CLLocationCoordinate2D) {
            if let selectionAnnotation {
                selectionAnnotation.coordinate = coordinate
                return
            }

            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            mapView.addAnnotation(annotation)
            selectionAnnotation = annotation
        }

        func clearSelectionAnnotation(on mapView: MKMapView) {
            if let selectionAnnotation {
                mapView.removeAnnotation(selectionAnnotation)
                self.selectionAnnotation = nil
            }
            mapView.removeOverlays(mapView.overlays)
        }

        func computeRoute(to coordinate: CLLocationCoordinate2D, on mapView: MKMapView) {
            activeDirections?.cancel()
            mapView.removeOverlays(mapView.overlays)

            guard let userCoordinate = GPSLocationPusher.shared.current else {
                DispatchQueue.main.async {
                    self.onRouteComputed(nil, nil)
                }
                return
            }

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: userCoordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            request.transportType = .automobile
            request.requestsAlternateRoutes = false

            let directions = MKDirections(request: request)
            activeDirections = directions
            directions.calculate { [weak self] response, _ in
                guard let self else { return }

                guard let route = response?.routes.first else {
                    DispatchQueue.main.async {
                        self.onRouteComputed(nil, nil)
                    }
                    return
                }

                DispatchQueue.main.async {
                    mapView.addOverlay(route.polyline)
                    mapView.setVisibleMapRect(
                        route.polyline.boundingMapRect.insetBy(dx: -2000, dy: -2000),
                        edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 260, right: 40),
                        animated: true
                    )
                    self.onRouteComputed(route.distance, route.expectedTravelTime)
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.95)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            let identifier = "sel"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView.annotation = annotation
            (annotationView as? MKMarkerAnnotationView)?.markerTintColor = UIColor.systemRed
            return annotationView
        }

        private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                guard let self else { return }

                let placemark = placemarks?.first.map(MKPlacemark.init(placemark:))
                    ?? MKPlacemark(coordinate: coordinate)

                DispatchQueue.main.async {
                    self.parent.pickedPlacemark = placemark
                    self.select(placemark: placemark)
                }
            }
        }

        private func select(placemark: MKPlacemark) {
            parent.pickedPlacemark = placemark
            onSelectPlacemark(placemark)
        }
    }
}
