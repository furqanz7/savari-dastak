@preconcurrency import Foundation
import Supabase

extension RideService {
    func markArrived(rideId: String, driverId: String) async -> Bool {
        let params: [String: AnyEncodable] = [
            "p_ride_id": AnyEncodable(rideId),
            "p_driver_id": AnyEncodable(driverId),
            "p_arrival_threshold_m": AnyEncodable(100.0)
        ]
        do {
            let resp = try await SupabaseManager.shared.client
                .rpc("mark_driver_arrived", params: params)
                .execute()

            if let bool = try? JSONDecoder().decode(Bool.self, from: resp.data) {
                return bool
            }
        } catch {
            SavariLog.debug("markArrived error:", error)
        }
        return false
    }

    func startRide(rideId: String) async -> Bool {
        let payload: [String: AnyEncodable] = [
            "status": AnyEncodable("in_progress"),
            "started_at": AnyEncodable(Date().iso8601String)
        ]
        do {
            _ = try await SupabaseManager.shared.client
                .from("rides")
                .update(payload)
                .eq("id", value: rideId)
                .select()
                .single()
                .execute()
            return true
        } catch {
            SavariLog.debug("startRide error:", error)
            return false
        }
    }

    func completeRideAtDropoff(rideId: String, driverId: String) async -> Bool {
        let params: [String: AnyEncodable] = [
            "p_ride_id": AnyEncodable(rideId),
            "p_driver_id": AnyEncodable(driverId),
            "p_dropoff_threshold_m": AnyEncodable(100.0)
        ]
        do {
            let response = try await SupabaseManager.shared.client
                .rpc("complete_ride", params: params)
                .execute()

            if let completed = try? JSONDecoder().decode(Bool.self, from: response.data) {
                return completed
            }
            return false
        } catch {
            SavariLog.debug("completeRideAtDropoff error:", error)
            return false
        }
    }
}
