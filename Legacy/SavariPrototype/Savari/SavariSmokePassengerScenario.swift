import Foundation

#if DEBUG && targetEnvironment(simulator)
@MainActor
extension SavariSmokeTestRunner {
    static func createPassengerRide() async {
        UserDefaults.standard.set("started", forKey: "savariSmokeCreateRideStatus")
        UserDefaults.standard.removeObject(forKey: "savariSmokeCreateRideId")
        UserDefaults.standard.removeObject(forKey: "savariSmokeCreateRideError")

        do {
            let userId = try await currentUserId()
            let existing = try? await SupabaseManager.shared.fetchProfile(for: userId)

            try await SupabaseManager.shared.upsertUserProfile(
                userId: userId,
                name: (existing?["name"] as? String) ?? "Savari Test Passenger",
                phone: (existing?["phone"] as? String) ?? "0000000000",
                role: "Passenger",
                age: existing?["age"] as? String,
                sex: existing?["sex"] as? String,
                vehicleNumber: nil
            )
            setLocalLogin(userId: userId, role: "Passenger")

            guard let rideId = await RideService.shared.createRideRequest(
                passengerId: userId.uuidString,
                pickupLat: 37.785834,
                pickupLon: -122.406417,
                dropLat: 37.774929,
                dropLon: -122.419416,
                vehicleType: "Auto",
                estimatedFare: 120,
                estimatedDistanceMeters: 1850,
                estimatedETASecs: 420
            ) else {
                UserDefaults.standard.set("failed_create_ride", forKey: "savariSmokeCreateRideStatus")
                return
            }

            UserDefaults.standard.set(rideId, forKey: "savariSmokeCreateRideId")
            UserDefaults.standard.set("created", forKey: "savariSmokeCreateRideStatus")
        } catch {
            UserDefaults.standard.set("failed", forKey: "savariSmokeCreateRideStatus")
            UserDefaults.standard.set(error.localizedDescription, forKey: "savariSmokeCreateRideError")
        }
    }
}
#endif
