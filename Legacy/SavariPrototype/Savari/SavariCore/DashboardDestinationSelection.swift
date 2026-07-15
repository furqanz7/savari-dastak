import Foundation
import CoreLocation
import MapKit

struct DashboardDestinationRoute {
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: CLLocationDistance
    let etaSeconds: Int
    let etaDate: Date
}

struct DashboardDestinationSelection {
    let mapItem: MKMapItem
    let destinationText: String
    let destinationCoordinate: CLLocationCoordinate2D
    let pickupCoordinate: CLLocationCoordinate2D?
    let route: DashboardDestinationRoute?
    let mapRegion: MKCoordinateRegion
}

enum DashboardDestinationSelectionResolver {
    static func resolve(
        item: LocationCompleter.CompletionItem,
        searchRegion: MKCoordinateRegion?,
        pickup: CLLocationCoordinate2D?
    ) async -> DashboardDestinationSelection? {
        guard let mapItem = await resolveMapItem(item: item, searchRegion: searchRegion) else {
            SavariLog.debug("[Inline] couldn't resolve mapItem for selection")
            return nil
        }

        let destination = mapItem.placemark.coordinate
        let fallbackRegion = MKCoordinateRegion(
            center: destination,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )

        guard let pickup else {
            return DashboardDestinationSelection(
                mapItem: mapItem,
                destinationText: destinationName(for: mapItem),
                destinationCoordinate: destination,
                pickupCoordinate: nil,
                route: nil,
                mapRegion: fallbackRegion
            )
        }

        do {
            let routeResult = try await RoutingService.shared.calculateRoute(from: pickup, to: destination)
            let route = DashboardDestinationRoute(
                coordinates: routeResult.coordinates,
                distanceMeters: routeResult.distanceMeters,
                etaSeconds: Int(routeResult.expectedTravelTime),
                etaDate: RoutingService.etaDate(from: routeResult.expectedTravelTime)
            )

            return DashboardDestinationSelection(
                mapItem: mapItem,
                destinationText: destinationName(for: mapItem),
                destinationCoordinate: destination,
                pickupCoordinate: pickup,
                route: route,
                mapRegion: MapCameraHelpers.regionFitting([pickup, destination])
            )
        } catch {
            SavariLog.debug("[Inline] routing failed:", error.localizedDescription)
            return DashboardDestinationSelection(
                mapItem: mapItem,
                destinationText: destinationName(for: mapItem),
                destinationCoordinate: destination,
                pickupCoordinate: pickup,
                route: nil,
                mapRegion: fallbackRegion
            )
        }
    }

    private static func resolveMapItem(
        item: LocationCompleter.CompletionItem,
        searchRegion: MKCoordinateRegion?
    ) async -> MKMapItem? {
        if let mapItem = item.mapItem {
            return mapItem
        }

        if let completion = item.completion {
            let request = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: request)
            do {
                return try await search.start().mapItems.first
            } catch {
                SavariLog.debug("[Inline] completion -> search.start error:", error.localizedDescription)
            }
        }

        let query = "\(item.title) \(item.subtitle)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let searchRegion {
            request.region = searchRegion
        }

        return try? await MKLocalSearch(request: request).start().mapItems.first
    }

    private static func destinationName(for mapItem: MKMapItem) -> String {
        mapItem.name ?? mapItem.placemark.title ?? ""
    }
}
