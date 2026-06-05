import Foundation
import CoreLocation
import Supabase

extension DashboardViewModelRealtime {
    func goOnline(driverId: String) {
        Task {
            let alreadyOnline = markOnlineIfNeeded()
            if alreadyOnline {
                SavariLog.debug("[VM] already online; ignoring goOnline")
                return
            }

            SavariLog.debug("[VM] goOnline called for driverId:", driverId)
            SavariSessionStore.setLoggedIn(userId: driverId, role: "driver")

            resetDriverRequestSubscription()

            rideRequestsCancel = await RealtimeManager.shared.subscribeRideRequests { [weak self] payload in
                self?.handleRideRequestPayload(payload, driverId: driverId)
            }

            await fetchRequestedRideBacklog(driverId: driverId)
            await MainActor.run { self.isRealtimeActive = true }
            await publishCurrentDriverLocation(driverId: driverId)

            driverPublishTask?.cancel()
        }
    }

    func stopOnline() {
        SavariLog.debug("[VM] stopOnline called")
        rideRequestsCancel?()
        rideRequestsCancel = nil
        incomingRideRequests.removeAll()
        isOnline = false

        driverPublishTask?.cancel()
        driverPublishTask = nil

        SavariSessionStore.setLastRole(nil)

        Task { @MainActor in
            self.isRealtimeActive = false
        }
    }

    @MainActor
    private func markOnlineIfNeeded() -> Bool {
        if isOnline {
            return true
        }
        isOnline = true
        return false
    }

    private func resetDriverRequestSubscription() {
        driverPublishTask?.cancel()
        driverPublishTask = nil
        rideRequestsCancel?()
        rideRequestsCancel = nil
    }

    nonisolated private func handleRideRequestPayload(_ payload: [String: Any], driverId: String) {
        guard let new = payload["new"] as? [String: Any] else {
            return
        }

        SavariLog.debug("[VM][DEBUG] ride payload new:", new)
        let status = (new["status"] as? String) ?? ""

        if status == "requested" {
            if uuidStringsMatch(new["passenger_id"] as? String, driverId) {
                return
            }
            Task { @MainActor in
                self.addIncomingRideIfNeeded(new)
            }
            return
        }

        guard let rideId = new["id"] as? String else {
            return
        }

        Task { @MainActor in
            self.removeIncomingRideIfNeeded(rideId: rideId)
            if status == "assigned",
               let assignedId = new["assigned_driver_id"] as? String,
               uuidStringsMatch(assignedId, SavariSessionStore.authToken) {
                Task { await self.loadActiveRideRowIfNeeded(rideId: rideId) }
            }
        }
    }

    @MainActor
    private func addIncomingRideIfNeeded(_ row: [String: Any]) {
        guard let rideId = row["id"] as? String else {
            return
        }
        if incomingRideRequests.firstIndex(where: { ($0["id"] as? String) == rideId }) == nil {
            incomingRideRequests.append(row)
        }
    }

    @MainActor
    private func removeIncomingRideIfNeeded(rideId: String) {
        if let index = incomingRideRequests.firstIndex(where: { ($0["id"] as? String) == rideId }) {
            incomingRideRequests.remove(at: index)
        }
    }

    private func fetchRequestedRideBacklog(driverId: String) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("rides")
                .select()
                .eq("status", value: "requested")
                .execute()

            if let rows = jsonArray(from: response.data) {
                await MainActor.run {
                    for row in rows {
                        if uuidStringsMatch(row["passenger_id"] as? String, driverId) {
                            continue
                        }
                        addIncomingRideIfNeeded(row)
                    }
                }
            }
        } catch {
            SavariLog.debug("[VM] initial fetch requested rides failed:", error)
        }
    }

    private func publishCurrentDriverLocation(driverId: String) async {
        guard let coordinate = GPSLocationPusher.shared.current else {
            SavariLog.debug("[VM] GPSLocationPusher.current is nil at goOnline")
            return
        }

        SavariLog.debug("[VM] immediate upsert coord:", coordinate)
        await RideService.shared.upsertDriverLocation(
            driverId: driverId,
            lat: coordinate.latitude,
            lon: coordinate.longitude
        )
    }
}
