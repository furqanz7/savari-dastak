import Foundation
import CoreLocation
import Supabase

extension DashboardViewModelRealtime {
    @MainActor
    func cancelRideRequest() async {
        let rideId = selectedRide.orderID.isEmpty
            ? (activeRideRow?["id"] as? String ?? "")
            : selectedRide.orderID
        if rideId.isEmpty {
            SavariLog.debug("[CancelRide] No rideId found")
            return
        }

        if (activeRideRow?["status"] as? String)?.lowercased() == "in_progress" {
            await cancelMidTripRide(rideId: rideId)
            return
        }

        do {
            let payload: [String: AnyEncodable] = [
                "status": AnyEncodable("cancelled"),
                "cancelled_at": AnyEncodable(Date().iso8601String),
                "cancelled_by": AnyEncodable("passenger")
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
            activeRideRow = nil
            passengerFlow = .idle
            SavariLog.debug("[CancelRide] Ride cancelled:", rideId)
        } catch {
            SavariLog.debug("[CancelRide] Error:", error.localizedDescription)
        }
    }

    @MainActor
    private func cancelMidTripRide(rideId: String) async {
        guard let passengerId = SavariSessionStore.authToken else {
            SavariLog.debug("[CancelRide] Missing passenger id")
            return
        }

        guard let current = GPSLocationPusher.shared.current else {
            SavariLog.debug("[CancelRide] Missing passenger location for mid-trip cancellation")
            return
        }

        do {
            let params: [String: AnyEncodable] = [
                "p_ride_id": AnyEncodable(rideId),
                "p_passenger_id": AnyEncodable(passengerId),
                "p_cancel_lat": AnyEncodable(current.latitude),
                "p_cancel_lon": AnyEncodable(current.longitude)
            ]

            let response = try await SupabaseManager.shared.client
                .rpc("passenger_cancel_mid_trip", params: params)
                .execute()

            guard let result = jsonObject(from: response.data),
                  (result["ok"] as? Bool) == true else {
                SavariLog.debug("[CancelRide] Mid-trip cancellation rejected")
                await cancelMidTripRideDirectly(rideId: rideId, passengerId: passengerId, current: current)
                return
            }

            var row = activeRideRow ?? [:]
            row["status"] = "passenger_cancelled_in_trip"
            row["cancelled_at"] = Date().iso8601String
            row["cancelled_by"] = "passenger"
            row["cancellation_lat"] = current.latitude
            row["cancellation_lon"] = current.longitude
            if let fare = doubleValue(result["fare"]) {
                row["cancellation_fare"] = fare
                row["fare"] = fare
            }
            if let distance = doubleValue(result["distance_m"]) {
                row["cancellation_distance_m"] = distance
            }

            handlePassengerMidTripCancellation(row: row)
        } catch {
            SavariLog.debug("[CancelRide] Mid-trip cancellation error:", error.localizedDescription)
            await cancelMidTripRideDirectly(rideId: rideId, passengerId: passengerId, current: current)
        }
    }

    @MainActor
    private func cancelMidTripRideDirectly(
        rideId: String,
        passengerId: String,
        current: CLLocationCoordinate2D
    ) async {
        guard let pickupLatitude = doubleValue(activeRideRow?["pickup_lat"]),
              let pickupLongitude = doubleValue(activeRideRow?["pickup_lon"]) else {
            SavariLog.debug("[CancelRide] Direct mid-trip cancellation missing pickup")
            return
        }

        let pickup = CLLocationCoordinate2D(latitude: pickupLatitude, longitude: pickupLongitude)
        let cancellationDistance = distanceMetersBetween(pickup, current)
        let cancellationFare = midTripCancellationFare(distanceMeters: cancellationDistance)

        let payload: [String: AnyEncodable] = [
            "status": AnyEncodable("passenger_cancelled_in_trip"),
            "cancelled_at": AnyEncodable(Date().iso8601String),
            "cancelled_by": AnyEncodable("passenger"),
            "cancellation_lat": AnyEncodable(current.latitude),
            "cancellation_lon": AnyEncodable(current.longitude),
            "cancellation_distance_m": AnyEncodable(cancellationDistance),
            "cancellation_fare": AnyEncodable(cancellationFare),
            "fare": AnyEncodable(cancellationFare),
            "fare_unlocked": AnyEncodable(true),
            "ended_at": AnyEncodable(Date().iso8601String)
        ]

        do {
            let response = try await SupabaseManager.shared.client
                .from("rides")
                .update(payload)
                .eq("id", value: rideId)
                .eq("passenger_id", value: passengerId)
                .eq("status", value: "in_progress")
                .select()
                .single()
                .execute()

            if let row = jsonObject(from: response.data) {
                handlePassengerMidTripCancellation(row: row)
            } else {
                var row = activeRideRow ?? [:]
                row["status"] = "passenger_cancelled_in_trip"
                row["cancelled_at"] = Date().iso8601String
                row["cancelled_by"] = "passenger"
                row["cancellation_lat"] = current.latitude
                row["cancellation_lon"] = current.longitude
                row["cancellation_fare"] = cancellationFare
                row["fare"] = cancellationFare
                row["cancellation_distance_m"] = cancellationDistance
                row["fare_unlocked"] = true
                row["ended_at"] = Date().iso8601String
                handlePassengerMidTripCancellation(row: row)
            }
        } catch {
            SavariLog.debug("[CancelRide] Direct mid-trip cancellation error:", error.localizedDescription)
        }
    }

    private func midTripCancellationFare(distanceMeters: CLLocationDistance) -> Double {
        let estimatedDistance = max(0, doubleValue(activeRideRow?["estimated_distance_m"]) ?? 0)
        let estimatedFare = max(0, doubleValue(activeRideRow?["estimated_fare"]) ?? selectedRide.amount)
        let proportionalFare: Double?

        if estimatedDistance > 0, estimatedFare > 0 {
            proportionalFare = estimatedFare * min(1, distanceMeters / estimatedDistance)
        } else {
            proportionalFare = nil
        }

        let fallbackFare = 20 + ((distanceMeters / 1000) * 12)
        return max(30, proportionalFare ?? fallbackFare)
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
            guard let self else {
                return
            }

            if payload["new"] == nil,
               let old = payload["old"] as? [String: Any],
               let id = old["id"] as? String,
               id == rideId {
                Task { @MainActor in
                    self.handlePassengerRideDeleted(old)
                }
                return
            }

            guard let new = payload["new"] as? [String: Any],
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
            await fetchPassengerRideHistorySnapshot(rideId: rideId)
        }
    }

