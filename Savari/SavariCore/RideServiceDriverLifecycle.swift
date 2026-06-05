@preconcurrency import Foundation
import Supabase

extension RideService {
    func markArrived(rideId: String, driverId: String) async -> Bool {
        let payload: [String: AnyEncodable] = [
            "status": AnyEncodable("arrived"),
            "arrived_at": AnyEncodable(Date().iso8601String),
            "driver_id": AnyEncodable(driverId)
        ]
        do {
            _ = try await SupabaseManager.shared.client
                .from("rides")
                .update(payload)
                .eq("id", value: rideId)
                .execute()
            return true
        } catch {
            SavariLog.debug("markArrived error:", error)
            return false
        }
    }

    func startRide(rideId: String) async -> Bool {
        let payload: [String: AnyEncodable] = [
            "status": AnyEncodable("in_progress")
        ]
        do {
            _ = try await SupabaseManager.shared.client
                .from("rides")
                .update(payload)
                .eq("id", value: rideId)
                .execute()
            return true
        } catch {
            SavariLog.debug("startRide error:", error)
            return false
        }
    }

    func endRideAndUnlockFare(rideId: String) async -> Bool {
        let payload: [String: AnyEncodable] = [
            "status": AnyEncodable("completed"),
            "ended_at": AnyEncodable(Date().iso8601String),
            "fare_unlocked": AnyEncodable(true)
        ]
        do {
            _ = try await SupabaseManager.shared.client
                .from("rides")
                .update(payload)
                .eq("id", value: rideId)
                .execute()
            return true
        } catch {
            SavariLog.debug("endRideAndUnlockFare error:", error)
            return false
        }
    }
}
