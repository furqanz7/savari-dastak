import Foundation
import MarketplaceFoundation
import Supabase
import XCTest
@testable import MarketplaceInfrastructure

final class SessionReliabilityTests: XCTestCase {
    func testConfirmedRefreshFailuresRequireNewSignIn() {
        XCTAssertTrue(SupabaseSessionFailure.isConfirmedSessionLoss(AuthError.sessionMissing))
        for code: ErrorCode in [.sessionNotFound, .sessionExpired, .refreshTokenNotFound,
                                .refreshTokenAlreadyUsed, .userNotFound] {
            XCTAssertTrue(SupabaseSessionFailure.isConfirmedSessionLoss(authError(code, status: 400)))
        }
    }

    func testOutagesUnknownAuthErrorsAndGeneric401AreNotConfirmedSessionLoss() {
        for error: Error in [URLError(.notConnectedToInternet), CancellationError(),
                             authError(.sessionExpired, status: 500),
                             authError(ErrorCode("unexpected_failure"), status: 401),
                             authError(ErrorCode("over_request_rate_limit"), status: 429),
                             FunctionClientError.api(statusCode: 401, code: "authentication_required", message: "Denied")] {
            XCTAssertFalse(SupabaseSessionFailure.isConfirmedSessionLoss(error))
        }
    }

