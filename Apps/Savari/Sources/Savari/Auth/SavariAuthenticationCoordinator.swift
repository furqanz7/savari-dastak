import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

@MainActor
final class AuthenticationCoordinator {
    private(set) var route: AccountRoute = .signedOut

    private let client: any AuthenticationClient

    init(client: any AuthenticationClient) {
        self.client = client
    }

    func restore() async {
        do {
            route = try await client.restoreAccount()
        } catch {
            route = .signedOut
        }
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        try await client.signInWithApple(identityToken: identityToken, nonce: nonce)
        route = try await client.restoreAccount()
    }

    func signInWithGoogle(
        idToken: String,
        configuration: GoogleOAuthConfiguration = GoogleOAuthConfiguration(bundle: .main)
    ) async throws {
        _ = try configuration.validatedReversedClientID()
        try await client.signInWithGoogle(idToken: idToken)
        route = try await client.restoreAccount()
    }

    func completeProfile(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {
        try await client.bootstrapAccount(
            displayName: displayName,
            phoneNumber: phoneNumber,
            key: key
        )
        route = try await client.restoreAccount()
    }

    func signOut() async throws {
        try await client.signOut()
        route = .signedOut
    }
}
