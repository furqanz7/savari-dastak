import Foundation
import Supabase
import PostgREST

#if DEBUG && targetEnvironment(simulator)
@MainActor
extension SavariSmokeTestRunner {
    static func completeDriverOnboarding() async {
        UserDefaults.standard.set("started", forKey: "savariSmokeDriverOnboardingStatus")
        UserDefaults.standard.removeObject(forKey: "savariSmokeDriverOnboardingError")

        do {
            let userId = try await currentUserId()
            let existing = try? await SupabaseManager.shared.fetchProfile(for: userId)

            try await SupabaseManager.shared.upsertUserProfile(
                userId: userId,
                name: (existing?["name"] as? String) ?? "Savari Test Driver",
                phone: (existing?["phone"] as? String) ?? "0000000000",
                role: "Driver",
                age: existing?["age"] as? String,
                sex: existing?["sex"] as? String,
                vehicleNumber: "SIM-DRIVER"
            )

            setLocalLogin(userId: userId, role: "Driver")
            UserDefaults.standard.set("completed", forKey: "savariSmokeDriverOnboardingStatus")
        } catch {
            UserDefaults.standard.set("failed", forKey: "savariSmokeDriverOnboardingStatus")
            UserDefaults.standard.set(error.localizedDescription, forKey: "savariSmokeDriverOnboardingError")
        }
    }

    static func runDriverLifecycle(rideId: String?) async {
        UserDefaults.standard.set("started", forKey: "savariSmokeDriverLifecycleStatus")
        resetDriverLifecycleSmokeState()

        guard let rideId, !rideId.isEmpty else {
            UserDefaults.standard.set("failed_missing_ride_id", forKey: "savariSmokeDriverLifecycleStatus")
            return
        }

        do {
            let driverId = try await currentUserId()
            let existing = try? await SupabaseManager.shared.fetchProfile(for: driverId)

            try await SupabaseManager.shared.upsertUserProfile(
                userId: driverId,
                name: (existing?["name"] as? String) ?? "Savari Test Driver",
                phone: (existing?["phone"] as? String) ?? "0000000000",
                role: "Driver",
                age: existing?["age"] as? String,
                sex: existing?["sex"] as? String,
                vehicleNumber: "SIM-DRIVER"
            )
            setLocalLogin(userId: driverId, role: "Driver")

            await RideService.shared.upsertDriverLocation(
                driverId: driverId.uuidString,
                lat: 37.785834,
                lon: -122.406417
            )

            let accepted = await RideService.shared.acceptRide(rideId: rideId, driverId: driverId.uuidString)
            UserDefaults.standard.set(accepted, forKey: "savariSmokeDriverLifecycleAccepted")
            guard accepted else {
                UserDefaults.standard.set("failed_accept", forKey: "savariSmokeDriverLifecycleStatus")
                return
            }

            let arrived = await RideService.shared.markArrived(rideId: rideId, driverId: driverId.uuidString)
            UserDefaults.standard.set(arrived, forKey: "savariSmokeDriverLifecycleArrived")
            guard arrived else {
                UserDefaults.standard.set("failed_arrive", forKey: "savariSmokeDriverLifecycleStatus")
                return
            }

            let started = await RideService.shared.startRide(rideId: rideId)
            UserDefaults.standard.set(started, forKey: "savariSmokeDriverLifecycleStarted")
            guard started else {
                UserDefaults.standard.set("failed_start", forKey: "savariSmokeDriverLifecycleStatus")
                return
            }

            let ended = await RideService.shared.endRideAndUnlockFare(rideId: rideId)
            UserDefaults.standard.set(ended, forKey: "savariSmokeDriverLifecycleEnded")
            if !ended {
                await diagnoseEndRideFailure(rideId: rideId)
            }
            UserDefaults.standard.set(ended ? "completed" : "failed_end", forKey: "savariSmokeDriverLifecycleStatus")
        } catch {
            UserDefaults.standard.set("failed", forKey: "savariSmokeDriverLifecycleStatus")
            UserDefaults.standard.set(error.localizedDescription, forKey: "savariSmokeDriverLifecycleError")
        }
    }

    private static func resetDriverLifecycleSmokeState() {
        [
            "savariSmokeDriverLifecycleAccepted",
            "savariSmokeDriverLifecycleArrived",
            "savariSmokeDriverLifecycleStarted",
            "savariSmokeDriverLifecycleEnded",
            "savariSmokeDriverLifecycleError",
            "savariSmokeDriverLifecycleEndError",
            "savariSmokeDriverLifecycleEndErrorDescription",
            "savariSmokeDriverLifecycleEndDiagnosticBody"
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func diagnoseEndRideFailure(rideId: String) async {
        UserDefaults.standard.removeObject(forKey: "savariSmokeDriverLifecycleEndError")
        UserDefaults.standard.removeObject(forKey: "savariSmokeDriverLifecycleEndErrorDescription")
        UserDefaults.standard.removeObject(forKey: "savariSmokeDriverLifecycleEndDiagnosticBody")

        let payload: [String: AnyEncodable] = [
            "status": AnyEncodable("completed"),
            "ended_at": AnyEncodable(Date().iso8601String),
            "fare_unlocked": AnyEncodable(true)
        ]

        do {
            let response = try await SupabaseManager.shared.client
                .from("rides")
                .update(payload)
                .eq("id", value: rideId)
                .select("id,status,ended_at,fare_unlocked")
                .execute()

            if let body = String(data: response.data, encoding: .utf8) {
                UserDefaults.standard.set(body, forKey: "savariSmokeDriverLifecycleEndDiagnosticBody")
            }
        } catch {
            UserDefaults.standard.set(String(describing: error), forKey: "savariSmokeDriverLifecycleEndError")
            UserDefaults.standard.set(error.localizedDescription, forKey: "savariSmokeDriverLifecycleEndErrorDescription")
        }
    }
}
#endif
