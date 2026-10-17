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
    @Published public private(set) var returnMission: DastakV1ReturnMission?
    var trackingID: UUID? { returnMission?.id ?? mission?.id }
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var heartbeatFailure: String?
    private let manager = CLLocationManager()
    private let functions: any FunctionClient
    private let demonstration: Bool
    private let client: SupabaseDastakV1DeliveryClient
    private let heartbeatMonitor: DastakDeliveryHeartbeat
    private var lastUpload: Date?
    private var uploading = false
    private var generation = UUID()
    private var stopped = false
    var actionInFlight = false
    private var refreshing = false
    private var uploadTask: Task<Void, Never>?
#if canImport(UIKit)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
#endif

    public init(functions: any FunctionClient, demonstration: Bool = false) {
        self.demonstration = demonstration
        let bounded = DastakDeliveryFunctionClient(base: functions)
        self.functions = bounded
        client = SupabaseDastakV1DeliveryClient(functions: bounded)
        heartbeatMonitor = DastakDeliveryHeartbeat(functions: bounded)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    public func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        stopped = false
        let revision = generation
        do {
            let snapshot = try await client.snapshot(idempotencyKey: key())
            guard !stopped, revision == generation, !Task.isCancelled else { return }
            adopt(snapshot)
        } catch {
            if trackingID != nil { statusMessage = "Tracking connection interrupted. Retrying automatically." }
        }
    }

    public func heartbeat() async {
        guard !stopped, returnMission == nil, !actionInFlight else { return }
        let revision = generation
        let attempted = await heartbeatMonitor.send(mission)
        guard !stopped, revision == generation else { return }
        heartbeatFailure = heartbeatMonitor.failure
        // Heartbeats advance the server version. Re-read after acknowledgements
        // and stale-version failures rather than retrying an old version forever.
        if attempted { await refresh() }
    }

    func adopt(_ value: DastakV1DeliveryMissionSnapshot?) {
        let value = value?.retainingConfirmedProgress(from: mission)
        if let value, let current = mission, value.id == current.id, value.version < current.version { return }
        if value?.id != mission?.id || value?.status != mission?.status {
            generation = UUID()
            lastUpload = nil
        }
        mission = value
        heartbeatMonitor.reset(for: value?.id)
        heartbeatFailure = heartbeatMonitor.failure
        if value == nil {
            manager.stopUpdatingLocation()
            statusMessage = nil
            return
        }
        updatePermissionAndReporting()
    }

    func adopt(_ snapshot: DastakV1DeliveryDispatchSnapshot) {
        guard snapshot.returnLaneCurrent else {
            // GPS publishes only the normal delivery lane. It can update an
            // existing matching mission, but cannot start one or clear a return.
            if returnMission == nil, let current = mission, snapshot.deliveryLaneCurrent,
               snapshot.currentMission?.id == current.id {
                adopt(snapshot.currentMission)
                return
            }
            statusMessage = "Return assignment could not be checked. Existing tracking is retained."; return
        }
        if let value = snapshot.returnMission {
            if let current = returnMission, current.id == value.id, current.version > value.version { return }
            if returnMission?.id != value.id || returnMission?.status != value.status {
                generation = UUID(); lastUpload = nil
            }
            mission = nil; returnMission = value
            heartbeatMonitor.reset(for: nil); heartbeatFailure = nil
            updatePermissionAndReporting()
        } else if snapshot.deliveryLaneCurrent {
            if returnMission != nil { generation = UUID(); lastUpload = nil; returnMission = nil }
            adopt(snapshot.currentMission)
        }
    }

    public func stop() {
        stopped = true
        generation = UUID()
        mission = nil
        returnMission = nil
        heartbeatFailure = nil
        heartbeatMonitor.reset(for: nil)
        manager.stopUpdatingLocation()
        uploadTask?.cancel()
        endBackgroundUpload()
    }

    private func updatePermissionAndReporting() {
        guard !demonstration else { return }
        guard trackingID != nil, !stopped else { return }
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
        guard !stopped, !actionInFlight, let missionID = trackingID, !uploading,
              let fix = locations.last, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 200,
              abs(fix.timestamp.timeIntervalSinceNow) <= 25,
              lastUpload.map({ Date.now.timeIntervalSince($0) >= 8 }) ?? true else { return }
        uploading = true
        lastUpload = .now
        let revision = generation
        let sample = DastakMissionLocationSample(missionId: missionID,
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
                adopt(snapshot)
            } catch {
                guard !stopped, generation == revision else { return }
                if case FunctionClientError.api(_, let code, _) = error, code == "mission_not_assigned" {
                    returnMission = nil; adopt(nil)
                } else {
                    statusMessage = "Location update delayed. Arrival stays locked until GPS reconnects."
                }
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard trackingID != nil else { return }
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
