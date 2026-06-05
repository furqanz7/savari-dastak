import Foundation
import CoreLocation
import MapKit

enum RideFormat {
    /// Formats a distance value (in meters) into a user-friendly string.
    /// Matches formatting used in DistanceETABox and MapPickerView.
    static func distance(_ distanceMeters: CLLocationDistance) -> String {
        if distanceMeters < 1000 {
            let meters = Int(round(distanceMeters))
            return "\(meters) m"
        } else {
            let km = distanceMeters / 1000
            if km < 10 {
                return String(format: "%.1f km", km)
            } else {
                return String(format: "%.0f km", km)
            }
        }
    }

    /// Formats an estimated time of arrival (ETA) in seconds into a user-friendly string.
    /// Matches formatting used in DistanceETABox and MapPickerView.
    static func eta(_ etaSeconds: TimeInterval) -> String {
        if etaSeconds < 60 {
            return "1 min"
        } else {
            let minutes = Int(round(etaSeconds / 60))
            return "\(minutes) min"
        }
    }
}

enum MapCameraHelpers {
    /// Returns an MKCoordinateRegion that fits the given coordinates with padding.
    /// - Parameters:
    ///   - coords: The array of CLLocationCoordinate2D points to fit.
    ///   - paddingFactor: Multiplier for padding (e.g. 1.3 for 30% padding).
    /// - Returns: MKCoordinateRegion covering the coordinates with padding, or a default region around (0,0) if coords is empty.
    static func regionFitting(_ coords: [CLLocationCoordinate2D], paddingFactor: Double = 1.3) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            // Return small region around (0,0)
            let center = CLLocationCoordinate2D(latitude: 0, longitude: 0)
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            return MKCoordinateRegion(center: center, span: span)
        }

        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude

        for coord in coords {
            if coord.latitude < minLat { minLat = coord.latitude }
            if coord.latitude > maxLat { maxLat = coord.latitude }
            if coord.longitude < minLon { minLon = coord.longitude }
            if coord.longitude > maxLon { maxLon = coord.longitude }
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2

        // Calculate span with padding
        let latDelta = (maxLat - minLat) * paddingFactor
        let lonDelta = (maxLon - minLon) * paddingFactor

        // Ensure minimum span to avoid too zoomed in region
        let minSpanDelta: CLLocationDegrees = 0.01

        let span = MKCoordinateSpan(
            latitudeDelta: max(latDelta, minSpanDelta),
            longitudeDelta: max(lonDelta, minSpanDelta)
        )

        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        return MKCoordinateRegion(center: center, span: span)
    }
}
