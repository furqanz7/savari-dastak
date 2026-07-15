import SwiftUI
import AuthenticationServices
import GoogleSignIn
import Auth
import UIKit

struct SignInStep: View {
    var onSignIn: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: handleAppleSignIn
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 55)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
            .padding(.horizontal, 15)

            Button(action: handleGoogleSignIn) {
                HStack {
                    Text("G")
                        .font(.headline)
                    Text("Sign in with Google")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.93, green: 0.94, blue: 0.96))
                .cornerRadius(14)
            }
            .padding(.horizontal, 15)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = appleIDCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                return
            }

            Task(priority: .userInitiated) {
                do {
                    let user = try await SupabaseManager.shared.signInWithApple(idToken: idToken)
                    SavariLog.debug("Apple user signed in:", user.id)

                    await MainActor.run {
                        onSignIn(user.id.uuidString)
                    }
                } catch {
                    SavariLog.debug("Supabase Apple sign-in error:", error.localizedDescription)
                }
            }

        case .failure(let error):
            SavariLog.debug("Apple Sign-In failed:", error.localizedDescription)
        }
    }

    private func handleGoogleSignIn() {
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else { return }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                SavariLog.debug("Google Sign-In failed:", error.localizedDescription)
                return
            }

            guard let idToken = result?.user.idToken?.tokenString else {
                SavariLog.debug("No ID token from Google")
                return
            }

            Task(priority: .userInitiated) {
                do {
                    let user = try await SupabaseManager.shared.signInWithGoogle(idToken: idToken)
                    SavariLog.debug("Supabase Google user signed in:", user.id)

                    await MainActor.run {
                        onSignIn(user.id.uuidString)
                    }
                } catch {
                    SavariLog.debug("Supabase Google sign-in error:", error.localizedDescription)
                }
            }
        }
    }
}
