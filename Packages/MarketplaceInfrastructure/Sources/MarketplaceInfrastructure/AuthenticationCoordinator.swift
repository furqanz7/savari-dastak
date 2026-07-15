import Combine
import Foundation
import MarketplaceFoundation

@MainActor
public final class AuthenticationCoordinator: ObservableObject {
    @Published public private(set) var route: AccountRoute = .signedOut

    private let client: any AuthenticationClient

    public init(client: any AuthenticationClient) {
        self.client = client
    }

    public func restore() async {
        do {
            route = try await client.restoreAccount()
        } catch {
            route = .signedOut
        }
    }

    public func signInWithApple(identityToken: String, nonce: String) async throws {
        route = .signedOut
        try await client.signInWithApple(identityToken: identityToken, nonce: nonce)
        route = try await client.restoreAccount()
    }

    public func signInWithGoogle(
        configuration: GoogleOAuthConfiguration = GoogleOAuthConfiguration(bundle: .main)
    ) async throws {
        route = .signedOut
        let callbackURL = try configuration.callbackURL()
        try await client.signInWithGoogle(redirectTo: callbackURL)
        route = try await client.restoreAccount()
    }

    public func completeProfile(
        displayName: String,
        phoneNumber: String,
        key: IdempotencyKey
    ) async throws {
        let validatedPhoneNumber = try E164PhoneNumber(phoneNumber).rawValue
        try await client.bootstrapAccount(
            displayName: displayName,
            phoneNumber: validatedPhoneNumber,
            key: key
        )
        do {
            route = try await client.restoreAccount()
        } catch {
            route = .signedOut
            throw error
        }
    }

    public func signOut() async throws {
        try await client.signOut()
        route = .signedOut
    }
}
