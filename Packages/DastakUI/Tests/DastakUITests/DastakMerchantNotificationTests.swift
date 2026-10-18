import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantNotificationTests: XCTestCase {
    func testDevelopmentSignedReleaseUsesSandboxInMerchantRegistration() async throws {
        let functions = NotificationFunctionsStub(), system = NotificationSystemStub()
        let profile = try PropertyListSerialization.data(fromPropertyList:
            ["Entitlements": ["aps-environment": "development"]], format: .xml, options: 0)
        system.environment = DastakAPNSEnvironment.resolve(embeddedProfile: profile)?.rawValue
        let alerts = controller(system, functions: functions)
        await alerts.receiveDeviceToken("fresh-development-token")
        let calls = await functions.calls
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(calls.first)) as? [String: String])
        XCTAssertEqual(body["apnsEnvironment"], "sandbox")
        XCTAssertEqual(body["applicationId"], "com.dastak.merchant")
        XCTAssertEqual(alerts.registration, .registered)
    }

    func testDistributedBuildRegistersProductionEnvironment() async throws {
        let functions = NotificationFunctionsStub(), system = NotificationSystemStub()
        system.environment = DastakAPNSEnvironment.resolve(embeddedProfile: nil)?.rawValue
        let alerts = controller(system, functions: functions)
        await alerts.receiveDeviceToken("fresh-distribution-token")
        let calls = await functions.calls
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(calls.first)) as? [String: String])
        XCTAssertEqual(body["apnsEnvironment"], "production")
        XCTAssertEqual(alerts.registration, .registered)
    }

    func testUnknownSigningEnvironmentDoesNotSendOrConfirmDeviceRegistration() async {
        let functions = NotificationFunctionsStub(), system = NotificationSystemStub()
        system.environment = nil
        let alerts = controller(system, functions: functions)
        await alerts.receiveDeviceToken("token-must-not-be-sent")
        let calls = await functions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(alerts.registration, .failed)
        XCTAssertFalse(alerts.isConnecting)
        XCTAssertNotNil(alerts.failureReason)
    }

    func testSharedCustomerDeliveryAppRegistersFreshTokenWithCorrectTopic() async throws {
        let functions = NotificationFunctionsStub()
        let system = NotificationSystemStub()
        system.currentSettings.permission = .notRequested
        let alerts = DastakMerchantNotifications(functions: functions, system: system.dependencies, applicationID: "com.dastak.app")
        await alerts.refresh()
        system.currentSettings.permission = .enabled // Permission granted by onboarding.
        await alerts.receiveDeviceToken("new-token")
        XCTAssertEqual(alerts.registration, .registered)
        XCTAssertFalse(alerts.needsAttention)
        let calls = await functions.calls
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(calls.first)) as? [String: String])
        XCTAssertEqual(body["applicationId"], "com.dastak.app")
        XCTAssertEqual(body["apnsEnvironment"], "sandbox")
    }

    func testLateTokenDoesNotRegisterAfterPermissionIsRevoked() async {
        let functions = NotificationFunctionsStub()
        let system = NotificationSystemStub()
        let alerts = controller(system, functions: functions)
        await alerts.refresh()
        system.currentSettings.permission = .disabled
        await alerts.receiveDeviceToken("late-token")
        XCTAssertEqual(alerts.registration, .notRegistered)
        let calls = await functions.calls
        XCTAssertTrue(calls.isEmpty)
    }
    func testPermissionAloneDoesNotHideRegistrationPrompt() async {
        let system = NotificationSystemStub()
        let alerts = controller(system)
        await alerts.refresh()
        XCTAssertEqual(alerts.registration, .waitingForDevice)
        XCTAssertTrue(alerts.needsAttention)
        XCTAssertEqual(system.appleRequests, 1)
    }

    func testAppleFailureAndMissingCallbackStayVisibleAndCanRetry() async throws {
        let system = NotificationSystemStub()
        let alerts = controller(system, timeout: .milliseconds(1))
        await alerts.refresh()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(alerts.registration, .failed)
        XCTAssertEqual(alerts.actionTitle, "Retry")
        await alerts.enable()
        XCTAssertEqual(system.appleRequests, 2)
        alerts.registrationFailed()
        XCTAssertTrue(alerts.needsAttention)
        XCTAssertFalse(alerts.isConnecting)
    }

    func testRegistrationSendsMerchantTopicAndEnvironmentAndRebindsSameToken() async throws {
        let functions = NotificationFunctionsStub()
        let system = NotificationSystemStub()
        let alerts = controller(system, functions: functions)
        await alerts.refresh()
        await alerts.receiveDeviceToken("fresh-apple-token")
        XCTAssertEqual(alerts.registration, .registered)
        XCTAssertFalse(alerts.needsAttention)
        await alerts.refresh() // Foreground after an account switch must not skip this token.
        await alerts.receiveDeviceToken("fresh-apple-token")
        let calls = await functions.calls
        XCTAssertEqual(calls.count, 2)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(calls.first)) as? [String: String])
        XCTAssertEqual(body["applicationId"], "com.dastak.merchant")
        XCTAssertEqual(body["apnsEnvironment"], "sandbox")
        XCTAssertNil(body["accountId"], "The authenticated server chooses the current account.")
    }

    func testServerFailureAndFalseAcknowledgmentNeverReportRegistered() async {
        let functions = NotificationFunctionsStub()
        let alerts = controller(NotificationSystemStub(), functions: functions)
        await alerts.refresh()
        await functions.setResponse(.failure)
        await alerts.receiveDeviceToken("token")
        XCTAssertEqual(alerts.registration, .failed)
        await functions.setResponse(.notRegistered)
        await alerts.receiveDeviceToken("token")
        XCTAssertEqual(alerts.registration, .failed)
        XCTAssertTrue(alerts.needsAttention)
    }

    func testMutedAlertsDirectToSettingsEvenAfterRegistrationSucceeds() async {
        let system = NotificationSystemStub()
        system.currentSettings.soundEnabled = false
        let alerts = controller(system)
        await alerts.refresh()
        await alerts.receiveDeviceToken("token")
        XCTAssertEqual(alerts.registration, .registered)
        XCTAssertTrue(alerts.needsAttention)
        XCTAssertEqual(alerts.actionTitle, "Settings")
        await alerts.enable()
        XCTAssertEqual(system.settingsOpened, 1)
    }

    func testDeniedPermissionDoesNotTryToRegister() async {
        let system = NotificationSystemStub()
        system.currentSettings.permission = .disabled
        let alerts = controller(system)
        await alerts.refresh()
        XCTAssertEqual(system.appleRequests, 0)
        XCTAssertTrue(alerts.needsSettings)
        await alerts.enable()
        XCTAssertEqual(system.settingsOpened, 1)
    }

    func testPermissionRequestThenFreshRegistration() async {
        let system = NotificationSystemStub()
        system.currentSettings.permission = .notRequested
        let alerts = controller(system)
        await alerts.refresh()
        XCTAssertEqual(alerts.actionTitle, "Enable")
        await alerts.enable()
        XCTAssertEqual(system.permissionRequests, 1)
        XCTAssertEqual(system.appleRequests, 1)
        XCTAssertEqual(alerts.registration, .waitingForDevice)
    }

    func testServerTimeoutReleasesConnectingStateAndLateResponseCannotConfirmRegistration() async {
        let functions = NotificationFunctionsStub(), system = NotificationSystemStub()
        let alerts = DastakMerchantNotifications(functions: functions, system: system.dependencies,
            requestTimeout: .milliseconds(50))
        await functions.hold()
        let read = Task { await alerts.receiveDeviceToken("fresh-token") }
        await functions.wait(); await read.value
        XCTAssertEqual(alerts.registration, .failed); XCTAssertFalse(alerts.isConnecting)
        XCTAssertNotNil(alerts.failureReason)
        await functions.release()
        XCTAssertEqual(alerts.registration, .failed)
        await alerts.receiveDeviceToken("retry-token")
        XCTAssertEqual(alerts.registration, .registered)
    }
    func testAutomaticRecoveryIsBoundedAndUsesFreshAppleCallbacksInsteadOfCachedTokens() async {
        let functions = NotificationFunctionsStub(), system = NotificationSystemStub()
        let alerts = controller(system, functions: functions)
        await alerts.refresh(); alerts.registrationFailed()
        let future = Date().addingTimeInterval(500)
        for _ in 0..<5 {
            await alerts.recoverIfNeeded(now: future)
            alerts.registrationFailed()
        }
        XCTAssertEqual(system.appleRequests, 4, "One initial attempt plus at most three automatic recoveries")
        let calls = await functions.calls; XCTAssertTrue(calls.isEmpty, "Retry asks Apple; no cached token is registered")
        await alerts.enable(); XCTAssertEqual(system.appleRequests, 5, "Manual Retry starts a new bounded cycle")
    }
    func testAutomaticRecoveryRespectsBackoffAndDoesNotPromptForDeniedPermission() async {
        let system = NotificationSystemStub(), alerts = controller(system)
        await alerts.refresh(); alerts.registrationFailed()
        await alerts.recoverIfNeeded(now: .now)
        XCTAssertEqual(system.appleRequests, 1)
        system.currentSettings.permission = .disabled
        await alerts.recoverIfNeeded(now: Date().addingTimeInterval(500))
        XCTAssertEqual(alerts.registration, .notRegistered)
        XCTAssertEqual(system.appleRequests, 1); XCTAssertEqual(system.permissionRequests, 0)
    }
    func testDuplicateTokenCallbacksCoalesceAndOldInFlightRegistrationCannotWin() async {
        let functions = NotificationFunctionsStub(), alerts = controller(NotificationSystemStub(), functions: functions)
        await functions.hold()
        let first = Task { await alerts.receiveDeviceToken("same-token") }
        await functions.wait()
        await alerts.receiveDeviceToken("same-token")
        let firstCalls = await functions.calls; XCTAssertEqual(firstCalls.count, 1)
        alerts.registrationFailed()
        await functions.release(); await first.value
        XCTAssertEqual(alerts.registration, .failed)
    }
    func testAccountChangeDuringRegistrationNeverReportsCurrentAccountLinked() async {
        let functions = NotificationFunctionsStub(), system = NotificationSystemStub(), identity = MerchantJournalTestIdentity()
        let alerts = DastakMerchantNotifications(functions: functions, system: system.dependencies,
            accountIDProvider: { await identity.id })
        await functions.hold()
        let read = Task { await alerts.receiveDeviceToken("token") }
        await functions.wait(); await identity.change(); await functions.release(); await read.value
        XCTAssertEqual(alerts.registration, .failed); XCTAssertTrue(alerts.needsAttention)
    }
    func testSettingsReadTimeoutAndConcurrentRefreshDoNotLeaveSetupBlocked() async {
        let functions = NotificationFunctionsStub(), system = NotificationSystemStub(), gate = NotificationSettingsGate()
        system.settingsLoader = { await gate.load() }
        let alerts = DastakMerchantNotifications(functions: functions, system: system.dependencies,
            requestTimeout: .milliseconds(50))
        let read = Task { await alerts.refresh() }
        await gate.wait(); await alerts.refresh(); await read.value
        XCTAssertEqual(alerts.registration, .failed); XCTAssertFalse(alerts.isConnecting)
        XCTAssertEqual(system.appleRequests, 0)
        await gate.release(); system.settingsLoader = nil
        await alerts.refresh(); XCTAssertEqual(alerts.registration, .waitingForDevice)
    }

    private func controller(_ system: NotificationSystemStub,
                            functions: NotificationFunctionsStub = .init(),
                            timeout: Duration = .seconds(15)) -> DastakMerchantNotifications {
        DastakMerchantNotifications(functions: functions, system: system.dependencies, registrationTimeout: timeout)
    }
}

