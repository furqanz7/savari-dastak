import SwiftUI
@preconcurrency import Foundation
import MapKit
import Combine
import Supabase
import CoreLocation
import Realtime


struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    init<T: Encodable & Sendable>(_ value: T) {
        // Capture encode in a @Sendable closure to avoid main-actor isolation complaints.
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - Helpers
nonisolated func distanceMetersBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
    CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
}
nonisolated func secondsFromMeters(_ meters: CLLocationDistance, avgSpeedMetersPerSec: Double = 8.0) -> Int {
    // default average driver speed ~ 8 m/s (~28.8 km/h) adjust per city
    Int(max(30, meters / avgSpeedMetersPerSec))
}

// MARK: - Models
final class Ride: ObservableObject, Identifiable {
    @Published var id = UUID()
    @Published var orderID: String
    @Published var amount: Double
    @Published var etaSeconds: Int
    @Published var etaDate: Date? // new: absolute ETA
    @Published var distanceMeters: Double? // new
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    let role: String

    init(orderID: String = "TEMP", amount: Double = 120.0, etaSeconds: Int = 300, role: String = "Passenger") {
        self.orderID = orderID
        self.amount = amount
        self.etaSeconds = etaSeconds
        self.role = role
    }

    var etaFormatted: String {
        let m = etaSeconds / 60
        let s = etaSeconds % 60
        return String(format: "%d:%02d min", m, s)
    }

    func tick() { if etaSeconds > 0 { etaSeconds -= 1 } }
}

// Driver model (manual Equatable/Hashable because CLLocationCoordinate2D isn't Hashable)
struct Driver: Identifiable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String
    var color: Color
}

extension Driver: Equatable {
    static func == (lhs: Driver, rhs: Driver) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

extension Driver: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

// Simple route helper
struct Route {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    var steps: [CLLocationCoordinate2D] {
        let count = 50
        let latStep = (end.latitude - start.latitude) / Double(count)
        let lonStep = (end.longitude - start.longitude) / Double(count)
        let lat = stride(from: start.latitude, through: end.latitude, by: latStep)
        let lon = stride(from: start.longitude, through: end.longitude, by: lonStep)
        return Array(zip(lat, lon)).map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
    }
}

public extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