    private func fetchPassengerRideHistorySnapshot(rideId: String) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("ride_history")
                .select()
                .eq("id", value: rideId)
                .single()
                .execute()

            if var row = jsonObject(from: response.data) {
                row["status"] = (row["status"] as? String) ?? "completed"
                await MainActor.run {
                    self.handlePassengerRideRow(row)
                }
            }
        } catch {
            SavariLog.debug("[PassengerRide] history snapshot fetch failed:", error)
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
    private func handlePassengerRideDeleted(_ oldRideRow: [String: Any]) {
        let deletedStatus = (oldRideRow["status"] as? String)?.lowercased()
        let currentStatus = (activeRideRow?["status"] as? String)?.lowercased()
        if deletedStatus == "completed" || isCompletablePassengerStatus(currentStatus) {
            handlePassengerRideCompleted(row: oldRideRow)
        }
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
        case "passenger_cancelled_in_trip":
            handlePassengerMidTripCancellation(row: activeRideRow)
        case "ride_finished":
            handlePassengerRideFinished(row: activeRideRow)
        case "payment_collected":
            handlePassengerPaymentCollected(row: activeRideRow)
        case "completed", "cancelled":
            if status?.lowercased() == "completed" {
                handlePassengerRideCompleted(row: activeRideRow)
                return
            }
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

    @MainActor
    private func handlePassengerRideCompleted(row: [String: Any]?) {
        var completedRow = row ?? activeRideRow ?? [:]
        completedRow["status"] = "completed"
        activeRideRow = completedRow
        assignedDriverUnsub?()
        assignedDriverUnsub = nil
        assignedDriverId = nil
        assignedDriver = nil
        assignedDriverETASeconds = nil
        rideAccepted = false
        rideRequested = false
        stopSubscribingMyRide()
        passengerFlow = .completed
    }

    @MainActor
    private func handlePassengerRideFinished(row: [String: Any]?) {
        var finishedRow = row ?? activeRideRow ?? [:]
        finishedRow["status"] = "ride_finished"
        activeRideRow = finishedRow
        assignedDriverUnsub?()
        assignedDriverUnsub = nil
        assignedDriverId = nil
        assignedDriver = nil
        assignedDriverETASeconds = nil
        rideAccepted = false
        rideRequested = false
        passengerFlow = .completed
    }

    @MainActor
    private func handlePassengerMidTripCancellation(row: [String: Any]?) {
        var cancellationRow = row ?? activeRideRow ?? [:]
        cancellationRow["status"] = "passenger_cancelled_in_trip"
        activeRideRow = cancellationRow
        assignedDriverUnsub?()
        assignedDriverUnsub = nil
        assignedDriverId = nil
        assignedDriver = nil
        assignedDriverETASeconds = nil
        rideAccepted = false
        rideRequested = false
        passengerFlow = .completed
    }

    @MainActor
    private func handlePassengerPaymentCollected(row: [String: Any]?) {
        var paymentRow = row ?? activeRideRow ?? [:]
        paymentRow["status"] = "payment_collected"
        activeRideRow = paymentRow
        assignedDriverUnsub?()
        assignedDriverUnsub = nil
        assignedDriverId = nil
        assignedDriver = nil
        assignedDriverETASeconds = nil
        rideAccepted = false
        rideRequested = false
        stopSubscribingMyRide()
        passengerFlow = .completed
    }

    nonisolated private func isCompletablePassengerStatus(_ status: String?) -> Bool {
        switch status {
        case "assigned", "accepted", "driver_en_route", "arrived", "boarded", "in_progress", "ride_finished", "passenger_cancelled_in_trip":
            return true
        default:
            return false
        }
    }

    nonisolated private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
