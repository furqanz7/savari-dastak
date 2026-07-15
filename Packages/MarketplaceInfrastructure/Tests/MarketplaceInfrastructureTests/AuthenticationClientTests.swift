import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class AuthenticationClientTests: XCTestCase {
    func testRestoreWithoutProviderSessionReturnsSignedOut() async throws {
        let operations = RecordingAuthenticationOperations(providerSessionExists: false)
        let client = SupabaseAuthenticationClient(operations: operations)

        let route = try await client.restoreAccount()

        XCTAssertEqual(route, .signedOut)
    }

    func testRestoreWithProviderSessionAndNoAccountReturnsNeedsProfile() async throws {
        let operations = RecordingAuthenticationOperations(accountExists: false)
        let client = SupabaseAuthenticationClient(operations: operations)

        let route = try await client.restoreAccount()

        XCTAssertEqual(route, .needsProfile)
    }

    func testRestoreWithAccountReturnsActive() async throws {
        let operations = RecordingAuthenticationOperations(accountExists: true)
        let client = SupabaseAuthenticationClient(operations: operations)

        let route = try await client.restoreAccount()

        XCTAssertEqual(route, .active)
    }

    func testProviderTokensAreForwardedWithoutBecomingPhoneProof() async throws {
        let operations = RecordingAuthenticationOperations()
        let client = SupabaseAuthenticationClient(operations: operations)

        try await client.signInWithApple(identityToken: "apple-token", nonce: "nonce-123")
        try await client.signInWithGoogle(idToken: "google-token")

        let appleCredentials = await operations.recordedAppleCredentials()
        let googleIDToken = await operations.recordedGoogleIDToken()
        XCTAssertEqual(
            appleCredentials,
            .init(identityToken: "apple-token", nonce: "nonce-123")
        )
        XCTAssertEqual(googleIDToken, "google-token")
    }

    func testBootstrapForwardsRequiredProfileAndIdempotencyKey() async throws {
        let operations = RecordingAuthenticationOperations()
        let client = SupabaseAuthenticationClient(operations: operations)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "bootstrap-123"))

        try await client.bootstrapAccount(
            displayName: "Test User",
            phoneNumber: "+919876543210",
            key: key
        )

        let request = await operations.recordedBootstrapRequest()
        XCTAssertEqual(
            request,
            .init(
                displayName: "Test User",
                phoneNumber: "+919876543210",
                key: key
            )
        )
    }

    func testBootstrapRejectsResponseThatClaimsPhoneIsVerified() async throws {
        let operations = RecordingAuthenticationOperations(
            bootstrapResult: AccountBootstrapResult(
                accountID: UUID(),
                phoneState: .verified
            )
        )
        let client = SupabaseAuthenticationClient(operations: operations)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "bootstrap-verified"))

        do {
            try await client.bootstrapAccount(
                displayName: "Test User",
                phoneNumber: "+919876543210",
                key: key
            )
            XCTFail("Expected the unverified-phone contract to fail closed")
        } catch let error as AuthenticationClientError {
            XCTAssertEqual(error, .unexpectedPhoneVerificationState)
        }
    }

    func testTrackedGoogleOAuthPlaceholderFailsClosed() {
        let configuration = GoogleOAuthConfiguration(
            reversedClientID: GoogleOAuthConfiguration.notConfiguredClientID
        )

        XCTAssertThrowsError(try configuration.validatedReversedClientID()) { error in
            XCTAssertEqual(error as? AuthenticationClientError, .googleOAuthNotConfigured)
        }
    }

    func testSignOutUsesProviderSessionOnly() async throws {
        let operations = RecordingAuthenticationOperations()
        let client = SupabaseAuthenticationClient(operations: operations)

        try await client.signOut()

        let callCount = await operations.recordedSignOutCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testOwnerProvisioningIsParameterizedAdministratorSQLOnly() throws {
        for product in ["Savari", "Dastak"] {
            let scriptURL = repositoryRoot
                .appendingPathComponent("Backends")
                .appendingPathComponent(product)
                .appendingPathComponent("scripts/grant-initial-owner.sql")
            let sql = try String(contentsOf: scriptURL, encoding: .utf8)
            let normalized = sql.lowercased()

            XCTAssertTrue(normalized.contains("begin;"), product)
            XCTAssertTrue(normalized.contains(":'owner_id'::uuid"), product)
            XCTAssertTrue(normalized.contains("'bootstrap_owner_granted'"), product)
            XCTAssertTrue(normalized.contains("commit;"), product)
            XCTAssertFalse(normalized.contains("auth.uid()"), product)
            XCTAssertFalse(normalized.contains("service_role"), product)
            XCTAssertFalse(normalized.contains("create function"), product)
            XCTAssertFalse(normalized.contains("create policy"), product)
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
