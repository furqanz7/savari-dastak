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
        rideUpdateCancel?()
        rideUpdateCancel = nil

        rideUpdateCancel = await RealtimeManager.shared.subscribeRideRequests { [weak self] payload in
            guard let self,
                  let new = payload["new"] as? [String: Any],
                  let id = new["id"] as? String,
                  id == rideId else {
                return
            }

            Task { @MainActor in
                self.activeRideRow = new
                self.subscribeToAssignedDriverIfNeeded(from: new)
                self.applyPassengerRideStatus(new["status"] as? String)
            }
        }
    }

    private func subscribeToAssignedDriverIfNeeded(from rideRow: [String: Any]) {
        guard let assigned = (rideRow["assigned_driver_id"] as? String) ?? (rideRow["driver_id"] as? String) else {
            return
        }

        passengerFlow = .accepted
        assignedDriverUnsub?()
        assignedDriverUnsub = nil

        Task {
            self.assignedDriverUnsub = await RealtimeManager.shared.subscribeDriverLocation(driverId: assigned) { driver in
                Task { @MainActor in
                    self.assignedDriver = driver

                    if let pickupLatitude = self.activeRideRow?["pickup_lat"] as? Double,
                       let pickupLongitude = self.activeRideRow?["pickup_lon"] as? Double {
                        let pickup = CLLocationCoordinate2D(latitude: pickupLatitude, longitude: pickupLongitude)
                        let meters = distanceMetersBetween(driver.coordinate, pickup)
                        self.assignedDriverETASeconds = secondsFromMeters(meters, avgSpeedMetersPerSec: 8.0)
                    }
                }
            }
        }
    }

    private func applyPassengerRideStatus(_ status: String?) {
        switch status {
        case "arrived", "in_progress":
            passengerFlow = .enRoute
        case "boarded":
            boardingCodeVerified = true
        case "completed", "cancelled":
            assignedDriverUnsub?()
            assignedDriverUnsub = nil
            assignedDriver = nil
            rideAccepted = false
        default:
            break
        }
    }
}
