import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

@MainActor
final class AuthenticationCoordinatorTests: XCTestCase {
    func testRetryOfSameNormalizedPayloadReusesIdempotencyKeyAfterAmbiguousFailure() async throws {
        let client = ProfileSubmissionAuthenticationClient(
            bootstrapOutcomes: [.ambiguousFailure, .success],
            restoreRoutes: [.needsProfile, .needsProfile, .active]
        )
        let coordinator = AuthenticationCoordinator(client: client)
        await coordinator.restore()

        do {
            try await coordinator.completeProfile(
                displayName: "  Test   User\n",
                phoneNumber: " +919876543210 "
            )
            XCTFail("Expected the first response to be ambiguous")
        } catch let error as AuthenticationClientError {
            XCTAssertEqual(error, .bootstrapAmbiguousFailure)
        }

        try await coordinator.completeProfile(
            displayName: "Test User",
            phoneNumber: "+919876543210"
        )

        let requests = await client.recordedBootstrapRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].key, requests[1].key)
        XCTAssertEqual(requests[0].displayName, "Test User")
        XCTAssertEqual(requests[0].phoneNumber, "+919876543210")
        XCTAssertEqual(coordinator.route, .active)
    }

    func testRapidDuplicateSubmissionIsSuppressedWhileFirstRequestIsInFlight() async throws {
        let client = ProfileSubmissionAuthenticationClient(
            bootstrapOutcomes: [.success],
            restoreRoutes: [.needsProfile, .active],
            suspendFirstBootstrap: true
        )
        let coordinator = AuthenticationCoordinator(client: client)
        await coordinator.restore()

        let firstSubmission = Task { @MainActor in
            try await coordinator.completeProfile(
                displayName: "Test User",
                phoneNumber: "+919876543210"
            )
        }
        await client.waitUntilBootstrapStarts()

        XCTAssertTrue(coordinator.isProfileSubmissionInFlight)
        try await coordinator.completeProfile(
            displayName: "Test User",
            phoneNumber: "+919876543210"
        )
        let callCountWhileInFlight = await client.bootstrapCallCount()
        XCTAssertEqual(callCountWhileInFlight, 1)

        await client.resumeFirstBootstrap()
        try await firstSubmission.value

        XCTAssertFalse(coordinator.isProfileSubmissionInFlight)
        XCTAssertEqual(coordinator.route, .active)
    }

    func testChangingNormalizedPayloadCreatesNewIdempotencyKey() async throws {
        let client = ProfileSubmissionAuthenticationClient(
            bootstrapOutcomes: [.ambiguousFailure, .ambiguousFailure],
            restoreRoutes: [.needsProfile, .needsProfile, .needsProfile]
        )
        let coordinator = AuthenticationCoordinator(client: client)
        await coordinator.restore()

        for displayName in ["Test User", "Test User Two"] {
            do {
                try await coordinator.completeProfile(
                    displayName: displayName,
                    phoneNumber: "+919876543210"
                )
                XCTFail("Expected an ambiguous response")
            } catch let error as AuthenticationClientError {
                XCTAssertEqual(error, .bootstrapAmbiguousFailure)
            }
        }

        let requests = await client.recordedBootstrapRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertNotEqual(requests[0].key, requests[1].key)
    }

    func testAmbiguousFailureReconcilesServerSideSuccessToActive() async throws {
        let client = ProfileSubmissionAuthenticationClient(
            bootstrapOutcomes: [.ambiguousFailure],
            restoreRoutes: [.needsProfile, .active]
        )
        let coordinator = AuthenticationCoordinator(client: client)
        await coordinator.restore()

        try await coordinator.completeProfile(
            displayName: "Test User",
            phoneNumber: "+919876543210"
        )

        XCTAssertEqual(coordinator.route, .active)
        XCTAssertNil(coordinator.profileSubmissionError)
        let bootstrapCallCount = await client.bootstrapCallCount()
        XCTAssertEqual(bootstrapCallCount, 1)
    }

    func testDefinitiveAPIFailureRemainsVisibleAndDoesNotActivate() async throws {
        let rejection = AuthenticationClientError.bootstrapRejected(
            statusCode: 400,
            code: "validation_failed",
            message: "Display name is invalid."
        )
        let client = ProfileSubmissionAuthenticationClient(
            bootstrapOutcomes: [.definitiveFailure(rejection)],
            restoreRoutes: [.needsProfile]
        )
        let coordinator = AuthenticationCoordinator(client: client)
        await coordinator.restore()

        do {
            try await coordinator.completeProfile(
                displayName: "Test User",
                phoneNumber: "+919876543210"
            )
            XCTFail("Expected a definitive API failure")
        } catch let error as AuthenticationClientError {
            XCTAssertEqual(error, rejection)
        }

        XCTAssertEqual(coordinator.route, .needsProfile)
        XCTAssertEqual(coordinator.profileSubmissionError, rejection)
        let restoreCallCount = await client.restoreCallCount()
        XCTAssertEqual(restoreCallCount, 1)
    }
}

private actor ProfileSubmissionAuthenticationClient: AuthenticationClient {
    struct BootstrapRequest: Equatable, Sendable {
        let displayName: String
        let phoneNumber: String
        let key: IdempotencyKey
    }

    enum BootstrapOutcome: Sendable {
        case success
        case ambiguousFailure
        case definitiveFailure(AuthenticationClientError)
    }

    private var bootstrapOutcomes: [BootstrapOutcome]
    private var restoreRoutes: [AccountRoute]
    private let suspendFirstBootstrap: Bool
    private var bootstrapRequests: [BootstrapRequest] = []
    private var bootstrapContinuation: CheckedContinuation<Void, Never>?
    private var restoreCalls = 0

    init(
        bootstrapOutcomes: [BootstrapOutcome],
        restoreRoutes: [AccountRoute],
        suspendFirstBootstrap: Bool = false
    ) {
        self.bootstrapOutcomes = bootstrapOutcomes
        self.restoreRoutes = restoreRoutes
        self.suspendFirstBootstrap = suspendFirstBootstrap
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {}
    func signInWithGoogle(idToken: String) async throws {}
    func signInWithGoogle(redirectTo: URL) async throws {}

    func restoreAccount() async throws -> AccountRoute {
        restoreCalls += 1
        return restoreRoutes.removeFirst()
    }

    func bootstrapAccount(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {
        bootstrapRequests.append(
            BootstrapRequest(displayName: displayName, phoneNumber: phoneNumber, key: key)
        )
        if suspendFirstBootstrap && bootstrapRequests.count == 1 {
            await withCheckedContinuation { continuation in
                bootstrapContinuation = continuation
            }
        }

        switch bootstrapOutcomes.removeFirst() {
        case .success:
            return
        case .ambiguousFailure:
            throw AuthenticationClientError.bootstrapAmbiguousFailure
        case let .definitiveFailure(error):
            throw error
        }
    }

    func signOut() async throws {}

    func waitUntilBootstrapStarts() async {
        while bootstrapRequests.isEmpty {
            await Task.yield()
        }
    }

    func resumeFirstBootstrap() {
        bootstrapContinuation?.resume()
        bootstrapContinuation = nil
    }

    func recordedBootstrapRequests() -> [BootstrapRequest] {
        bootstrapRequests
    }

    func bootstrapCallCount() -> Int {
        bootstrapRequests.count
    }

    func restoreCallCount() -> Int {
        restoreCalls
    }
}
