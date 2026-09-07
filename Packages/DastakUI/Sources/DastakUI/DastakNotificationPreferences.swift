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
        await alertSettings().permission
    }

    static func alertSettings() async -> DastakNotificationSettings {
        #if os(iOS)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let permission: DastakNotificationPermissionState
        switch settings.authorizationStatus {
        case .notDetermined: permission = .notRequested
        case .authorized, .provisional, .ephemeral: permission = .enabled
        case .denied: permission = .disabled
        @unknown default: permission = .unavailable
        }
        return DastakNotificationSettings(
            permission: permission,
            alertsEnabled: settings.alertSetting == .enabled && settings.authorizationStatus != .provisional,
            soundEnabled: settings.soundSetting == .enabled
        )
        #else
        return DastakNotificationSettings(permission: .unavailable, alertsEnabled: false, soundEnabled: false)
        #endif
    }

    @discardableResult
    static func request(registerWithApple: Bool = true) async -> DastakNotificationPermissionState {
        #if os(iOS)
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )) == true
        if granted && registerWithApple {
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
