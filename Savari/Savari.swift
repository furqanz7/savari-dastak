//
//  Savari.swift
//  Savari
//
//  Created by Furqan on 07/10/25.
//

import SwiftUI
import GoogleSignIn
import Supabase
import Auth
import PostgREST

@main
struct Savari: App {
    @AppStorage("authToken") var authToken: String?

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "CLIENT_ID") as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            print("✅ Google Client ID configured: \(clientID)")
        } else {
            print("❌ Failed to find CLIENT_ID in Info.plist")
        }
    }

    // MARK: - AppDelegate
    class AppDelegate: UIResponder, UIApplicationDelegate {

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
        ) -> Bool {
            _ = launchOptions // keep parameter used to avoid warnings
            return true
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

// RootView: if already logged in, go to dashboard; otherwise show RoleSelection -> LoginFlow
struct RootView: View {
    @AppStorage("authToken") var authToken: String?
    @AppStorage("isOnboardingComplete") var isOnboardingComplete: Bool = false
    @AppStorage("lastRole") var lastRole: String?
    @State private var showSplash: Bool = true

    var body: some View {
        Group {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                if let token = authToken, !token.isEmpty {
                    if isOnboardingComplete {
                        DashboardView(role: lastRole ?? "Passenger")
                    } else {
                        LoginFlowView(role: lastRole)
                    }
                } else {
                    LoginFlowView()
                }
            }
        }
        .onAppear {
            SavariSmokeTestRunner.runIfRequested()

            // Simulate startup work or wait for initialization to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut) {
                    showSplash = false
                }
            }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor
private enum SavariSmokeTestRunner {
    private static var didStart = false

    static func runIfRequested() {
        guard !didStart else { return }
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--savari-smoke-self-accept")
            || args.contains("--savari-complete-driver-onboarding")
            || args.contains("--savari-smoke-create-ride")
            || args.contains("--savari-smoke-driver-lifecycle")
        else { return }
        didStart = true

        Task {
            if args.contains("--savari-smoke-self-accept") {
                await runSelfAcceptCheck()
            } else if args.contains("--savari-complete-driver-onboarding") {
                await completeDriverOnboarding()
            } else if args.contains("--savari-smoke-create-ride") {
                await createPassengerRide()
            } else if args.contains("--savari-smoke-driver-lifecycle") {
                await runDriverLifecycle(rideId: argumentValue(after: "--savari-smoke-driver-lifecycle", in: args))
            }
        }
    }

    private static func argumentValue(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }

    private static func completeDriverOnboarding() async {
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

    private static func createPassengerRide() async {
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

    private static func runDriverLifecycle(rideId: String?) async {
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

    private static func currentUserId() async throws -> UUID {
        let session = try await SupabaseManager.shared.client.auth.session
        return session.user.id
    }

    private static func setLocalLogin(userId: UUID, role: String) {
        UserDefaults.standard.set(userId.uuidString, forKey: "authToken")
        UserDefaults.standard.set(role, forKey: "lastRole")
        UserDefaults.standard.set(true, forKey: "isOnboardingComplete")
    }

    private static func runSelfAcceptCheck() async {
        UserDefaults.standard.set("started", forKey: "savariSmokeSelfAcceptStatus")
        UserDefaults.standard.removeObject(forKey: "savariSmokeSelfAcceptRideId")
        UserDefaults.standard.removeObject(forKey: "savariSmokeSelfAcceptAccepted")
        UserDefaults.standard.removeObject(forKey: "savariSmokeSelfAcceptError")
        print("[SMOKE] self_accept_check started")

        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id
            let userIdString = userId.uuidString
            let originalProfile = try? await SupabaseManager.shared.fetchProfile(for: userId)

            UserDefaults.standard.set(userIdString, forKey: "authToken")
            UserDefaults.standard.set("Driver", forKey: "lastRole")
            UserDefaults.standard.set(true, forKey: "isOnboardingComplete")

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
                print("[SMOKE][FAIL] self_accept_check could not create ride")
                UserDefaults.standard.set("failed_create_ride", forKey: "savariSmokeSelfAcceptStatus")
                return
            }

            UserDefaults.standard.set(rideId, forKey: "savariSmokeSelfAcceptRideId")
            print("[SMOKE] self_accept_check created ride \(rideId)")
            let accepted = await RideService.shared.acceptRide(rideId: rideId, driverId: userIdString)
            UserDefaults.standard.set(accepted, forKey: "savariSmokeSelfAcceptAccepted")
            UserDefaults.standard.set(accepted ? "failed_accepted_own_ride" : "passed_blocked_own_ride", forKey: "savariSmokeSelfAcceptStatus")
            print(accepted ? "[SMOKE][FAIL] self_accept_check accepted own ride" : "[SMOKE][PASS] self_accept_check blocked own ride")

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
            print("[SMOKE][FAIL] self_accept_check error: \(error.localizedDescription)")
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
            print("[SMOKE] self_accept_check cleaned ride \(rideId)")
        } catch {
            print("[SMOKE][WARN] self_accept_check cleanup failed: \(error.localizedDescription)")
        }
    }
}
#else
private enum SavariSmokeTestRunner {
    static func runIfRequested() {}
}
#endif
