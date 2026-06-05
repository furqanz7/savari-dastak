import SwiftUI
@preconcurrency import Foundation
import MapKit
import Combine
import Supabase
import CoreLocation
import Realtime


final class GPSLocationPusher: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GPSLocationPusher()
    private let lm = CLLocationManager()
    private var lastPublished: Date? = nil
    private var publishInterval: TimeInterval = 2.0 // seconds
    @Published var current: CLLocationCoordinate2D? = nil

    private override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.distanceFilter = 2
    }

    func start() {
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
    }

    func stop() { lm.stopUpdatingLocation() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        DispatchQueue.main.async { self.current = coord
            SavariSessionStore.setLastCoordinate(coord)
        }

        let now = Date()
        if let last = lastPublished, now.timeIntervalSince(last) < publishInterval { return }
        lastPublished = now

        Task { await publishCoordinateIfDriver(coord) }
    }

    private func publishCoordinateIfDriver(_ coord: CLLocationCoordinate2D) async {
        guard let role = SavariSessionStore.lastRole,
              role.lowercased().contains("driver") else { return }
        guard let driverId = SavariSessionStore.authToken else { return }
        await RideService.shared.upsertDriverLocation(driverId: driverId, lat: coord.latitude, lon: coord.longitude)
    }
}
