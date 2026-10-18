import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakNotificationSettings: Equatable, Sendable {
    var permission: DastakNotificationPermissionState
    var alertsEnabled: Bool
    var soundEnabled: Bool
}

@MainActor
struct DastakMerchantNotificationSystem {
    var settings: @MainActor @Sendable () async -> DastakNotificationSettings
    var requestPermission: @MainActor @Sendable () async -> Void
    var registerWithApple: @MainActor @Sendable () -> Void
    var openSettings: @MainActor @Sendable () -> Void
    var environment: String?

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
    @Published private(set) var failureReason: String?
    private let system: DastakMerchantNotificationSystem
    private let client: SupabaseDastakDeviceTokenClient
    private let registrationTimeout: Duration
    private let applicationID: String
    private var timeoutTask: Task<Void, Never>?
    private var attempt = UUID()
    private var checkingSettings = false
    private var registeringToken: String?
    private var automaticRetries = 0
    private var retryAt: Date?
    private let requestTimeout: Duration
    private let accountIDProvider: (@Sendable () async throws -> UUID)?

    init(functions: any FunctionClient, system: DastakMerchantNotificationSystem = .live,
         registrationTimeout: Duration = .seconds(15), applicationID: String = "com.dastak.merchant",
         requestTimeout: Duration = .seconds(12), accountIDProvider: (@Sendable () async throws -> UUID)? = nil) {
        self.client = SupabaseDastakDeviceTokenClient(functions: functions)
        self.system = system
        self.registrationTimeout = registrationTimeout
        self.applicationID = applicationID
        self.requestTimeout = requestTimeout
        self.accountIDProvider = accountIDProvider
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
        if let failureReason, registration == .failed { return failureReason }
        if settings.permission != .enabled { return "Allow notifications for new requests, even outside the app." }
        if isConnecting { return "Linking this device to your signed-in account." }
        return failureReason ?? "Orders still update here. Reconnect alerts for background notifications."
    }
    var actionTitle: String {
        if needsSettings { return "Settings" }
        return settings.permission == .enabled ? "Retry" : "Enable"
    }

    func refresh() async {
        await refresh(resetRecovery: true)
    }

    private func refresh(resetRecovery: Bool) async {
        guard !checkingSettings, !isConnecting else { return }
        if resetRecovery { automaticRetries = 0; retryAt = nil }
        checkingSettings = true
        defer { checkingSettings = false }
        let check = UUID(); attempt = check
        do {
            let value = try await MarketplaceRequestDeadline.run(after: requestTimeout) { [system] in await system.settings() }
            guard attempt == check else { return }
            settings = value
        } catch {
            guard attempt == check else { return }
            fail("Notification settings could not be checked. Retry or open iOS Settings."); return
        }
        guard settings.permission == .enabled else {
            attempt = UUID()
            timeoutTask?.cancel()
            registration = .notRegistered
            failureReason = nil; retryAt = nil
            return
        }
        guard !isConnecting else { return }
        // Register on every foreground/account entry. Never assume that a token
        // cached by a previous signed-in account is still registered to this one.
        let currentAttempt = UUID()
        attempt = currentAttempt
        registration = .waitingForDevice
        failureReason = nil
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, registrationTimeout] in
            do { try await Task.sleep(for: registrationTimeout) } catch { return }
            guard let self, self.attempt == currentAttempt, self.registration == .waitingForDevice else { return }
            self.fail("Apple did not return a device token in time. Keep the app open and retry.")
        }
        system.registerWithApple()
    }

    func receiveDeviceToken(_ token: String) async {
        guard !(registration == .registering && registeringToken == token) else { return }
        timeoutTask?.cancel()
        let currentAttempt = UUID()
        attempt = currentAttempt
        guard !token.isEmpty, token.count <= 512 else { fail("Apple returned an invalid device token. Retry notification setup."); return }
        guard let environment = system.environment else {
            fail("This app's push signing environment could not be verified. Update the app or retry notification setup.")
            return
        }
        registration = .registering
        registeringToken = token
        defer { if attempt == currentAttempt { registeringToken = nil } }
        do {
            let result = try await MarketplaceRequestDeadline.run(after: requestTimeout) { [system, client, applicationID, accountIDProvider] in
                let settings = await system.settings()
                guard settings.permission == .enabled else { return (settings, false) }
                let actor = try await accountIDProvider?()
                let registered = try await client.register(token: token, applicationId: applicationID,
                apnsEnvironment: environment, idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!)
                if let actor, try await accountIDProvider?() != actor { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                return (settings, registered)
            }
            guard attempt == currentAttempt else { return }
            settings = result.0
            guard settings.permission == .enabled else { registration = .notRegistered; retryAt = nil; return }
            if result.1 {
                registration = .registered; failureReason = nil; automaticRetries = 0; retryAt = nil
            } else { fail("The server did not confirm this device registration. Orders remain available; retry background alerts.") }
        } catch {
            guard attempt == currentAttempt else { return }
            fail("This device could not be linked to the current account. Check the connection and session, then retry alerts.")
        }
    }

    func registrationFailed() {
        timeoutTask?.cancel()
        attempt = UUID()
        registeringToken = nil
        fail("Apple could not register this device. Check the connection and retry alerts.")
    }

    private func fail(_ message: String) {
        registration = .failed; failureReason = message
        retryAt = Date().addingTimeInterval(automaticRetries == 0 ? 5 : automaticRetries == 1 ? 15 : 45)
    }

    /// Called only by the Merchant foreground loop. No cached token is replayed
    /// across accounts: every recovery asks Apple for a fresh callback.
    func recoverIfNeeded(now: Date = .now) async {
        guard registration == .failed, !checkingSettings, automaticRetries < 3,
              let retryAt, now >= retryAt else { return }
        automaticRetries += 1
        await refresh(resetRecovery: false)
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
