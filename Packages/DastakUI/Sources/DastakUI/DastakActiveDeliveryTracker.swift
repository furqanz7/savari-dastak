import CoreLocation
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Owned by the authenticated Customer/Partner root, not a tab or delivery card.
/// Only an assigned active mission enables continuous/background location.
@MainActor
public final class DastakActiveDeliveryTracker: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published public private(set) var mission: DastakV1DeliveryMissionSnapshot?
    @Published public private(set) var statusMessage: String?
    private let manager = CLLocationManager()
    private let functions: any FunctionClient
    private let client: SupabaseDastakV1DeliveryClient
    private var lastUpload: Date?
    private var uploading = false
    private var generation = UUID()
    private var stopped = false
    private var uploadTask: Task<Void, Never>?
#if canImport(UIKit)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
#endif

    public init(functions: any FunctionClient) {
        self.functions = functions
        client = SupabaseDastakV1DeliveryClient(functions: functions)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    public func refresh() async {
        stopped = false
        let revision = generation
        do {
            let snapshot = try await client.snapshot(idempotencyKey: key())
            guard !stopped, revision == generation, !Task.isCancelled else { return }
            adopt(snapshot.currentMission)
        } catch {
            if mission != nil { statusMessage = "Tracking connection interrupted. Retrying automatically." }
        }
    }

    func adopt(_ value: DastakV1DeliveryMissionSnapshot?) {
        if let value, let current = mission, value.id == current.id, value.version < current.version { return }
        if value?.id != mission?.id || value?.status != mission?.status {
            generation = UUID()
            lastUpload = nil
        }
        mission = value
        if value == nil {
            manager.stopUpdatingLocation()
            statusMessage = nil
            return
        }
        updatePermissionAndReporting()
    }

    public func stop() {
        stopped = true
        generation = UUID()
        mission = nil
        manager.stopUpdatingLocation()
        uploadTask?.cancel()
        endBackgroundUpload()
    }

    private func updatePermissionAndReporting() {
        guard mission != nil, !stopped else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            statusMessage = "Allow precise location to track this delivery and confirm arrival."
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            statusMessage = "Location is off. Enable Precise Location in Settings to confirm arrival."
        case .authorizedAlways, .authorizedWhenInUse:
#if os(iOS)
            // This capability is present only in Dastak (the Customer/Partner binary).
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
#endif
            statusMessage = manager.accuracyAuthorization == .reducedAccuracy
                ? "Precise Location is off. Enable it in Settings to confirm arrival." : nil
            manager.startUpdatingLocation()
        @unknown default:
            statusMessage = "Location permission is unavailable."
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updatePermissionAndReporting()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !stopped, let mission, !uploading,
              let fix = locations.last, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 200,
              abs(fix.timestamp.timeIntervalSinceNow) <= 25,
              lastUpload.map({ Date.now.timeIntervalSince($0) >= 8 }) ?? true else { return }
        uploading = true
        lastUpload = .now
        let revision = generation
        let sample = DastakMissionLocationSample(missionId: mission.id,
            latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
            accuracyMeters: fix.horizontalAccuracy, recordedAt: fix.timestamp)
        // CLLocation wakes this process in the background. Give the single
        // authenticated upload bounded completion time, never an endless task.
#if canImport(UIKit)
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Delivery location") { [weak self] in
            Task { @MainActor in
                self?.uploadTask?.cancel()
                self?.endBackgroundUpload()
            }
        }
#endif
        uploadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                uploading = false
                endBackgroundUpload()
            }
            do {
                let snapshot: DastakV1DeliveryDispatchSnapshot = try await functions.invoke(
                    "courier-dispatch", request: sample, idempotencyKey: key())
                guard !stopped, generation == revision else { return }
                adopt(snapshot.currentMission)
            } catch {
                guard !stopped, generation == revision else { return }
                if case FunctionClientError.api(_, let code, _) = error, code == "mission_not_assigned" {
                    adopt(nil)
                } else {
                    statusMessage = "Location update delayed. Arrival stays locked until GPS reconnects."
                }
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard mission != nil else { return }
        statusMessage = "Waiting for a fresh GPS location. Check Location Services."
    }

    private func endBackgroundUpload() {
#if canImport(UIKit)
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
#endif
    }

    private func key() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString.lowercased())! }
}
