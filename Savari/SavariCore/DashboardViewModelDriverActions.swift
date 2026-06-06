import Foundation
import CoreLocation
import Supabase

extension DashboardViewModelRealtime {
    func driverArrived(rideId: String, driverId: String) async -> Bool {
        let ok = await RideService.shared.markArrived(rideId: rideId, driverId: driverId)
        if ok {
            await MainActor.run {
                var row = self.activeRideRow ?? [:]
                row["status"] = "arrived"
                self.activeRideRow = row
                self.waitSeconds = 0
                self.waitChargeApplied = false
                self.driverFlow = .awaitingOTP
                self.driverBoardingCodeEntry = ""
                self.driverBoardingCodeError = nil
            }

            await MainActor.run {
                self.waitTimer?.invalidate()
                self.waitTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.waitSeconds += 1
                    if self.waitSeconds > 120 && !self.waitChargeApplied {
                        self.waitChargeApplied = true
                        Task {
                            _ = await RideService.shared.applyWaitingChargeNow(rideId: rideId)
                            await self.loadActiveRideRowIfNeeded(rideId: rideId)
                        }
                    }
                }
            }
        }
        return ok
    }

    func verifyBoardingCodeAndBoard(rideId: String, code: String) async -> Bool {
        do {
            let fetch = try await SupabaseManager.shared.client
                .from("rides")
                .select("id,boarding_code")
                .eq("id", value: rideId)
                .single()
                .execute()

            if let dict = jsonObject(from: fetch.data), let expected = dict["boarding_code"] as? String {
                if expected == code {
                    let payload: [String: AnyEncodable] = [
                        "status": AnyEncodable("boarded"),
                        "boarded_at": AnyEncodable(Date().iso8601String)
                    ]
                    _ = try await SupabaseManager.shared.client
                        .from("rides")
                        .update(payload)
                        .eq("id", value: rideId)
                        .execute()
                    await MainActor.run {
                        var row = self.activeRideRow ?? [:]
                        row["status"] = "boarded"
                        self.activeRideRow = row
                        self.boardingCodeVerified = true
                        self.driverFlow = .verified
                        self.driverBoardingCodeEntry = ""
                        self.driverBoardingCodeError = nil
                        self.waitTimer?.invalidate()
                        self.waitTimer = nil
                    }
                    return true
                }
                await MainActor.run {
                    self.driverBoardingCodeError = "Code does not match"
                }
                return false
            }
        } catch {
            SavariLog.debug("verifyBoardingCodeAndBoard error:", error)
            await MainActor.run {
                self.driverBoardingCodeError = "Could not verify code"
            }
        }
        return false
    }

    func startRideNow(rideId: String) async -> Bool {
        let ok = await RideService.shared.startRide(rideId: rideId)
        if ok {
            await MainActor.run {
                var copy = activeRideRow ?? [:]
                copy["status"] = "in_progress"
                self.activeRideRow = copy
                self.waitTimer?.invalidate()
                self.waitTimer = nil
                self.waitSeconds = 0
                self.driverFlow = .inProgress
                self.assignedDriverUnsub?()
                self.assignedDriverUnsub = nil
                self.assignedDriver = nil
            }
        }
        return ok
    }

    func endRideNow(rideId: String) async -> Bool {
        let ok = await RideService.shared.endRideAndUnlockFare(rideId: rideId)
        if ok {
            await MainActor.run {
                var copy = self.activeRideRow ?? [:]
                copy["status"] = "completed"
                self.activeRideRow = copy
                self.rideAccepted = false
                self.activeRideRow = nil
                self.boardingCodeVerified = false
                self.driverBoardingCodeEntry = ""
                self.driverBoardingCodeError = nil
                self.driverFlow = .idle
                self.waitTimer?.invalidate()
                self.waitTimer = nil
                self.waitSeconds = 0
                self.assignedDriverUnsub?()
                self.assignedDriverUnsub = nil
                self.assignedDriver = nil
            }
        }
        return ok
    }

    func acceptRide(rideId: String, driverId: String) async -> Bool {
        let ok = await RideService.shared.acceptRide(rideId: rideId, driverId: driverId)
        if ok {
            await loadActiveRideRowIfNeeded(rideId: rideId)
            await MainActor.run {
                self.rideAccepted = true
                self.boardingCodeVerified = false
                self.driverFlow = .idle
                self.driverBoardingCodeEntry = ""
                self.driverBoardingCodeError = nil
                self.incomingRideRequests.removeAll()
            }
        }
        return ok
    }

    func acceptIncomingRide(_ incomingRide: [String: Any]) {
        guard let rideId = incomingRide["id"] as? String,
              let driverId = SavariSessionStore.authToken else { return }
        if uuidStringsMatch(incomingRide["passenger_id"] as? String, driverId) {
            SavariLog.debug("accept blocked: driver cannot accept their own passenger ride")
            return
        }

        Task {
            await MainActor.run {
                if let idx = self.incomingRideRequests.firstIndex(where: { ($0["id"] as? String) == rideId }) {
                    self.incomingRideRequests.remove(at: idx)
                }
            }

            let ok = await RideService.shared.acceptRide(rideId: rideId, driverId: driverId)
            if ok {
                await self.loadActiveRideRowIfNeeded(rideId: rideId)
                await MainActor.run {
                    self.rideAccepted = true
                    self.boardingCodeVerified = false
                    self.driverFlow = .idle
                    self.driverBoardingCodeEntry = ""
                    self.driverBoardingCodeError = nil
                    self.incomingRideRequests.removeAll()
                }
            } else {
                SavariLog.debug("accept failed (likely accepted by someone else)")
            }

            let currentLocation = GPSLocationPusher.shared.current
            await MainActor.run {
                self.incomingRideRequests.sort { lhs, rhs in
                    func distanceToPickup(_ row: [String: Any]) -> Double {
                        guard let pickupLatitude = row["pickup_lat"] as? Double,
                              let pickupLongitude = row["pickup_lon"] as? Double,
                              let currentLocation else {
                            return Double.greatestFiniteMagnitude
                        }
                        let pickup = CLLocationCoordinate2D(latitude: pickupLatitude, longitude: pickupLongitude)
                        return distanceMetersBetween(currentLocation, pickup)
                    }
                    return distanceToPickup(lhs) < distanceToPickup(rhs)
                }
            }
        }
    }

    func driverCancelAssignedRide(rideId: String, driverId: String, reason: String = "") async -> Bool {
        do {
            let params: [String: AnyEncodable] = [
                "p_ride_id": AnyEncodable(rideId),
                "p_driver_id": AnyEncodable(driverId),
                "p_reason": AnyEncodable(reason)
            ]
            let resp = try await SupabaseManager.shared.client.rpc("driver_cancel_ride", params: params).execute()
            if let cancelled = jsonBool(from: resp.data) {
                return cancelled
            }
        } catch {
            SavariLog.debug("driverCancelAssignedRide error:", error)
        }
        return false
    }
}
