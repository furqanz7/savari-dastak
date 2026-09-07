import Foundation
#if os(iOS)
import UIKit
import UserNotifications
#endif

enum DastakNotificationPermissionState: Equatable {
    case notRequested
    case enabled
    case disabled
    case unavailable

    var title: String {
        switch self {
        case .notRequested: "Not set up"
        case .enabled: "On"
        case .disabled: "Off"
        case .unavailable: "Unavailable"
        }
    }
}

@MainActor
enum DastakNotificationPreferences {
    static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    static func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func status() async -> DastakNotificationPermissionState {
        #if os(iOS)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notRequested
        case .authorized, .provisional, .ephemeral: return .enabled
        case .denied: return .disabled
        @unknown default: return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    @discardableResult
    static func request() async -> DastakNotificationPermissionState {
        #if os(iOS)
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )) == true
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return await status()
        #else
        return .unavailable
        #endif
    }

    static func openSystemSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
