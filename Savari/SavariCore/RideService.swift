import SwiftUI
@preconcurrency import Foundation
import MapKit
import Combine
import Supabase
import CoreLocation
import Realtime


final class RideService {
    static let shared = RideService()
    private init() {}

    private func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func jsonArray(from data: Data) -> [[String: Any]]? {
        try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    private func jsonBool(from data: Data) -> Bool? {
        try? JSONDecoder().decode(Bool.self, from: data)
    }

    // MARK: - Create ride request
    /// Returns the inserted ride UUID string on success
    func createRideRequest(
        passengerId: String,
        pickupLat: Double,
        pickupLon: Double,
        dropLat: Double,
        dropLon: Double,
        vehicleType: String,
        estimatedFare: Double,
        estimatedDistanceMeters: Double,
        estimatedETASecs: Int
    ) async -> String? {
        let payload: [String: AnyEncodable] = [
            "passenger_id": AnyEncodable(passengerId),
            "pickup_lat": AnyEncodable(pickupLat),
            "pickup_lon": AnyEncodable(pickupLon),
            "drop_lat": AnyEncodable(dropLat),
            "drop_lon": AnyEncodable(dropLon),
            "vehicle_type": AnyEncodable(vehicleType),
            "estimated_fare": AnyEncodable(estimatedFare),
            "estimated_distance_m": AnyEncodable(estimatedDistanceMeters),
            "estimated_eta_secs": AnyEncodable(estimatedETASecs),
            "status": AnyEncodable("requested")
        ]

        do {
            let resp = try await SupabaseManager.shared.client
                .from("rides")
                .insert([payload])
                .select()    // request the inserted row back
                .single()
                .execute()

            let data = resp.data
            if let dict = jsonObject(from: data), let id = dict["id"] as? String {
                return id
            }

            if let arr = jsonArray(from: data), let id = arr.first?["id"] as? String {
                return id
            }
            SavariLog.debug("[RideService] createRideRequest returned unexpected response:", String(data: data, encoding: .utf8) ?? "<binary>")
        } catch {
            SavariLog.debug("[RideService] createRideRequest error:", error)
        }
        return nil
    }

    // MARK: - Accept ride (calls atomic RPC)
    /// Calls RPC accept_ride which MUST do the atomic update and return boolean
    func acceptRide(rideId: String, driverId: String) async -> Bool {
        let boardingCode = Self.makeBoardingCode(4)
        let params: [String: AnyEncodable] = [
            "p_ride_id": AnyEncodable(rideId),
            "p_driver_id": AnyEncodable(driverId),
            "p_boarding_code": AnyEncodable(boardingCode)
        ]
        do {
            let resp = try await SupabaseManager.shared.client
                .rpc("accept_ride", params: params)
                .execute()

            if let bool = jsonBool(from: resp.data) { return bool }
            if let dict = jsonObject(from: resp.data), let ok = dict["ok"] as? Bool { return ok }
            if let arr = jsonArray(from: resp.data) { return !arr.isEmpty }
            return false
        } catch {
            SavariLog.debug("[RideService] acceptRide rpc error:", error)
            return false
        }
    }

    // MARK: - Other RPCs used by code
    func driverCancelAssignedRide(rideId: String, driverId: String, reason: String = "") async -> Bool {
        let params: [String: AnyEncodable] = [
            "p_ride_id": AnyEncodable(rideId),
            "p_driver_id": AnyEncodable(driverId),
            "p_reason": AnyEncodable(reason)
        ]
        do {
            let resp = try await SupabaseManager.shared.client.rpc("driver_cancel_ride", params: params).execute()
            if let b = jsonBool(from: resp.data) { return b }
            if let dict = jsonObject(from: resp.data), let ok = dict["ok"] as? Bool { return ok }
        } catch {
            SavariLog.debug("[RideService] driverCancelAssignedRide error:", error)
        }
        return false
    }

    func applyWaitingChargeNow(rideId: String, thresholdSeconds: Int = 120, chargePerMin: Double = 10.0) async -> Bool {
        let params: [String: AnyEncodable] = [
            "ride_id": AnyEncodable(rideId),
            "threshold_seconds": AnyEncodable(thresholdSeconds),
            "charge_per_min": AnyEncodable(chargePerMin)
        ]
        do {
            let resp = try await SupabaseManager.shared.client.rpc("apply_waiting_charge", params: params).execute()
            if let b = jsonBool(from: resp.data) { return b }
            if let dict = jsonObject(from: resp.data), let ok = dict["ok"] as? Bool { return ok }
        } catch {
            SavariLog.debug("[RideService] applyWaitingChargeNow rpc error:", error)
        }
        return false
    }

    // MARK: - Upsert location
    func upsertDriverLocation(driverId: String, lat: Double, lon: Double) async {
        let payload: [String: AnyEncodable] = [
            "driver_id": AnyEncodable(driverId),
            "latitude": AnyEncodable(lat),
            "longitude": AnyEncodable(lon)
        ]
        do {
            _ = try await SupabaseManager.shared.client
                .from("driver_locations")
                .upsert([payload])
                .execute()
        } catch {
            SavariLog.debug("[RideService] upsertDriverLocation error:", error)
        }
    }

    // MARK: - Helpers
    private static func makeBoardingCode(_ digits: Int = 4) -> String {
        let max = Int(pow(10.0, Double(digits)))
        let min = max / 10
        return String(Int.random(in: min..<max))
    }
}

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
