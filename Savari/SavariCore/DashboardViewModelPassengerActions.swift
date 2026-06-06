import Foundation
import CoreLocation
import Supabase

extension DashboardViewModelRealtime {
    @MainActor
    func cancelRideRequest() async {
        let rideId = selectedRide.orderID
        if rideId.isEmpty {
            SavariLog.debug("[CancelRide] No rideId found")
            return
        }

        do {
            let payload: [String: AnyEncodable] = [
                "status": AnyEncodable("cancelled"),
                "cancelled_at": AnyEncodable(Date().iso8601String)
            ]
            _ = try await SupabaseManager.shared.client
                .from("rides")
                .update(payload)
                .eq("id", value: rideId)
                .execute()
            stopSubscribingMyRide()
            assignedDriverUnsub?()
            assignedDriverUnsub = nil
            assignedDriverId = nil
            assignedDriver = nil
            assignedDriverETASeconds = nil
            rideAccepted = false
            rideRequested = false
            SavariLog.debug("[CancelRide] Ride cancelled:", rideId)
        } catch {
            SavariLog.debug("[CancelRide] Error:", error.localizedDescription)
        }
    }

    func updateFareEstimates(distanceMeters: CLLocationDistance) {
        let km = distanceMeters / 1000

        fareAuto = max(50, 20 + km * 12)
        fareBike = max(30, 10 + km * 8)

        if chosenTransportOption == nil {
            chosenTransportOption = "Auto"
            selectedRide.amount = fareAuto ?? 0
        }
    }

    func subscribeToMyRide(rideId: String) async {
        stopSubscribingMyRide()

        rideUpdateCancel = await RealtimeManager.shared.subscribeRideRequests { [weak self] payload in
            guard let self,
                  let new = payload["new"] as? [String: Any],
                  let id = new["id"] as? String,
                  id == rideId else {
                return
            }

            Task { @MainActor in
                self.handlePassengerRideRow(new)
            }
        }

        await fetchPassengerRideSnapshot(rideId: rideId)
        startPassengerRidePolling(rideId: rideId)
    }

    private func fetchPassengerRideSnapshot(rideId: String) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("rides")
                .select()
                .eq("id", value: rideId)
                .single()
                .execute()

            if let row = jsonObject(from: response.data) {
                await MainActor.run {
                    self.handlePassengerRideRow(row)
                }
            }
        } catch {
            SavariLog.debug("[PassengerRide] snapshot fetch failed:", error)
        }
    }

    private func startPassengerRidePolling(rideId: String) {
        passengerRidePollingTask?.cancel()
        passengerRidePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                await self?.fetchPassengerRideSnapshot(rideId: rideId)
            }
        }
    }

    @MainActor
    private func handlePassengerRideRow(_ rideRow: [String: Any]) {
        activeRideRow = rideRow
        subscribeToAssignedDriverIfNeeded(from: rideRow)
        applyPassengerRideStatus(rideRow["status"] as? String)
    }

    @MainActor
    private func subscribeToAssignedDriverIfNeeded(from rideRow: [String: Any]) {
        guard let assigned = (rideRow["assigned_driver_id"] as? String) ?? (rideRow["driver_id"] as? String) else {
            return
        }

        rideAccepted = true
        if passengerFlow != .enRoute {
            passengerFlow = .accepted
        }

        if assignedDriverId == assigned, assignedDriverUnsub != nil {
            return
        }

        assignedDriverId = assigned
        assignedDriverUnsub?()
        assignedDriverUnsub = nil

        Task { [weak self] in
            let unsubscribe = await RealtimeManager.shared.subscribeDriverLocation(driverId: assigned) { driver in
                Task { @MainActor in
                    guard let self else { return }
                    self.assignedDriver = driver

                    if let pickupLatitude = self.activeRideRow?["pickup_lat"] as? Double,
                       let pickupLongitude = self.activeRideRow?["pickup_lon"] as? Double {
                        let pickup = CLLocationCoordinate2D(latitude: pickupLatitude, longitude: pickupLongitude)
                        let meters = distanceMetersBetween(driver.coordinate, pickup)
                        self.assignedDriverETASeconds = secondsFromMeters(meters, avgSpeedMetersPerSec: 8.0)
                    }
                }
            }

            await MainActor.run {
                self?.assignedDriverUnsub = unsubscribe
            }
        }
    }

    @MainActor
    private func applyPassengerRideStatus(_ status: String?) {
        switch status?.lowercased() {
        case "requested":
            passengerFlow = .matching
        case "assigned", "accepted", "driver_en_route":
            rideAccepted = true
            if passengerFlow != .enRoute {
                passengerFlow = .accepted
            }
        case "arrived", "in_progress":
            rideAccepted = true
            passengerFlow = .enRoute
        case "boarded":
            rideAccepted = true
            boardingCodeVerified = true
            passengerFlow = .enRoute
        case "completed", "cancelled":
            assignedDriverUnsub?()
            assignedDriverUnsub = nil
            assignedDriverId = nil
            assignedDriver = nil
            assignedDriverETASeconds = nil
            rideAccepted = false
            rideRequested = false
            stopSubscribingMyRide()
            passengerFlow = status?.lowercased() == "completed" ? .completed : .idle
        default:
            break
        }
    }
}
