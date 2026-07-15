//
//  SavariSmokeTestRunner.swift
//  Savari
//

import Foundation
import Supabase
import Auth
import PostgREST

#if DEBUG && targetEnvironment(simulator)
@MainActor
enum SavariSmokeTestRunner {
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

    static func currentUserId() async throws -> UUID {
        let session = try await SupabaseManager.shared.client.auth.session
        return session.user.id
    }

    static func setLocalLogin(userId: UUID, role: String) {
        SavariSessionStore.setLoggedIn(userId: userId.uuidString, role: role)
    }
}
#else
enum SavariSmokeTestRunner {
    static func runIfRequested() {}
}
#endif
