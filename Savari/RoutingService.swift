// RoutingService.swift
import Foundation
import MapKit
import CoreLocation

actor RoutingService {
    static let shared = RoutingService()
    
    struct RouteResult {
        let polyline: MKPolyline
        let coordinates: [CLLocationCoordinate2D]
        let distanceMeters: CLLocationDistance
        let expectedTravelTime: TimeInterval
    }
    
    enum RoutingError: Error {
        case noRouteFound
        case directionsFailed(Error)
    }
    
    /// Calculate driving route between two coords (uses MapKit).
    func calculateRoute(from: CLLocationCoordinate2D,
                        to: CLLocationCoordinate2D,
                        transportType: MKDirectionsTransportType = .automobile) async throws -> RouteResult
    {
        let sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: from))
        let destItem = MKMapItem(placemark: MKPlacemark(coordinate: to))
        
        let request = MKDirections.Request()
        request.source = sourceItem
        request.destination = destItem
        request.transportType = transportType
        request.requestsAlternateRoutes = false
        
        let directions = MKDirections(request: request)
        
        return try await withCheckedThrowingContinuation { cont in
            directions.calculate { response, error in
                if let err = error {
                    cont.resume(throwing: RoutingError.directionsFailed(err))
                    return
                }
                guard let route = response?.routes.first else {
                    cont.resume(throwing: RoutingError.noRouteFound)
                    return
                }
                
                let poly = route.polyline
                var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: poly.pointCount)
                poly.getCoordinates(&coords, range: NSRange(location: 0, length: poly.pointCount))
                
                let result = RouteResult(polyline: poly,
                                         coordinates: coords,
                                         distanceMeters: route.distance,
                                         expectedTravelTime: route.expectedTravelTime)
                cont.resume(returning: result)
            }
        }
    }
    /// Static ETA helper — does not require await
        static func etaDate(from travelTime: TimeInterval) -> Date {
            Date().addingTimeInterval(travelTime)
        }

    }   // <-- closes actor RoutingService