    func testRegistry401RefreshesOnceAndReusesRegistrationKey() async throws {
        let client = SessionProbe([.failure(rejected), .success(AccountSessionCollection(sessions: []))])
        let refresh = RefreshProbe()
        try await DastakSessionVerifier.verify(client: client, device: device, refreshSession: { await refresh.run() })
        let keys = await client.keys()
        let refreshes = await refresh.count()
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.first, keys.last)
        XCTAssertEqual(refreshes, 1)
    }

    func testRepeatedRegistry401RemainsBlockedNotInfiniteRetry() async {
        let client = SessionProbe([.failure(rejected), .failure(rejected)])
        let refresh = RefreshProbe()
        do {
            try await DastakSessionVerifier.verify(client: client, device: device, refreshSession: { await refresh.run() })
            XCTFail("Unverified session cannot enter app")
        } catch let error as FunctionClientError {
            XCTAssertEqual(error, rejected)
        } catch { XCTFail("Unexpected error \(error)") }
        let keys = await client.keys()
        let refreshes = await refresh.count()
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(refreshes, 1)
    }

    func testOfflineRefreshDoesNotRetryRegistryOrConvertToMissing() async {
        let client = SessionProbe([.failure(rejected)])
        do {
            try await DastakSessionVerifier.verify(client: client, device: device, refreshSession: { throw URLError(.timedOut) })
            XCTFail("Expected temporary failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch { XCTFail("Unexpected error \(error)") }
        let keys = await client.keys()
        XCTAssertEqual(keys.count, 1)
    }

    func testMissingSessionAndRegistryOutageDoNotForceTokenRefresh() async {
        for error: Error in [FunctionClientError.authenticationRequired, URLError(.notConnectedToInternet),
                             FunctionClientError.api(statusCode: 503, code: nil, message: "Unavailable")] {
            let client = SessionProbe([.failure(error)])
            let refresh = RefreshProbe()
            do {
                try await DastakSessionVerifier.verify(client: client, device: device, refreshSession: { await refresh.run() })
                XCTFail("Expected failure")
            } catch {}
            let refreshes = await refresh.count()
            let keys = await client.keys()
            XCTAssertEqual(refreshes, 0)
            XCTAssertEqual(keys.count, 1)
        }
    }

    @MainActor
    func testRegistryRejectionPreservesSignInAndRetryCanRecover() async {
        let client = FakeAuthenticationClient(restoredRoute: .active)
        let coordinator = AuthenticationCoordinator(client: client)
        await coordinator.restore()
        coordinator.sessionVerificationFailed(rejected)
        XCTAssertTrue(coordinator.restorationFailed)
        XCTAssertEqual(coordinator.route, .active)
        await coordinator.restore()
        XCTAssertFalse(coordinator.restorationFailed)
        XCTAssertEqual(coordinator.route, .active)
    }

    @MainActor
    func testConfirmedMissingSessionReturnsToSignIn() async {
        let coordinator = AuthenticationCoordinator(client: FakeAuthenticationClient(restoredRoute: .active))
        await coordinator.restore()
        coordinator.sessionVerificationFailed(FunctionClientError.authenticationRequired)
        XCTAssertFalse(coordinator.restorationFailed)
        XCTAssertEqual(coordinator.route, .signedOut)
    }

    @MainActor
    func testLateRestoreCannotUndoExplicitSignOut() async throws {
        let client = DelayedRestoreClient()
        let coordinator = AuthenticationCoordinator(client: client)
        let pending = Task { await coordinator.restore() }
        await client.waitUntilRestoring()
        try await coordinator.signOut()
        await client.release()
        await pending.value
        XCTAssertEqual(coordinator.route, .signedOut)
        XCTAssertFalse(coordinator.isRestoring)
        XCTAssertFalse(coordinator.restorationFailed)
    }

    @MainActor
    func testLateRestoreCannotReplaceNewerRoleDecision() async {
        let client = DelayedRestoreClient()
        let coordinator = AuthenticationCoordinator(client: client)
        let pending = Task { await coordinator.restore() }
        await client.waitUntilRestoring()
        await coordinator.restore()
        await client.release()
        await pending.value
        XCTAssertEqual(coordinator.route, .suspended)
        XCTAssertFalse(coordinator.isRestoring)
    }

    private var device: AccountSessionDevice { .init(deviceName: "Test", platform: "ios", appName: "Dastak") }
    private var rejected: FunctionClientError { .api(statusCode: 401, code: "authentication_required", message: "Denied") }
    private func authError(_ code: ErrorCode, status: Int) -> AuthError {
        .api(message: "Test", errorCode: code, underlyingData: Data(), underlyingResponse:
            HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private actor RefreshProbe {
    private var calls = 0
    func run() { calls += 1 }
    func count() -> Int { calls }
}

private actor SessionProbe: AccountSessionClient {
    private var outcomes: [Result<AccountSessionCollection, Error>]
    private var requestKeys: [IdempotencyKey] = []
    init(_ outcomes: [Result<AccountSessionCollection, Error>]) { self.outcomes = outcomes }
    func snapshot(device: AccountSessionDevice, idempotencyKey: IdempotencyKey) throws -> AccountSessionCollection {
        requestKeys.append(idempotencyKey)
        return try outcomes.removeFirst().get()
    }
    func keys() -> [IdempotencyKey] { requestKeys }
    func signOutOthers(device: AccountSessionDevice, idempotencyKey: IdempotencyKey) throws -> AccountSessionCollection { throw FunctionClientError.invalidResponse }
    func revoke(sessionID: UUID, idempotencyKey: IdempotencyKey) throws -> AccountSessionCollection { throw FunctionClientError.invalidResponse }
    func endCurrent(idempotencyKey: IdempotencyKey) throws { throw FunctionClientError.invalidResponse }
}

private actor DelayedRestoreClient: AuthenticationClient {
    private var pending: CheckedContinuation<AccountRoute, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var calls = 0
    func restoreAccount() async -> AccountRoute {
        calls += 1
        if calls > 1 { return .suspended }
        return await withCheckedContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
    }
    func waitUntilRestoring() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { pending?.resume(returning: .active); pending = nil }
    func signInWithApple(identityToken: String, nonce: String) async throws {}
    func signInWithGoogle(idToken: String) async throws {}
    func signInWithGoogle(redirectTo: URL) async throws {}
    func bootstrapAccount(displayName: String, phoneNumber: String, key: IdempotencyKey) async throws {}
    func signOut() async throws {}
}
