import Foundation
import CoreLocation
import Supabase

private let driverIdleOfflineLimitNanoseconds: UInt64 = 15 * 60 * 1_000_000_000

extension DashboardViewModelRealtime {
    func goOnline(driverId: String) {
        Task {
            let alreadyOnline = await MainActor.run {
                self.markOnlineIfNeeded()
            }
            if alreadyOnline {
                SavariLog.debug("[VM] already online; refreshing ride request feed")
                await fetchRequestedRideBacklog(driverId: driverId)
                await MainActor.run {
                    self.startDriverRequestBacklogPolling(driverId: driverId)
                    self.startDriverIdleOfflineCountdownIfNeeded()
                }
                return
            }

            SavariLog.debug("[VM] goOnline called for driverId:", driverId)
            SavariSessionStore.setLoggedIn(userId: driverId, role: "driver")

            resetDriverRequestSubscription()

            rideRequestsCancel = await RealtimeManager.shared.subscribeRideRequests { [weak self] payload in
                self?.handleRideRequestPayload(payload, driverId: driverId)
            }

            await MainActor.run {
                self.isRealtimeActive = true
                self.startDriverIdleOfflineCountdownIfNeeded()
            }
            await fetchRequestedRideBacklog(driverId: driverId)
            await MainActor.run {
                self.startDriverRequestBacklogPolling(driverId: driverId)
            }
            await publishCurrentDriverLocation(driverId: driverId)

            driverPublishTask?.cancel()
        }
    }

    @MainActor
    func stopOnline() {
        SavariLog.debug("[VM] stopOnline called")
        rideRequestsCancel?()
        rideRequestsCancel = nil
        incomingRideRequests.removeAll()
        isOnline = false
        driverIdleOfflineTask?.cancel()
        driverIdleOfflineTask = nil
        driverRequestBacklogPollingTask?.cancel()
        driverRequestBacklogPollingTask = nil
        driverActiveRidePollingTask?.cancel()
        driverActiveRidePollingTask = nil

        driverPublishTask?.cancel()
        driverPublishTask = nil

        SavariSessionStore.setLastRole(nil)

        isRealtimeActive = false
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
        driverRequestBacklogPollingTask?.cancel()
        driverRequestBacklogPollingTask = nil
        driverActiveRidePollingTask?.cancel()
        driverActiveRidePollingTask = nil
        rideRequestsCancel?()
        rideRequestsCancel = nil
    }

    nonisolated private func handleRideRequestPayload(_ payload: [String: Any], driverId: String) {
        if payload["new"] == nil,
           let old = payload["old"] as? [String: Any],
           let oldRideId = old["id"] as? String {
            Task { @MainActor in
                self.removeIncomingRideIfNeeded(rideId: oldRideId)
                let assignedId = (old["assigned_driver_id"] as? String) ?? (old["driver_id"] as? String)
                let oldStatus = (old["status"] as? String) ?? ""
                if uuidStringsMatch(assignedId, SavariSessionStore.authToken),
                   self.activeRideRow?["id"] as? String == oldRideId,
                   self.isDriverRideStatusVisible(oldStatus) {
                    self.applyDriverRideUpdate(old, status: oldStatus)
                }
            }
            return
        }

        guard let new = payload["new"] as? [String: Any] else {
            return
        }

        SavariLog.debug("[VM][DEBUG] ride payload new:", new)
        let status = (new["status"] as? String) ?? ""

        if status == "requested" {
            if !isVisibleRequestedRide(new, driverId: driverId) {
                return
            }
            Task { @MainActor in
                if !self.rideAccepted {
                    self.addIncomingRideIfNeeded(new)
                }
            }
            return
        }

        guard let rideId = new["id"] as? String else {
            return
        }

        Task { @MainActor in
            self.removeIncomingRideIfNeeded(rideId: rideId)
            let assignedId = (new["assigned_driver_id"] as? String) ?? (new["driver_id"] as? String)
            if let assignedId,
               uuidStringsMatch(assignedId, SavariSessionStore.authToken) {
                if self.activeRideRow?["id"] as? String == rideId || self.isDriverRideStatusVisible(status) {
                    self.applyDriverRideUpdate(new, status: status)
                }
            }
        }
    }

    @MainActor
    func startDriverIdleOfflineCountdownIfNeeded() {
        driverIdleOfflineTask?.cancel()
        guard isOnline, !rideAccepted, activeRideRow == nil else {
            driverIdleOfflineTask = nil
            return
        }

        driverIdleOfflineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: driverIdleOfflineLimitNanoseconds)
            if Task.isCancelled { return }

