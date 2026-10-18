import DastakLaunchUI
import DastakUI
import MarketplaceInfrastructure
import SwiftUI
import UIKit
import UserNotifications

@main
struct DastakMerchantApp: App {
    @UIApplicationDelegateAdaptor(MerchantNotificationDelegate.self) private var notificationDelegate
    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-DastakMerchantDesignPreview") {
                DastakMerchantDesignPreview()
            } else { workspace }
            #else
            workspace
            #endif
        }
    }
    private var workspace: some View {
            DastakLaunchView(variant: .merchant) {
                MarketplaceAuthenticationShell(
                    applicationName: "Dastak Merchant",
                    product: .dastak,
                    requiredAccess: .dastakMerchant,
                    showsPersistentSignOut: false
                ) { services in
                    DastakMerchantRootView(services: services)
                } restrictedContent: { route, services in
                    DastakMerchantAccessView(route: route, services: services)
                }
            }
    }
}

final class MerchantNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let notificationInbox = DastakNotificationInbox()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        notificationInbox.clear()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        notificationInbox.clear()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.removeObject(forKey: "dastak.merchant.apns.deviceToken")
        NotificationCenter.default.post(name: Notification.Name("dastak.merchant.deviceTokenRegistered"), object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.removeObject(forKey: "dastak.merchant.apns.deviceToken")
        NotificationCenter.default.post(name: Notification.Name("dastak.merchant.deviceTokenRegistrationFailed"), object: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notificationInbox.clear()
        NotificationCenter.default.post(name: Notification.Name("dastak.merchant.ordersChanged"), object: nil)
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        notificationInbox.clear()
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        // A validated, short-lived hint survives cold launch/sign-in. No order
        // action is executed here and payload fields are never authority.
        await MainActor.run {
            _ = DastakMerchantNotificationInbox().receive(payload: response.notification.request.content.userInfo,
                identifier: response.notification.request.identifier)
        }
    }
}
