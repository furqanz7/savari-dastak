import CoreLocation
import Foundation
import MapKit
import MarketplaceFoundation

public struct DastakDeliveryLocation: Codable, Equatable, Sendable, Identifiable {
    public let addressID: UUID?
    public let addressVersion: String?
    public let address: String
    public let point: GeoPoint
    public let label: String?
    public let details: String?
    public let building: String?
    public let floor: String?
    public let landmark: String?
    public let deliveryNotes: String?

    public init(
        addressID: UUID? = nil,
        addressVersion: String? = nil,
        address: String,
        point: GeoPoint,
        label: String? = nil,
        details: String? = nil,
        building: String? = nil,
        floor: String? = nil,
        landmark: String? = nil,
        deliveryNotes: String? = nil
    ) {
        self.addressID = addressID
        self.addressVersion = addressVersion
        self.address = address
        self.point = point
        self.label = Self.cleaned(label)
        self.details = Self.cleaned(details)
        self.building = Self.cleaned(building) ?? Self.cleaned(details)?.components(separatedBy: " • ").first
        self.floor = Self.cleaned(floor)
        self.landmark = Self.cleaned(landmark)
        self.deliveryNotes = Self.cleaned(deliveryNotes)
    }

    public var displayName: String {
        label ?? "Delivery address"
    }

    public var id: String {
        addressID?.uuidString ?? "\(point.latitude),\(point.longitude)|\(label ?? "")|\(address)"
    }

    public var displayAddress: String {
        [building, floor, landmark, address]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    public var isReadyForDelivery: Bool {
        label != nil && building != nil
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class DastakLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: DastakDeliveryLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private var requestRevision = UUID()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        // An explicit request must not reuse a previous GPS fix or its error.
        requestRevision = UUID()
        location = nil
        errorMessage = nil
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
            let revision = UUID()
            requestRevision = revision
            let point = GeoPoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let address = await reverseGeocode(locations.last) ?? "Current location"
            guard requestRevision == revision else { return }
            location = DastakDeliveryLocation(address: address, point: point)
            errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            requestRevision = UUID()
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
        didSet {
            cancelResolution()
            suggestions = []
            errorMessage = nil
            completionTask?.cancel()
            completer.cancel()
            let fragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
            isSearching = !fragment.isEmpty
            guard !fragment.isEmpty else { return }
            completionTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == fragment else { return }
                completer.queryFragment = fragment
            }
        }
    }
    @Published private(set) var suggestions: [DastakPlaceSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isResolving = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var completionTask: Task<Void, Never>?
    private var resolution: MKLocalSearch?
    private var resolutionID = UUID()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let fragment = completer.queryFragment
        let results = completer.results.prefix(12).map {
            DastakPlaceSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in
            guard !query.isEmpty, query.trimmingCharacters(in: .whitespacesAndNewlines) == fragment else { return }
            suggestions = results
            isSearching = false
            errorMessage = nil
        }
    }

    nonisolated func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        let fragment = completer.queryFragment
        Task { @MainActor in
            guard !query.isEmpty, query.trimmingCharacters(in: .whitespacesAndNewlines) == fragment else { return }
            isSearching = false
            errorMessage = "Address search is unavailable right now."
        }
    }

    func resolve(_ suggestion: DastakPlaceSuggestion) async -> DastakDeliveryLocation? {
        cancelResolution()
        let token = resolutionID
        isResolving = true
        defer { if token == resolutionID { isResolving = false } }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = [suggestion.title, suggestion.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let operation = MKLocalSearch(request: request)
            resolution = operation
            guard let item = try await operation.start().mapItems.first else {
                throw DastakPlaceSearchError.noResult
            }
            guard !Task.isCancelled, token == resolutionID else { return nil }
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
            guard !Task.isCancelled, token == resolutionID else { return nil }
            errorMessage = "That address could not be resolved."
            return nil
        }
    }

    func cancelResolution() {
        resolutionID = UUID()
        resolution?.cancel()
        resolution = nil
        isResolving = false
    }
}

private enum DastakPlaceSearchError: Error {
    case noResult
}