@MainActor
private final class NotificationSystemStub {
    var environment: String? = "sandbox"
    var currentSettings = DastakNotificationSettings(permission: .enabled, alertsEnabled: true, soundEnabled: true)
    var appleRequests = 0
    var settingsOpened = 0
    var permissionRequests = 0
    var settingsLoader: (@MainActor @Sendable () async -> DastakNotificationSettings)?
    var dependencies: DastakMerchantNotificationSystem {
        .init(settings: { if let loader = self.settingsLoader { return await loader() }; return self.currentSettings }, requestPermission: {
            self.permissionRequests += 1
            self.currentSettings.permission = .enabled
        }, registerWithApple: { self.appleRequests += 1 }, openSettings: { self.settingsOpened += 1 }, environment: self.environment)
    }
}

private actor NotificationFunctionsStub: FunctionClient {
    enum Response { case success, failure, notRegistered }
    var calls: [Data] = []
    private var response: Response = .success
    private var holding = false
    private var continuation: CheckedContinuation<Void, Never>?, started: CheckedContinuation<Void, Never>?
    func hold() { holding = true }
    func wait() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func release() { continuation?.resume(); continuation = nil }
    func setResponse(_ response: Response) { self.response = response }
    func invoke<Request: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        calls.append(try JSONEncoder().encode(request))
        if holding { holding = false; await withCheckedContinuation { continuation = $0; started?.resume(); started = nil } }
        if response == .failure { throw URLError(.notConnectedToInternet) }
        return try JSONDecoder().decode(Result.self, from: Data(
            (response == .success ? "{\"registered\":true}" : "{\"registered\":false}").utf8
        ))
    }
}

private actor NotificationSettingsGate {
    private var continuation: CheckedContinuation<DastakNotificationSettings, Never>?, started: CheckedContinuation<Void, Never>?
    func load() async -> DastakNotificationSettings {
        await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
    }
    func wait() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func release() { continuation?.resume(returning: .init(permission: .enabled, alertsEnabled: true, soundEnabled: true)); continuation = nil }
}
