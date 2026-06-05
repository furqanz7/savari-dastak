//
//  Savari.swift
//  Savari
//
//  Created by Furqan on 07/10/25.
//

import SwiftUI
import GoogleSignIn
import UIKit

@main
struct Savari: App {
    @AppStorage("authToken") var authToken: String?

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "CLIENT_ID") as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            SavariLog.debug("✅ Google Client ID configured: \(clientID)")
        } else {
            SavariLog.debug("❌ Failed to find CLIENT_ID in Info.plist")
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
