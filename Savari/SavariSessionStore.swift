import Foundation
import CoreLocation

enum SavariDefaultsKey {
    static let authToken = "authToken"
    static let lastRole = "lastRole"
    static let isOnboardingComplete = "isOnboardingComplete"
    static let lastLatitude = "lastLat"
    static let lastLongitude = "lastLon"
}

enum SavariSessionStore {
    private static var defaults: UserDefaults { .standard }

    static var authToken: String? {
        defaults.string(forKey: SavariDefaultsKey.authToken)
    }

    static var lastRole: String? {
        defaults.string(forKey: SavariDefaultsKey.lastRole)
    }

    static var isOnboardingComplete: Bool {
        defaults.bool(forKey: SavariDefaultsKey.isOnboardingComplete)
    }

    static var lastCoordinate: CLLocationCoordinate2D? {
        let latitude = defaults.double(forKey: SavariDefaultsKey.lastLatitude)
        let longitude = defaults.double(forKey: SavariDefaultsKey.lastLongitude)
        guard latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func setLoggedIn(userId: String, role: String) {
        defaults.set(userId, forKey: SavariDefaultsKey.authToken)
        defaults.set(role, forKey: SavariDefaultsKey.lastRole)
        defaults.set(true, forKey: SavariDefaultsKey.isOnboardingComplete)
    }

    static func setLastRole(_ role: String?) {
        if let role {
            defaults.set(role, forKey: SavariDefaultsKey.lastRole)
        } else {
            defaults.removeObject(forKey: SavariDefaultsKey.lastRole)
        }
    }

    static func setOnboardingComplete(_ isComplete: Bool) {
        defaults.set(isComplete, forKey: SavariDefaultsKey.isOnboardingComplete)
    }

    static func setLastCoordinate(_ coordinate: CLLocationCoordinate2D) {
        defaults.set(coordinate.latitude, forKey: SavariDefaultsKey.lastLatitude)
        defaults.set(coordinate.longitude, forKey: SavariDefaultsKey.lastLongitude)
    }

    static func clearLastCoordinate() {
        defaults.removeObject(forKey: SavariDefaultsKey.lastLatitude)
        defaults.removeObject(forKey: SavariDefaultsKey.lastLongitude)
    }
}
