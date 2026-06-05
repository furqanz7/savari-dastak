import SwiftUI
import MapKit
@preconcurrency import Foundation
import CoreLocation
import Combine

final class LocationCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct CompletionItem: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let subtitle: String
        let mapItem: MKMapItem?      // present for fallback results
        let completion: MKLocalSearchCompletion? // present for genuine completions
    }

    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var completions: [CompletionItem] = []
    private let completer = MKLocalSearchCompleter()
    private var cancellables = Set<AnyCancellable>()

    /// Optional region to bias results
    var region: MKCoordinateRegion? {
        didSet {
            if let r = region { completer.region = r }
        }
    }

    private let querySubject = PassthroughSubject<String, Never>()

    // optional direct MKLocalSearch fallback per query (helps when completer errors)
    private let useDirectSearchFallback = true
    private var directSearchCancellable: AnyCancellable?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        if #available(iOS 16.0, *) {
            completer.pointOfInterestFilter = .some(.includingAll)
        }

        // Debounce user input before feeding to MKLocalSearchCompleter
        querySubject
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(220), scheduler: RunLoop.main)
            .sink { [weak self] fragment in
                guard let self = self else { return }
                if fragment.isEmpty {
                    self.suggestions = []
                    self.completions = []
                    self.completer.queryFragment = ""
                } else {
                    self.completer.queryFragment = fragment
                }
            }
            .store(in: &cancellables)

        completer.queryFragment = ""
    }

    func update(query: String) {
        querySubject.send(query)

        // optional direct MKLocalSearch fallback (debounced)
        guard useDirectSearchFallback else { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        directSearchCancellable?.cancel()
        directSearchCancellable = Just(q)
            .delay(for: .milliseconds(160), scheduler: RunLoop.main)
            .sink { [weak self] str in
                guard let self = self, !str.isEmpty else { return }
                self.runDirectSearch(query: str)
            }
    }

    // direct MKLocalSearch to produce immediate mapItems (fallback)
    private func runDirectSearch(query: String) {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        if let r = region {
            req.region = r
        } else {
            // fallback region — use a reasonable city-size span
            req.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
                                            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25))
        }
        let search = MKLocalSearch(request: req)
        search.start { [weak self] resp, err in
            guard let self = self else { return }
            if let err = err {
                print("[LocationCompleter][DirectSearch] error:", err.localizedDescription)
                return
            }
            guard let mapItems = resp?.mapItems, !mapItems.isEmpty else {
                // no direct results
                return
            }
            DispatchQueue.main.async {
                // map MKMapItems to CompletionItem (no MKLocalSearchCompletion here)
                self.completions = mapItems.prefix(12).map {
                    CompletionItem(title: $0.name ?? ($0.placemark.title ?? "Unknown"),
                                   subtitle: $0.placemark.title ?? "",
                                   mapItem: $0,
                                   completion: nil)
                }
                print("[LocationCompleter][DirectSearch] found \(mapItems.count) items for '\(query)'")
            }
        }
    }

    // MARK: - MKLocalSearchCompleterDelegate
    func completer(_ completer: MKLocalSearchCompleter, didUpdateResults results: [MKLocalSearchCompletion]) {
        DispatchQueue.main.async {
            self.suggestions = results
            let mapped = results.map { comp in
                CompletionItem(title: comp.title, subtitle: comp.subtitle, mapItem: nil, completion: comp)
            }
            // prefer real completions when available
            self.completions = mapped
            print("[LocationCompleter] got \(results.count) suggestions for '\(completer.queryFragment)'")
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let ns = error as NSError
        print("[LocationCompleter] didFailWithError domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
        DispatchQueue.main.async { self.suggestions = []; self.completions = [] }

        // Determine a reasonable region without comparing MKCoordinateRegion directly
        let fallbackRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
        let region: MKCoordinateRegion = {
            let c = completer.region
            // Use the completer's region if it appears valid (non-zero span)
            if c.span.latitudeDelta != 0 && c.span.longitudeDelta != 0 { return c }
            if let r = self.region { return r }
            return fallbackRegion
        }()

        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = completer.queryFragment.isEmpty ? "Point of Interest" : completer.queryFragment
        req.region = region
        let search = MKLocalSearch(request: req)
        search.start { resp, err in
            if let err = err {
                print("[LocationCompleter] fallback MKLocalSearch error:", err.localizedDescription)
                return
            }
            guard let mapItems = resp?.mapItems, !mapItems.isEmpty else { return }
            DispatchQueue.main.async {
                let fallback = mapItems.prefix(10).map { mi in
                    CompletionItem(title: mi.name ?? (mi.placemark.title ?? "Unknown"),
                                   subtitle: mi.placemark.title ?? "",
                                   mapItem: mi,
                                   completion: nil)
                }
                self.completions = fallback
                print("[LocationCompleter] fallback found \(mapItems.count) items")
            }
        }
    }
}

struct MapPickerView: View {
    @Binding var selectedItem: MKMapItem?
    var onPick: (MKMapItem) -> Void

    @State private var pickedCoordinate: CLLocationCoordinate2D? = nil
    @State private var pickedPlacemark: MKPlacemark? = nil
    @State private var distanceMeters: CLLocationDistance? = nil
    @State private var etaSeconds: TimeInterval? = nil

    // hints / overlays
    @State private var showHint: Bool = true               // "Long-press to pick..." (visible until first pick)
    @State private var showTopCloseHint: Bool = true       // "Tap here to close" (top area)
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack(alignment: .top) {
            // Map (your MapRepresentable should call onSelectPlacemark when user long-presses)
            MapRepresentable(
                pickedCoordinate: $pickedCoordinate,
                pickedPlacemark: $pickedPlacemark,
                onSelectPlacemark: { placemark in
                    // set the picked placemark & binding; this signals a real long-press selection
                    pickedPlacemark = placemark
                    selectedItem = MKMapItem(placemark: placemark)
                    
                    // hide the "long-press" hint and top close hint once user selects
                    withAnimation(.easeOut(duration: 0.22)) {
                        showHint = false
                        showTopCloseHint = false
                    }
                },
                onRouteComputed: { distance, eta in
                    // route results only after pick
                    distanceMeters = distance
                    etaSeconds = eta
                }
            )
            .edgesIgnoringSafeArea(.all)
            
            // --- GLOBAL TOP TAP + HINT (visible until dismissed/first pick) ---
            VStack(spacing: 0) {
                // invisible tappable area
                Color.clear
                    .frame(height: 120)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // tapping the top area dismisses the whole picker
                        withAnimation(.easeOut(duration: 0.22)) { showTopCloseHint = false }
                        dismiss()
                    }
                
                Spacer()
            }
            .allowsHitTesting(showTopCloseHint) // only intercept taps if hint is showing
            
            if showTopCloseHint {
                VStack {
                    Text("Tap here/Drag down to close")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 6)
                        .padding(.top, 18)
                        .onTapGesture {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            withAnimation(.easeOut(duration: 0.2)) { showTopCloseHint = false }
                            dismiss()
                        }
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Floating "long-press" hint (appears until first selection)
            if showHint {
                VStack {
                    Spacer()
                    Text("Long-press to pick a location")
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 6)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) { showHint = false }
                        }
                        .padding(.bottom, 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Bottom panel: only shown AFTER user long-press picked a placemark
            if let placemark = pickedPlacemark {
                VStack(spacing: 14) {
                    
                    // --- Drag Handle ---
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                    
                    // --- Location Info ---
                    VStack(alignment: .leading, spacing: 6) {
                        Text(placemark.name ?? "Selected location")
                            .font(.system(size: 18, weight: .semibold))
                        
                        if let title = placemark.title, title != placemark.name {
                            Text(title)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    
                    // --- Distance + ETA Row ---
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let d = distanceMeters {
                                Text(RideFormat.distance(d))
                                    .font(.system(size: 15, weight: .medium))
                            } else {
                                Text("Distance —")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            
                            if let eta = etaSeconds {
                                Text("ETA \(RideFormat.eta(eta))")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("ETA —")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // --- Actions ---
                        HStack(spacing: 10) {
                            Button("Cancel") {
                                clearSelection()
                                withAnimation(.easeInOut) {
                                    showHint = true
                                    showTopCloseHint = true
                                }
                            }
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(20)
                            
                            Button {
                                let mi = MKMapItem(placemark: placemark)
                                onPick(mi)
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                Text("Use Location")
                                    .font(.system(size: 15, weight: .semibold))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                            }
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.9))
                            )
                            .foregroundColor(.black)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(
                    ZStack {
                        // Base blur
                        RoundedRectangle(cornerRadius: 22)
                            .fill(.ultraThinMaterial)
                        
                        // Inner highlight stroke (glass edge)
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
                .padding(.horizontal, 14)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: - Helpers

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    private func clearSelection() {
        pickedCoordinate = nil
        pickedPlacemark = nil
        distanceMeters = nil
        etaSeconds = nil
        selectedItem = nil
    }
}

// MARK: - MapRepresentable (UIViewRepresentable using MKMapView & long-press)
private struct MapRepresentable: UIViewRepresentable {
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

        // long press recognizer
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        long.minimumPressDuration = 0.35
        map.addGestureRecognizer(long)

        // initial camera if user's last known location exists (optional)
        if let user = GPSLocationPusher.shared.current {
            map.setRegion(MKCoordinateRegion(center: user, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)), animated: false)
        }

        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // update annotation if selection changed from SwiftUI side
        if let coord = pickedCoordinate {
            // ensure there's exactly one selection annotation
            if context.coordinator.selectionAnnotation == nil {
                let ann = MKPointAnnotation()
                ann.coordinate = coord
                uiView.addAnnotation(ann)
                context.coordinator.selectionAnnotation = ann
            } else {
                context.coordinator.selectionAnnotation?.coordinate = coord
            }
        } else {
            if let ann = context.coordinator.selectionAnnotation {
                uiView.removeAnnotation(ann)
                context.coordinator.selectionAnnotation = nil
            }
            // remove overlays (route)
            uiView.removeOverlays(uiView.overlays)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, onSelectPlacemark: onSelectPlacemark, onRouteComputed: onRouteComputed)
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapRepresentable
        weak var selectionAnnotation: MKPointAnnotation?
        var activeDirections: MKDirections? = nil
        var onSelectPlacemark: (MKPlacemark) -> Void
        var onRouteComputed: (CLLocationDistance?, TimeInterval?) -> Void

        init(_ parent: MapRepresentable, onSelectPlacemark: @escaping (MKPlacemark) -> Void, onRouteComputed: @escaping (CLLocationDistance?, TimeInterval?) -> Void) {
            self.parent = parent
            self.onSelectPlacemark = onSelectPlacemark
            self.onRouteComputed = onRouteComputed
            super.init()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            if gesture.state == .began {
                let point = gesture.location(in: map)
                let coord = map.convert(point, toCoordinateFrom: map)

                // drop pin
                DispatchQueue.main.async {
                    self.parent.pickedCoordinate = coord
                }

                // add/replace annotation
                DispatchQueue.main.async {
                    if let ann = self.selectionAnnotation {
                        ann.coordinate = coord
                    } else {
                        let ann = MKPointAnnotation()
                        ann.coordinate = coord
                        map.addAnnotation(ann)
                        self.selectionAnnotation = ann
                    }
                }

                // Immediately signal selection with a raw coordinate placemark
                let immediatePlacemark = MKPlacemark(coordinate: coord)
                DispatchQueue.main.async {
                    self.parent.pickedPlacemark = immediatePlacemark
                    self.onSelectPlacemark(immediatePlacemark)
                }

                // reverse geocode to get placemark/title
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let geo = CLGeocoder()
                geo.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
                    guard let self = self else { return }
                    if let pm = placemarks?.first {
                        let mkpm = MKPlacemark(placemark: pm)
                        DispatchQueue.main.async {
                            self.parent.pickedPlacemark = mkpm
                            self.onSelectPlacemark(mkpm)
                        }
                    } else {
                        // fallback to raw placemark
                        let mkpm = MKPlacemark(coordinate: coord)
                        DispatchQueue.main.async {
                            self.parent.pickedPlacemark = mkpm
                            self.onSelectPlacemark(mkpm)
                        }
                    }
                }

                // compute route from user's current location (if available)
                computeRoute(to: coord, on: map)
            }
        }

        func computeRoute(to coordinate: CLLocationCoordinate2D, on mapView: MKMapView) {
            // cancel previous directions
            activeDirections?.cancel()
            mapView.removeOverlays(mapView.overlays)

            // source — user's current location (if available), else no route
            guard let userCoord = GPSLocationPusher.shared.current else {
                DispatchQueue.main.async { self.onRouteComputed(nil, nil) }
                return
            }

            let srcPlacemark = MKPlacemark(coordinate: userCoord)
            let dstPlacemark = MKPlacemark(coordinate: coordinate)
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: srcPlacemark)
            request.destination = MKMapItem(placemark: dstPlacemark)
            request.transportType = .automobile
            request.requestsAlternateRoutes = false

            let directions = MKDirections(request: request)
            self.activeDirections = directions
            directions.calculate { [weak self] resp, error in
                guard let self = self else { return }
                if let route = resp?.routes.first {
                    DispatchQueue.main.async {
                        // add polyline overlay
                        mapView.addOverlay(route.polyline)
                        // zoom to fit
                        mapView.setVisibleMapRect(route.polyline.boundingMapRect.insetBy(dx: -2000, dy: -2000), edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 260, right: 40), animated: true)

                        // update states: distance & eta
                        self.onRouteComputed(route.distance, route.expectedTravelTime)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.onRouteComputed(nil, nil)
                    }
                }
            }
        }

        // MARK: - MKMapViewDelegate for overlay rendering
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = UIColor.systemBlue.withAlphaComponent(0.95)
                r.lineWidth = 6
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // custom annotation view style (optional) — default pin is OK too
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "sel"
            var av = mapView.dequeueReusableAnnotationView(withIdentifier: id)
            if av == nil {
                av = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            }
            av?.annotation = annotation
            (av as? MKMarkerAnnotationView)?.markerTintColor = UIColor.systemRed
            return av
        }
    }
}

