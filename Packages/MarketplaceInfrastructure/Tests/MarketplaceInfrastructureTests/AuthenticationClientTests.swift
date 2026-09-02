import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class AuthenticationClientTests: XCTestCase {
    func testRuntimeBackendConfigurationAcceptsOnlyTheExpectedConfiguredProduct() throws {
        let configuration = try BackendConfiguration.runtime(
            product: .savari,
            infoDictionary: [
                "MarketplaceProduct": "Savari",
                "MarketplaceSupabaseURL": "https://savari-nonprod.supabase.co",
                "MarketplaceSupabasePublishableKey": "publishable-key"
            ]
        )

        XCTAssertEqual(configuration.product, "Savari")
        XCTAssertEqual(configuration.supabaseURL.absoluteString, "https://savari-nonprod.supabase.co")
        XCTAssertEqual(configuration.publishableKey, "publishable-key")
        XCTAssertThrowsError(
            try BackendConfiguration.runtime(
                product: .dastak,
                infoDictionary: [
                    "MarketplaceProduct": "Savari",
                    "MarketplaceSupabaseURL": "https://savari-nonprod.supabase.co",
                    "MarketplaceSupabasePublishableKey": "publishable-key"
                ]
            )
        )
    }

    func testRuntimeBackendConfigurationFailsClosedForTrackedPlaceholders() {
        XCTAssertThrowsError(
            try BackendConfiguration.runtime(
                product: .savari,
                infoDictionary: [
                    "MarketplaceProduct": "Savari",
                    "MarketplaceSupabaseURL": "https://not-configured.invalid",
                    "MarketplaceSupabasePublishableKey": "not-configured"
                ]
            )
        )
    }

    func testRestoreWithoutCurrentAccountReturnsSignedOut() async throws {
        let operations = RecordingAuthenticationOperations(currentAccountID: nil)
        let client = SupabaseAuthenticationClient(operations: operations)

        let route = try await client.restoreAccount()

        XCTAssertEqual(route, .signedOut)
        let profileLookupAccountID = await operations.recordedProfileLookupAccountID()
        XCTAssertNil(profileLookupAccountID)
    }

    func testRestoreWithCurrentAccountAndNoProfileReturnsNeedsProfile() async throws {
        let accountID = UUID()
        let operations = RecordingAuthenticationOperations(
            currentAccountID: accountID,
            profileAccountID: nil
        )
        let client = SupabaseAuthenticationClient(operations: operations)

        let route = try await client.restoreAccount()

        XCTAssertEqual(route, .needsProfile)
        let profileLookupAccountID = await operations.recordedProfileLookupAccountID()
        XCTAssertEqual(profileLookupAccountID, accountID)
    }

    func testRestoreWithMatchingCurrentAccountAndProfileReturnsActive() async throws {
        let accountID = UUID()
        let operations = RecordingAuthenticationOperations(
            currentAccountID: accountID,
            profileAccountID: accountID
        )
        let client = SupabaseAuthenticationClient(operations: operations)

        let route = try await client.restoreAccount()

        XCTAssertEqual(route, .active)
        let profileLookupAccountID = await operations.recordedProfileLookupAccountID()
        XCTAssertEqual(profileLookupAccountID, accountID)
    }

    func testRestoreUsesServerRouteForTheRequiredDastakApplication() async throws {
        let accountID = UUID()
        let operations = RecordingAuthenticationOperations(
            currentAccountID: accountID,
            profileAccountID: accountID,
            accountAccessRoute: .pendingApproval
        )
        let client = SupabaseAuthenticationClient(
            operations: operations,
            requiredAccess: .dastakMerchant
        )

        let route = try await client.restoreAccount()

        XCTAssertEqual(route, .pendingApproval)
        let requiredAccess = await operations.recordedRequiredAccess()
        XCTAssertEqual(requiredAccess, .dastakMerchant)
    }

    func testRestoreWithMismatchedProfileDoesNotBecomeActive() async throws {
        let currentAccountID = UUID()
        let operations = RecordingAuthenticationOperations(
            currentAccountID: currentAccountID,
            profileAccountID: UUID()
        )
        let client = SupabaseAuthenticationClient(operations: operations)

        let route = try await client.restoreAccount()

        XCTAssertEqual(route, .needsProfile)
        let profileLookupAccountID = await operations.recordedProfileLookupAccountID()
        XCTAssertEqual(profileLookupAccountID, currentAccountID)
    }

    func testLiveProfileLookupFiltersAccountsByCurrentAccountID() async throws {
        let accountID = UUID()
        let session = makeCapturingSession(
            responses: [
                .init(
                    statusCode: 200,
                    body: #"[{"id":"\#(accountID.uuidString)"}]"#.data(using: .utf8)!
                )
            ]
        )
        let operations = SupabaseAuthenticationClient.LiveOperations(
            configuration: testBackendConfiguration,
            session: session,
            accessToken: "session-access-token"
        )

        let profileAccountID = try await operations.accountProfileID(for: accountID)

        XCTAssertEqual(profileAccountID, accountID)
        let request = try XCTUnwrap(
            CapturingURLProtocol.capture.recordedRequests().first {
                $0.url?.path == "/rest/v1/accounts"
            }
        )
        let queryItems = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(queryItems.first(where: { $0.name == "select" })?.value, "id")
        XCTAssertEqual(queryItems.first(where: { $0.name == "id" })?.value, "eq.\(accountID.uuidString)")
        XCTAssertEqual(queryItems.first(where: { $0.name == "limit" })?.value, "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-access-token")
    }

    func testLiveBootstrapUsesSessionAuthorizationAndIdempotencyBoundary() async throws {
        let accountID = UUID()
        let session = makeCapturingSession(
            responses: [
                .init(
                    statusCode: 200,
                    body: #"{"accountId":"\#(accountID.uuidString)","phoneRecorded":true}"#.data(using: .utf8)!
                )
            ]
        )
        let operations = SupabaseAuthenticationClient.LiveOperations(
            configuration: testBackendConfiguration,
            session: session,
            accessToken: "session-access-token"
        )
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "bootstrap-live-123"))

        let result = try await operations.bootstrapAccount(
            displayName: "Test User",
            phoneNumber: "+919876543210",
            application: .dastakMerchant,
            key: key
        )

        XCTAssertEqual(result.accountID, accountID)
        let request = try XCTUnwrap(
            CapturingURLProtocol.capture.recordedRequests().first {
                $0.url?.path == "/functions/v1/bootstrap-account"
            }
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Idempotency-Key"), key.rawValue)
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedBootstrapRequest.self, from: try capturedRequestBody(request)),
            .init(application: "merchant", displayName: "Test User", phoneNumber: "+919876543210")
        )
    }

    func testLiveAppAccessResolutionUsesSessionAuthorizationAndDeclaredApplication() async throws {
        let session = makeCapturingSession(
            responses: [
                .init(
                    statusCode: 200,
                    body: #"{"route":"suspended"}"#.data(using: .utf8)!
                )
            ]
        )
        let operations = SupabaseAuthenticationClient.LiveOperations(
            configuration: testBackendConfiguration,
            session: session,
            accessToken: "session-access-token"
        )

        let route = try await operations.resolveAppAccess(for: .dastakAdmin)

        XCTAssertEqual(route, .suspended)
        let request = try XCTUnwrap(
            CapturingURLProtocol.capture.recordedRequests().first {
                $0.url?.path == "/functions/v1/resolve-app-access"
            }
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-access-token")
        XCTAssertEqual(
            try JSONDecoder().decode(CapturedAppAccessRequest.self, from: try capturedRequestBody(request)),
            .init(application: "admin")
        )
    }

    func testBootstrapMapsNestedHTTPErrorToDefinitiveRejection() async throws {
        let session = makeCapturingSession(
            responses: [
                .init(
                    statusCode: 400,
                    body: #"{"error":{"code":"validation_failed","message":"Display name is invalid."}}"#
                        .data(using: .utf8)!
                )
            ]
        )
        let operations = SupabaseAuthenticationClient.LiveOperations(
            configuration: testBackendConfiguration,
            session: session,
            accessToken: "session-access-token"
        )
        let client = SupabaseAuthenticationClient(operations: operations)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "bootstrap-definitive"))

        do {
            try await client.bootstrapAccount(
                displayName: "Test User",
                phoneNumber: "+919876543210",
                key: key
            )
            XCTFail("Expected a definitive API rejection")
        } catch let error as AuthenticationClientError {
            XCTAssertEqual(
                error,
                .bootstrapRejected(
                    statusCode: 400,
                    code: "validation_failed",
                    message: "Display name is invalid."
                )
            )
        }
    }

    func testBootstrapMapsTransportFailureToAmbiguousFailure() async throws {
        let operations = RecordingAuthenticationOperations(bootstrapError: .transport)
        let client = SupabaseAuthenticationClient(operations: operations, requiredAccess: .dastakMerchant)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "bootstrap-ambiguous"))

        do {
            try await client.bootstrapAccount(
                displayName: "Test User",
                phoneNumber: "+919876543210",
                key: key
            )
            XCTFail("Expected an ambiguous bootstrap failure")
        } catch let error as AuthenticationClientError {
            XCTAssertEqual(error, .bootstrapAmbiguousFailure)
        }
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
        let client = SupabaseAuthenticationClient(operations: operations, requiredAccess: .dastakMerchant)
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
                application: .dastakMerchant,
                key: key
            )
        )
    }

    func testBootstrapRejectsResponseWithoutRecordedPhoneProof() async throws {
        let operations = RecordingAuthenticationOperations(
            bootstrapResult: AccountBootstrapResult(
                accountID: UUID(),
                phoneRecorded: false
            )
        )
        let client = SupabaseAuthenticationClient(operations: operations)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "bootstrap-unverified"))

        do {
            try await client.bootstrapAccount(
                displayName: "Test User",
                phoneNumber: "+919876543210",
                key: key
            )
            XCTFail("Expected missing required-phone proof to fail closed")
        } catch let error as AuthenticationClientError {
            XCTAssertEqual(error, .unexpectedPhoneRecordingState)
        }
    }

    func testBootstrapRejectsMalformedE164PhoneNumbersBeforeCallingOperations() async throws {
        let operations = RecordingAuthenticationOperations()
        let client = SupabaseAuthenticationClient(operations: operations)
        let key = try XCTUnwrap(IdempotencyKey(rawValue: "bootstrap-invalid-phone"))

        for phoneNumber in ["+12", "919876543210", "+019876543210", "+91 9876543210", "+9198765432100000"] {
            do {
                try await client.bootstrapAccount(
                    displayName: "Test User",
                    phoneNumber: phoneNumber,
                    key: key
                )
                XCTFail("Expected \(phoneNumber) to fail E.164 validation")
            } catch let error as AuthenticationClientError {
                XCTAssertEqual(error, .invalidE164PhoneNumber)
            }
        }

        let request = await operations.recordedBootstrapRequest()
        XCTAssertNil(request)
    }

    func testE164PhoneNumberAcceptsCanonicalInternationalNumber() throws {
        let phoneNumber = try E164PhoneNumber("+14155552671")

        XCTAssertEqual(phoneNumber.rawValue, "+14155552671")
    }

    func testMissingOAuthCallbackSchemeFailsClosed() {
        let configuration = OAuthCallbackConfiguration(scheme: "")

        XCTAssertThrowsError(try configuration.validatedScheme()) { error in
            XCTAssertEqual(error as? AuthenticationClientError, .oauthCallbackNotConfigured)
        }
    }

    func testOAuthCallbackAcceptsRegisteredBundleIdentifierScheme() throws {
        let configuration = OAuthCallbackConfiguration(scheme: "com.dastak.merchant")

        XCTAssertEqual(
            try configuration.callbackURL(),
            URL(string: "com.dastak.merchant://login-callback")
        )
    }

    #if canImport(AuthenticationServices)
    func testOAuthErrorMapperTreatsCanceledWebSessionAsCancellation() {
        let error = NSError(
            domain: ASWebAuthenticationSessionErrorDomain,
            code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
        )

        XCTAssertEqual(OAuthSignInErrorMapper.map(error), .oauthCancelled)
    }
    #endif

    func testOAuthErrorMapperTreatsExpiredStateSeparately() {
        XCTAssertEqual(
            OAuthSignInErrorMapper.classifyPKCE(
                message: "OAuth state has expired",
                providerError: "server_error",
                providerCode: "bad_oauth_state"
            ),
            .oauthSessionExpired
        )
    }

    func testOAuthErrorMapperTreatsProviderServerFailureAsUnavailable() {
        XCTAssertEqual(
            OAuthSignInErrorMapper.classifyPKCE(
                message: "Unable to exchange external code",
                providerError: "server_error",
                providerCode: "unexpected_failure"
            ),
            .oauthProviderUnavailable
        )
    }

    func testOAuthErrorMapperTreatsProviderAccessDeniedAsCancellation() {
        XCTAssertEqual(
            OAuthSignInErrorMapper.classifyPKCE(
                message: "The user denied access",
                providerError: "access_denied",
                providerCode: nil
            ),
            .oauthCancelled
        )
    }

    func testGoogleSignInMessagesAreSpecificAndCancellationIsSilent() {
        XCTAssertNil(AuthenticationClientError.oauthCancelled.googleSignInMessage)
        XCTAssertEqual(
            AuthenticationClientError.oauthSessionExpired.googleSignInMessage,
            "Google sign-in expired. Try again."
        )
        XCTAssertEqual(
            AuthenticationClientError.oauthProviderUnavailable.googleSignInMessage,
            "Google sign-in is temporarily unavailable. Try again later."
        )
        XCTAssertEqual(
            AuthenticationClientError.oauthCallbackNotConfigured.googleSignInMessage,
            "Google sign-in is not configured."
        )
    }

    @MainActor
    func testSharedCoordinatorUsesSupabaseGoogleWebFlowAndRestoresServerRoute() async throws {
        let client = FakeAuthenticationClient(
            restoredRoute: .needsProfile,
            suggestedName: "Google Customer"
        )
        let coordinator = AuthenticationCoordinator(client: client)

        let suggestedName = try await coordinator.signInWithGoogle(
            configuration: OAuthCallbackConfiguration(scheme: "com.dastak.app")
        )

        XCTAssertEqual(coordinator.route, .needsProfile)
        XCTAssertEqual(suggestedName, "Google Customer")
        let redirectURL = await client.recordedGoogleRedirectURL()
        XCTAssertEqual(
            redirectURL,
            URL(string: "com.dastak.app://login-callback")
        )
    }

    func testAppleNonceHashUsesSHA256ForSystemCredentialRequest() {
        XCTAssertEqual(
            AppleSignInNonce.sha256("test"),
            "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        )
    }

    func testSavariGoogleOAuthDefaultIsOverridableAndWiredToEveryAppTarget() throws {
        let gitignore = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        XCTAssertTrue(gitignore.contains("**/Secrets.xcconfig"))

        try assertGoogleOAuthDefaults(
            product: "Savari",
            projectName: "Savari",
            defaultsReference: "A1A1A1A1A1A1A1A1A1A1A1A1",
            configurationIDs: [
                "A56DCBF2CD11538AE1F64796",
                "D8C955244EB6128D29D56334",
                "2D75231A2B05595624883B7E",
                "86449F7B4DA0A64EE246D938"
            ]
        )
    }

    func testDastakRegistersEachBundleIdentifierAsItsOAuthCallbackScheme() throws {
        let defaultsURL = repositoryRoot
            .appendingPathComponent("Apps/Dastak/Configuration/Defaults.xcconfig")
        let defaults = try String(contentsOf: defaultsURL, encoding: .utf8)
        let infoPlistURL = repositoryRoot
            .appendingPathComponent("Apps/Dastak/Supporting/Info.plist")
        let infoPlist = try String(contentsOf: infoPlistURL, encoding: .utf8)

        XCTAssertFalse(defaults.contains("GOOGLE_REVERSED_CLIENT_ID"))
        XCTAssertTrue(infoPlist.contains("<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>"))
        XCTAssertFalse(infoPlist.contains("$(GOOGLE_REVERSED_CLIENT_ID)"))
    }

    func testEveryDastakTargetDeclaresItsServerApprovedAccessRequirement() throws {
        let expectations = [
            ("Sources/Dastak/DastakApp.swift", ".dastakCustomer"),
            ("Sources/DastakMerchant/DastakMerchantApp.swift", ".dastakMerchant"),
            ("Sources/DastakAdmin/DastakAdminApp.swift", ".dastakAdmin")
        ]

        for (path, requiredAccess) in expectations {
            let source = try String(
                contentsOf: repositoryRoot
                    .appendingPathComponent("Apps/Dastak")
                    .appendingPathComponent(path),
                encoding: .utf8
            )
            XCTAssertTrue(
                source.contains("requiredAccess: \(requiredAccess)"),
                "Missing server-approved access requirement in \(path)"
            )
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

    private var testBackendConfiguration: BackendConfiguration {
        BackendConfiguration(
            product: "test-product",
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable-key"
        )
    }

    private func assertGoogleOAuthDefaults(
        product: String,
        projectName: String,
        defaultsReference: String,
        configurationIDs: [String]
    ) throws {
        let defaultsURL = repositoryRoot
            .appendingPathComponent("Apps")
            .appendingPathComponent(product)
            .appendingPathComponent("Configuration/Defaults.xcconfig")
        let defaults = try String(contentsOf: defaultsURL, encoding: .utf8)
        let defaultValue = try XCTUnwrap(
            defaults.range(of: "GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.not-configured")
        )
        let secretsInclude = try XCTUnwrap(defaults.range(of: #"#include? "Secrets.xcconfig""#))
        XCTAssertLessThan(defaultValue.lowerBound, secretsInclude.lowerBound)

        let projectURL = repositoryRoot
            .appendingPathComponent("Apps")
            .appendingPathComponent(product)
            .appendingPathComponent("\(projectName).xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        XCTAssertTrue(project.contains("\(defaultsReference) /* Defaults.xcconfig */"))

        for configurationID in configurationIDs {
            let block = try XCTUnwrap(
                buildConfigurationBlock(id: configurationID, in: project),
                "Missing build configuration \(configurationID)"
            )
            XCTAssertTrue(
                block.contains("baseConfigurationReference = \(defaultsReference) /* Defaults.xcconfig */;"),
                configurationID
            )
            XCTAssertFalse(block.contains("GOOGLE_REVERSED_CLIENT_ID"), configurationID)
        }
    }

    private func buildConfigurationBlock(id: String, in project: String) -> String? {
        guard let start = project.range(of: "\t\t\(id) /*") else {
            return nil
        }
        let remainder = project[start.lowerBound...]
        guard let end = remainder.range(of: "\n\t\t};") else {
            return nil
        }
        return String(remainder[..<end.lowerBound])
    }
}

private struct CapturedBootstrapRequest: Decodable, Equatable {
    let application: String
    let displayName: String
    let phoneNumber: String
}

private struct CapturedAppAccessRequest: Decodable, Equatable {
    let application: String
}

private struct CapturedHTTPResponse {
    let statusCode: Int
    let body: Data
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = [URLRequest]()
    private var responses = [CapturedHTTPResponse]()

    func reset(responses: [CapturedHTTPResponse]) {
        lock.lock()
        defer { lock.unlock() }
        requests = []
        self.responses = responses
    }

    func record(_ request: URLRequest) -> CapturedHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        guard !responses.isEmpty else {
            return CapturedHTTPResponse(statusCode: 500, body: Data())
        }
        return responses.removeFirst()
    }

    func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class CapturingURLProtocol: URLProtocol, @unchecked Sendable {
    static let capture = RequestCapture()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let capturedResponse = Self.capture.record(request)
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: capturedResponse.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: capturedResponse.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeCapturingSession(responses: [CapturedHTTPResponse]) -> URLSession {
    CapturingURLProtocol.capture.reset(responses: responses)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CapturingURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func capturedRequestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        throw RequestCaptureError.missingBody
    }

    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = buffer.withUnsafeMutableBufferPointer {
            stream.read($0.baseAddress!, maxLength: $0.count)
        }
        guard count >= 0 else {
            throw stream.streamError ?? RequestCaptureError.unreadableBody
        }
        guard count > 0 else {
            break
        }
        body.append(contentsOf: buffer.prefix(count))
    }
    return body
}

private enum RequestCaptureError: Error {
    case missingBody
    case unreadableBody
}
