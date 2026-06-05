import Foundation
import Supabase
import PostgREST

#if DEBUG && targetEnvironment(simulator)
@MainActor
extension SavariSmokeTestRunner {
    static func runSelfAcceptCheck() async {
        UserDefaults.standard.set("started", forKey: "savariSmokeSelfAcceptStatus")
        UserDefaults.standard.removeObject(forKey: "savariSmokeSelfAcceptRideId")
        UserDefaults.standard.removeObject(forKey: "savariSmokeSelfAcceptAccepted")
        UserDefaults.standard.removeObject(forKey: "savariSmokeSelfAcceptError")
        SavariLog.debug("[SMOKE] self_accept_check started")

        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id
            let userIdString = userId.uuidString
            let originalProfile = try? await SupabaseManager.shared.fetchProfile(for: userId)

            SavariSessionStore.setLoggedIn(userId: userIdString, role: "Driver")

            try await SupabaseManager.shared.upsertUserProfile(
                userId: userId,
                name: (originalProfile?["name"] as? String) ?? "Savari Smoke",
                phone: (originalProfile?["phone"] as? String) ?? "0000000000",
                role: "Driver",
                age: originalProfile?["age"] as? String,
                sex: originalProfile?["sex"] as? String,
                vehicleNumber: nil
            )

            guard let rideId = await RideService.shared.createRideRequest(
                passengerId: userIdString,
                pickupLat: 37.785834,
                pickupLon: -122.406417,
                dropLat: 37.774929,
                dropLon: -122.419416,
                vehicleType: "Auto",
                estimatedFare: 120,
                estimatedDistanceMeters: 1850,
                estimatedETASecs: 420
            ) else {
                SavariLog.debug("[SMOKE][FAIL] self_accept_check could not create ride")
                UserDefaults.standard.set("failed_create_ride", forKey: "savariSmokeSelfAcceptStatus")
                return
            }

            UserDefaults.standard.set(rideId, forKey: "savariSmokeSelfAcceptRideId")
            SavariLog.debug("[SMOKE] self_accept_check created ride \(rideId)")
            let accepted = await RideService.shared.acceptRide(rideId: rideId, driverId: userIdString)
            UserDefaults.standard.set(accepted, forKey: "savariSmokeSelfAcceptAccepted")
            UserDefaults.standard.set(accepted ? "failed_accepted_own_ride" : "passed_blocked_own_ride", forKey: "savariSmokeSelfAcceptStatus")
            SavariLog.debug(accepted ? "[SMOKE][FAIL] self_accept_check accepted own ride" : "[SMOKE][PASS] self_accept_check blocked own ride")

            await cancelSmokeRide(rideId: rideId)
            if let originalProfile {
                try? await SupabaseManager.shared.upsertUserProfile(
                    userId: userId,
                    name: (originalProfile["name"] as? String) ?? "Savari Smoke",
                    phone: (originalProfile["phone"] as? String) ?? "0000000000",
                    role: (originalProfile["role"] as? String) ?? "Passenger",
                    age: originalProfile["age"] as? String,
                    sex: originalProfile["sex"] as? String,
                    vehicleNumber: nil
                )
            }
        } catch {
            UserDefaults.standard.set("failed_error", forKey: "savariSmokeSelfAcceptStatus")
            UserDefaults.standard.set(error.localizedDescription, forKey: "savariSmokeSelfAcceptError")
            SavariLog.debug("[SMOKE][FAIL] self_accept_check error: \(error.localizedDescription)")
        }
    }

    private static func cancelSmokeRide(rideId: String) async {
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
            SavariLog.debug("[SMOKE] self_accept_check cleaned ride \(rideId)")
        } catch {
            SavariLog.debug("[SMOKE][WARN] self_accept_check cleanup failed: \(error.localizedDescription)")
        }
    }
}
#endif
