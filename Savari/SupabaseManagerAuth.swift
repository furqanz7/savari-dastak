import Foundation
import Supabase
import Auth
import GoogleSignIn

extension SupabaseManager {
    func signInWithApple(idToken: String) async throws -> User {
        let result = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken)
        )
        return result.user
    }

    func signInWithGoogle(idToken: String) async throws -> User {
        let result = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken)
        )
        return result.user
    }

    @MainActor
    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            SavariLog.debug("[Auth] Supabase sign-out error:", error.localizedDescription)
        }

        GIDSignIn.sharedInstance.signOut()
    }
}
