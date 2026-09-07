import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantNotificationTests: XCTestCase {
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

    private func controller(_ system: NotificationSystemStub,
                            functions: NotificationFunctionsStub = .init(),
                            timeout: Duration = .seconds(15)) -> DastakMerchantNotifications {
        DastakMerchantNotifications(functions: functions, system: system.dependencies, registrationTimeout: timeout)
    }
}

@MainActor
private final class NotificationSystemStub {
    var currentSettings = DastakNotificationSettings(permission: .enabled, alertsEnabled: true, soundEnabled: true)
    var appleRequests = 0
    var settingsOpened = 0
    var permissionRequests = 0
    var dependencies: DastakMerchantNotificationSystem {
        .init(settings: { self.currentSettings }, requestPermission: {
            self.permissionRequests += 1
            self.currentSettings.permission = .enabled
        }, registerWithApple: { self.appleRequests += 1 }, openSettings: { self.settingsOpened += 1 }, environment: "sandbox")
    }
}

private actor NotificationFunctionsStub: FunctionClient {
    enum Response { case success, failure, notRegistered }
    var calls: [Data] = []
    private var response: Response = .success
    func setResponse(_ response: Response) { self.response = response }
    func invoke<Request: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        calls.append(try JSONEncoder().encode(request))
        if response == .failure { throw URLError(.notConnectedToInternet) }
        return try JSONDecoder().decode(Result.self, from: Data(
            (response == .success ? "{\"registered\":true}" : "{\"registered\":false}").utf8
        ))
    }
}
