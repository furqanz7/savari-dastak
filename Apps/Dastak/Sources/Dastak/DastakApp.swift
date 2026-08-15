import DastakDomain
import DastakLaunchUI
import DastakUI
import Foundation
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
                DastakCustomerPartnerRoot(services: services)
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
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            DastakNotificationRoute.register(deviceToken: token)
        }
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
        guard let route = DastakNotificationRoute.route(
            from: response.notification.request.content.userInfo
        ) else { return }
        DastakNotificationRoute.open(type: route.type, id: route.id)
    }
}

@MainActor
enum DastakNotificationRoute {
    static let orderOpened = Notification.Name("dastak.notification.orderOpened")
    static let deviceTokenRegistered = Notification.Name("dastak.notification.deviceTokenRegistered")
    private static let pendingEntityTypeKey = "dastak.notification.pendingEntityType"
    private static let pendingEntityIDKey = "dastak.notification.pendingEntityID"

    nonisolated static func route(from payload: [AnyHashable: Any]) -> (type: String, id: String)? {
        if let entityType = payload["entityType"] as? String,
           let entityID = payload["entityId"] as? String,
           ["merchantOrder", "parcel"].contains(entityType),
           UUID(uuidString: entityID) != nil {
            return (entityType, entityID)
        }
        if let parcelID = payload["parcelId"] as? String, UUID(uuidString: parcelID) != nil {
            return ("parcel", parcelID)
        }
        if let orderID = payload["orderId"] as? String, UUID(uuidString: orderID) != nil {
            return ("merchantOrder", orderID)
        }
        return nil
    }

    static func register(deviceToken: String) {
        UserDefaults.standard.set(deviceToken, forKey: "dastak.apns.deviceToken")
        NotificationCenter.default.post(name: deviceTokenRegistered, object: nil)
    }

    static func open(type: String, id: String) {
        UserDefaults.standard.set(type, forKey: pendingEntityTypeKey)
        UserDefaults.standard.set(id, forKey: pendingEntityIDKey)
        NotificationCenter.default.post(
            name: orderOpened,
            object: nil,
            userInfo: ["entityType": type, "entityId": id]
        )
    }
}

protocol DeliveryPartnerAccessProviding: Sendable {
    func currentAccess() async throws -> DeliveryPartnerAccess
}

@MainActor
protocol DastakRootSelectionStoring {
    func load() -> DastakAppRoot?
    func save(_ root: DastakAppRoot)
}

@MainActor
private struct UserDefaultsDastakRootSelectionStore: DastakRootSelectionStoring {
    private let defaults: UserDefaults
    private let key = "dastak.last-active-root.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DastakAppRoot? {
        guard let rawValue = defaults.string(forKey: key),
              let root = DastakAppRoot(rawValue: rawValue),
              root == .customer || root == .deliveryPartner else {
            return nil
        }
        return root
    }

    func save(_ root: DastakAppRoot) {
        guard root == .customer || root == .deliveryPartner else { return }
        defaults.set(root.rawValue, forKey: key)
    }
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
    @Published private(set) var hasLoadedPartnerAccess = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedRoot: DastakAppRoot

    private let accessProvider: any DeliveryPartnerAccessProviding
    private let selectionStore: any DastakRootSelectionStoring

    convenience init(accessProvider: any DeliveryPartnerAccessProviding) {
        self.init(
            accessProvider: accessProvider,
            selectionStore: UserDefaultsDastakRootSelectionStore()
        )
    }

    init(
        accessProvider: any DeliveryPartnerAccessProviding,
        selectionStore: any DastakRootSelectionStoring
    ) {
        self.accessProvider = accessProvider
        self.selectionStore = selectionStore
        selectedRoot = selectionStore.load() ?? .customer
    }

    func refreshPartnerAccess() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let access = try await accessProvider.currentAccess()
            rootState.updateDeliveryPartnerAccess(access)
            if selectedRoot == .deliveryPartner, access == .approved {
                try? rootState.select(.deliveryPartner)
            }
            errorMessage = nil
        } catch {
            rootState.updateDeliveryPartnerAccess(.unavailable)
            errorMessage = "Delivery Partner access could not be refreshed."
        }
        hasLoadedPartnerAccess = true
    }

    func select(_ root: DastakAppRoot) {
        guard root == .customer || root == .deliveryPartner else {
            errorMessage = "This mode is not available for this account."
            return
        }
        selectedRoot = root
        selectionStore.save(root)
        if root == .customer || rootState.deliveryPartnerAccess == .approved {
            try? rootState.select(root)
        }
    }

    func openDeliveryPartner() async {
        await refreshPartnerAccess()
        select(.deliveryPartner)
    }
}

private struct DastakCustomerPartnerRoot: View {
    @StateObject private var model: DastakRootModel
    private let services: MarketplaceAuthenticatedServices

    init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        _model = StateObject(
            wrappedValue: DastakRootModel(
                accessProvider: LiveDeliveryPartnerAccessProvider(
                    client: SupabaseDeliveryPartnerClient(functions: services.functions)
                )
            )
        )
    }

    var body: some View {
        activeRoot
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                guard !model.hasLoadedPartnerAccess else { return }
                await model.refreshPartnerAccess()
            }
    }

    @ViewBuilder
    private var activeRoot: some View {
        switch model.selectedRoot {
        case .customer:
            DastakCustomerRootView(
                functions: services.functions,
                checkoutCustomerProvider: services.checkoutCustomer,
                accountIDProvider: services.accountID,
                deliveryPartnerAccess: model.rootState.deliveryPartnerAccess,
                isDeliveryPartnerAccessLoading: !model.hasLoadedPartnerAccess || model.isRefreshing,
                becomeDeliveryPartner: {
                    Task { await model.openDeliveryPartner() }
                }
            )
        case .deliveryPartner:
            VStack(spacing: 0) {
                HStack {
                    Button {
                        model.select(.customer)
                    } label: {
                        Label("Back to Dastak", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    if model.isRefreshing {
                        ProgressView()
                    }
                }
                .padding(.horizontal)
                .frame(minHeight: 52)

                if model.rootState.deliveryPartnerAccess == .approved {
                    DastakDeliveryPartnerRootView(services: services)
                } else {
                    DastakDeliveryPartnerAccessView(
                        access: model.rootState.deliveryPartnerAccess,
                        services: services,
                        onRefresh: { await model.refreshPartnerAccess() }
                    )
                }
            }
        case .merchant, .admin:
            EmptyView()
        }
    }
}
