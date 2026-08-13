import DastakDomain
import DastakUI
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI
import UIKit
import UserNotifications

@main
struct DastakApp: App {
    @UIApplicationDelegateAdaptor(DastakNotificationDelegate.self) private var notificationDelegate

    var body: some Scene {
        WindowGroup {
            DastakLaunchView(variant: .customerAndPartner) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-DastakUIPreview") {
                    DastakCustomerRootView(preview: true)
                } else {
                    authenticatedRoot
                }
                #else
                authenticatedRoot
                #endif
            }
        }
    }

    private var authenticatedRoot: some View {
        MarketplaceAuthenticationShell(
            applicationName: "Dastak",
            product: .dastak,
            requiredAccess: .dastakCustomer,
            showsPersistentSignOut: false,
            authenticatedServicesContent: { services in
                DastakCustomerPartnerRoot(
                    functionClient: services.functions,
                    checkoutCustomerProvider: services.checkoutCustomer
                )
            },
            restrictedContent: { _, _ in EmptyView() }
        )
    }
}

final class DastakNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            guard granted == true else { return }
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "dastak.apns.deviceToken")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.removeObject(forKey: "dastak.apns.deviceToken")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let orderID = response.notification.request.content.userInfo["orderId"] as? String,
              UUID(uuidString: orderID) != nil else { return }
        DastakNotificationRoute.openOrder(orderID)
    }
}

enum DastakNotificationRoute {
    static let orderOpened = Notification.Name("dastak.notification.orderOpened")
    private static let pendingOrderIDKey = "dastak.notification.pendingOrderID"

    static func openOrder(_ orderID: String) {
        UserDefaults.standard.set(orderID, forKey: pendingOrderIDKey)
        NotificationCenter.default.post(name: orderOpened, object: orderID)
    }

}

protocol DeliveryPartnerAccessProviding: Sendable {
    func currentAccess() async throws -> DeliveryPartnerAccess
}

private struct LiveDeliveryPartnerAccessProvider: DeliveryPartnerAccessProviding {
    let client: any DeliveryPartnerClient

    func currentAccess() async throws -> DeliveryPartnerAccess {
        let key = IdempotencyKey(rawValue: UUID().uuidString)!
        let snapshot = try await client.selfSnapshot(idempotencyKey: key)

        switch snapshot.onboardingState {
        case .notApplied:
            return .notApplied
        case .pending:
            return .pending
        case .approved:
            return .approved
        case .rejected:
            return .rejected
        }
    }
}

@MainActor
final class DastakRootModel: ObservableObject {
    @Published private(set) var rootState = DastakAppRootState(
        application: .customerAndPartner
    )
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let accessProvider: any DeliveryPartnerAccessProviding

    init(accessProvider: any DeliveryPartnerAccessProviding) {
        self.accessProvider = accessProvider
    }

    func refreshPartnerAccess() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            rootState.updateDeliveryPartnerAccess(
                try await accessProvider.currentAccess()
            )
            errorMessage = nil
        } catch {
            rootState.updateDeliveryPartnerAccess(.unavailable)
            errorMessage = "Delivery Partner access could not be refreshed."
        }
    }

    func select(_ root: DastakAppRoot) {
        do {
            try rootState.select(root)
        } catch {
            errorMessage = "This mode is not available for this account."
        }
    }
}

private struct DastakCustomerPartnerRoot: View {
    @StateObject private var model: DastakRootModel
    private let functionClient: any FunctionClient
    private let checkoutCustomerProvider: @Sendable () async throws -> MarketplaceCheckoutCustomer?

    init(
        functionClient: any FunctionClient,
        checkoutCustomerProvider: @escaping @Sendable () async throws -> MarketplaceCheckoutCustomer?
    ) {
        self.functionClient = functionClient
        self.checkoutCustomerProvider = checkoutCustomerProvider
        _model = StateObject(
            wrappedValue: DastakRootModel(
                accessProvider: LiveDeliveryPartnerAccessProvider(
                    client: SupabaseDeliveryPartnerClient(functions: functionClient)
                )
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.rootState.availableRoots.count > 1 {
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { model.rootState.activeRoot },
                        set: { model.select($0) }
                    )
                ) {
                    Text("Customer").tag(DastakAppRoot.customer)
                    Text("Delivery Partner").tag(DastakAppRoot.deliveryPartner)
                }
                .pickerStyle(.segmented)
                .padding()
            }

            activeRoot
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isRefreshing {
                ProgressView()
                    .padding(.bottom)
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .task {
            await model.refreshPartnerAccess()
        }
    }

    @ViewBuilder
    private var activeRoot: some View {
        switch model.rootState.activeRoot {
        case .customer:
            DastakCustomerRootView(
                functions: functionClient,
                checkoutCustomerProvider: checkoutCustomerProvider
            )
        case .deliveryPartner:
            DastakDeliveryPartnerRootView(functions: functionClient)
        case .merchant, .admin:
            EmptyView()
        }
    }
}
