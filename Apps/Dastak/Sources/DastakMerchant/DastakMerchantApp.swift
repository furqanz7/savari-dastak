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
}

final class MerchantNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
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
        NotificationCenter.default.post(name: Notification.Name("dastak.merchant.ordersChanged"), object: nil)
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        // Persist cold-launch navigation until authentication has restored the workspace.
        UserDefaults.standard.set(true, forKey: "dastak.merchant.openOrders")
        NotificationCenter.default.post(name: Notification.Name("dastak.merchant.openOrders"), object: nil)
    }
}
