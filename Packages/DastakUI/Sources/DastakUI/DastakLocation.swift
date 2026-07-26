import CoreLocation
import Foundation
import MapKit
import MarketplaceFoundation

public struct DastakDeliveryLocation: Equatable, Sendable {
    public let address: String
    public let point: GeoPoint

    public init(address: String, point: GeoPoint) {
        self.address = address
        self.point = point
    }
}

@MainActor
final class DastakLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: DastakDeliveryLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #else
            manager.requestAlwaysAuthorization()
            #endif
        } else if Self.isAuthorized(status) {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            errorMessage = "Location access is off. Search for a delivery address instead."
        } else {
            errorMessage = "Location is unavailable."
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if Self.isAuthorized(status) {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            let point = GeoPoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let address = await reverseGeocode(locations.last) ?? "Current location"
            location = DastakDeliveryLocation(address: address, point: point)
            errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = "Current location could not be found. Search for an address instead."
        }
    }

    private func reverseGeocode(_ location: CLLocation?) async -> String? {
        guard let location else { return nil }
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        return [
            placemark.name,
            placemark.locality,
            placemark.administrativeArea
        ]
        .compactMap { $0 }
        .uniqued()
        .joined(separator: ", ")
    }

    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(iOS)
        status == .authorizedAlways || status == .authorizedWhenInUse
        #else
        status == .authorizedAlways
        #endif
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct DastakPlaceSuggestion: Identifiable, Sendable {
    let title: String
    let subtitle: String
    var id: String { "\(title)|\(subtitle)" }
}

@MainActor
final class DastakPlaceSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var suggestions: [DastakPlaceSuggestion] = []
    @Published private(set) var isResolving = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.prefix(12).map {
            DastakPlaceSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in
            suggestions = results
        }
    }

    nonisolated func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            errorMessage = "Address search is unavailable right now."
        }
    }

    func resolve(_ suggestion: DastakPlaceSuggestion) async -> DastakDeliveryLocation? {
        isResolving = true
        defer { isResolving = false }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = [suggestion.title, suggestion.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            guard let item = try await MKLocalSearch(request: request).start().mapItems.first else {
                throw DastakPlaceSearchError.noResult
            }
            let coordinate = item.placemark.coordinate
            errorMessage = nil
            return DastakDeliveryLocation(
                address: [item.name, item.placemark.locality, item.placemark.administrativeArea]
                    .compactMap { $0 }
                    .uniqued()
                    .joined(separator: ", "),
                point: GeoPoint(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            )
        } catch {
            errorMessage = "That address could not be resolved."
            return nil
        }
    }
}

private enum DastakPlaceSearchError: Error {
    case noResult
}
