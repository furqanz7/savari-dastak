import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakNotificationSettings: Equatable {
    var permission: DastakNotificationPermissionState
    var alertsEnabled: Bool
    var soundEnabled: Bool
}

@MainActor
struct DastakMerchantNotificationSystem {
    var settings: () async -> DastakNotificationSettings
    var requestPermission: () async -> Void
    var registerWithApple: () -> Void
    var openSettings: () -> Void
    var environment: String

    static var live: Self {
        Self(
            settings: { await DastakNotificationPreferences.alertSettings() },
            requestPermission: { _ = await DastakNotificationPreferences.request(registerWithApple: false) },
            registerWithApple: { DastakNotificationPreferences.registerForRemoteNotifications() },
            openSettings: { DastakNotificationPreferences.openSystemSettings() },
            environment: DastakNotificationPreferences.apnsEnvironment
        )
    }
}

/// Permission is not delivery registration. Only a fresh Apple callback followed
/// by a successful authenticated server registration can dismiss the setup prompt.
@MainActor
final class DastakMerchantNotifications: ObservableObject {
    enum Registration: Equatable { case notRegistered, waitingForDevice, registering, registered, failed }

    @Published private(set) var settings = DastakNotificationSettings(
        permission: .notRequested, alertsEnabled: false, soundEnabled: false
    )
    @Published private(set) var registration: Registration = .notRegistered
    private let system: DastakMerchantNotificationSystem
    private let client: SupabaseDastakDeviceTokenClient
    private let registrationTimeout: Duration
    private let applicationID: String
    private var timeoutTask: Task<Void, Never>?
    private var attempt = UUID()

    init(functions: any FunctionClient, system: DastakMerchantNotificationSystem = .live,
         registrationTimeout: Duration = .seconds(15), applicationID: String = "com.dastak.merchant") {
        self.client = SupabaseDastakDeviceTokenClient(functions: functions)
        self.system = system
        self.registrationTimeout = registrationTimeout
        self.applicationID = applicationID
    }

    var isConnecting: Bool { registration == .waitingForDevice || registration == .registering }
    var needsAttention: Bool {
        settings.permission != .unavailable &&
            (settings.permission != .enabled || !settings.alertsEnabled || !settings.soundEnabled || registration != .registered)
    }
    var needsSettings: Bool {
        settings.permission == .disabled ||
            (settings.permission == .enabled && (!settings.alertsEnabled || !settings.soundEnabled))
    }
    var title: String {
        if needsSettings { return "Order alerts are muted" }
        if settings.permission != .enabled { return "Hear every new order" }
        if isConnecting { return "Connecting order alerts…" }
        return "Order alerts need a retry"
    }
    var detail: String {
        if needsSettings { return "Turn on banners and sounds in iOS Settings." }
        if settings.permission != .enabled { return "Allow notifications for new requests, even outside the app." }
        if isConnecting { return "Linking this device to your signed-in account." }
        return "Orders still update here. Reconnect alerts for background notifications."
    }
    var actionTitle: String {
        if needsSettings { return "Settings" }
        return settings.permission == .enabled ? "Retry" : "Enable"
    }

    func refresh() async {
        settings = await system.settings()
        guard settings.permission == .enabled else {
            attempt = UUID()
            timeoutTask?.cancel()
            registration = .notRegistered
            return
        }
        guard !isConnecting else { return }
        // Register on every foreground/account entry. Never assume that a token
        // cached by a previous signed-in account is still registered to this one.
        let currentAttempt = UUID()
        attempt = currentAttempt
        registration = .waitingForDevice
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, registrationTimeout] in
            do { try await Task.sleep(for: registrationTimeout) } catch { return }
            guard let self, self.attempt == currentAttempt, self.registration == .waitingForDevice else { return }
            self.registration = .failed
        }
        system.registerWithApple()
    }

    func receiveDeviceToken(_ token: String) async {
        timeoutTask?.cancel()
        let currentAttempt = UUID()
        attempt = currentAttempt
        guard !token.isEmpty else { registration = .failed; return }
        registration = .registering
        settings = await system.settings()
        guard attempt == currentAttempt else { return }
        guard settings.permission == .enabled else { registration = .notRegistered; return }
        do {
            let registered = try await client.register(
                token: token, applicationId: applicationID,
                apnsEnvironment: system.environment,
                idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!
            )
            guard attempt == currentAttempt else { return }
            registration = registered ? .registered : .failed
        } catch {
            guard attempt == currentAttempt else { return }
            registration = .failed
        }
    }

    func registrationFailed() {
        timeoutTask?.cancel()
        attempt = UUID()
        registration = .failed
    }

    func enable() async {
        if needsSettings {
            system.openSettings()
        } else {
            if settings.permission != .enabled { await system.requestPermission() }
            await refresh()
        }
    }
}