            await MainActor.run {
                guard let self else { return }
                guard self.isOnline, !self.rideAccepted, self.activeRideRow == nil else { return }
                SavariLog.debug("[VM] driver auto-offline after 15 minutes idle")
                self.stopOnline()
            }
        }
    }

    @MainActor
    func cancelDriverIdleOfflineCountdown() {
        driverIdleOfflineTask?.cancel()
        driverIdleOfflineTask = nil
    }

    @MainActor
    func startDriverRequestBacklogPolling(driverId: String) {
        driverRequestBacklogPollingTask?.cancel()
        guard isOnline, !rideAccepted, activeRideRow == nil else {
            driverRequestBacklogPollingTask = nil
            return
        }

        driverRequestBacklogPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchRequestedRideBacklog(driverId: driverId)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @MainActor
    func cancelDriverRequestBacklogPolling() {
        driverRequestBacklogPollingTask?.cancel()
        driverRequestBacklogPollingTask = nil
    }

    @MainActor
    private func applyDriverRideUpdate(_ row: [String: Any], status: String) {
        activeRideRow = row
        rideAccepted = true
        incomingRideRequests.removeAll()
        cancelDriverIdleOfflineCountdown()
        cancelDriverRequestBacklogPolling()

        switch status.lowercased() {
        case "ride_finished":
            invalidateDriverWaitTimer()
            driverFlow = .collectPayment
        case "passenger_cancelled_in_trip":
            invalidateDriverWaitTimer()
            cancelDriverActiveRidePolling()
            driverFlow = .collectPayment
        case "payment_collected":
            resetDriverRideToWaiting()
        case "cancelled":
            if ((row["cancelled_by"] as? String)?.lowercased() ?? "") != "driver" {
                invalidateDriverWaitTimer()
                cancelDriverActiveRidePolling()
                driverFlow = .passengerCancelled
            }
        case "in_progress":
            driverFlow = .inProgress
        case "boarded":
            boardingCodeVerified = true
            driverFlow = .verified
        case "assigned", "accepted", "driver_en_route":
            driverFlow = .idle
        default:
            break
        }
    }

    @MainActor
    func startDriverActiveRidePolling(rideId: String) {
        driverActiveRidePollingTask?.cancel()
        guard !rideId.isEmpty else {
            driverActiveRidePollingTask = nil
            return
        }

        driverActiveRidePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchDriverActiveRideSnapshot(rideId: rideId)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @MainActor
    func cancelDriverActiveRidePolling() {
        driverActiveRidePollingTask?.cancel()
        driverActiveRidePollingTask = nil
    }

    private func fetchDriverActiveRideSnapshot(rideId: String) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("rides")
                .select()
                .eq("id", value: rideId)
                .single()
                .execute()

            guard let row = jsonObject(from: response.data) else {
                return
            }

            await MainActor.run {
                let status = (row["status"] as? String) ?? ""
                guard self.activeRideRow?["id"] as? String == rideId || self.isDriverRideStatusVisible(status) else {
                    return
                }
                self.applyDriverRideUpdate(row, status: status)
            }
        } catch {
            SavariLog.debug("[VM] driver active ride snapshot failed:", error)
        }
    }

    @MainActor
    private func invalidateDriverWaitTimer() {
        waitTimer?.invalidate()
        waitTimer = nil
        waitSeconds = 0
    }

    nonisolated private func isDriverRideStatusVisible(_ status: String) -> Bool {
        switch status.lowercased() {
        case "assigned", "accepted", "driver_en_route", "arrived", "boarded", "in_progress", "ride_finished", "cancelled", "passenger_cancelled_in_trip", "payment_collected":
            return true
        default:
            return false
        }
    }

    private func fetchRequestedRideBacklog(driverId: String) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("rides")
                .select()
                .eq("status", value: "requested")
                .execute()

            guard let rows = jsonArray(from: response.data) else {
                SavariLog.debug("[VM] requested ride backlog response was not an array")
                return
            }

            let visibleRows = rows.filter { self.isVisibleRequestedRide($0, driverId: driverId) }
            let visibleIds = Set(visibleRows.compactMap { $0["id"] as? String })

            await MainActor.run {
                guard self.isOnline, !self.rideAccepted, self.activeRideRow == nil else {
                    return
                }

                for row in visibleRows {
                    self.addIncomingRideIfNeeded(row)
                }

                self.incomingRideRequests.removeAll { request in
                    guard let id = request["id"] as? String else { return true }
                    return !visibleIds.contains(id)
                }
            }
        } catch {
            SavariLog.debug("[VM] requested ride backlog fetch failed:", error)
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

    nonisolated private func isVisibleRequestedRide(_ row: [String: Any], driverId: String) -> Bool {
        guard (row["status"] as? String) == "requested" else {
            return false
        }

        if uuidStringsMatch(row["passenger_id"] as? String, driverId) {
            return false
        }

        return true
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
