//
//  SupabaseManager.swift
//  Savari
//

import Foundation
import Supabase
import GoogleSignIn
import UIKit

final class SupabaseManager {
    static let shared = SupabaseManager()

    private let supabaseUrl = URL(string: "https://mxpszppootpltifzvjla.supabase.co")!
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im14cHN6cHBvb3RwbHRpZnp2amxhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAxMjAxNzUsImV4cCI6MjA3NTY5NjE3NX0.ZBN6pr6zP7AkfdWLfmxqjG0QULjmt1djf1bCh2D0l9s"

    lazy var client = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseKey)
    private init() {}

    // MARK: - AUTHENTICATION
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
            print("❌ Supabase sign-out error:", error.localizedDescription)
        }

        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - STRUCTS
    private struct ProfilePayload: Encodable {
        let id: String
        let name: String
        let phone: String
        let age: String?
        let sex: String?
        let role: String
    }

    private struct PaymentPayload: Encodable {
        let id: String
        let profile_id: String
        let provider: String?
        let method_type: String?
        let token: String?
        let last4: String?
        let is_default: Bool
    }

    // MARK: - PROFILE MANAGEMENT

    /// Backwards-compatible alias used by UI code
    func upsertUserProfile(
        userId: UUID,
        name: String,
        phone: String,
        role: String,
        age: String?,
        sex: String?,
        vehicleNumber: String?
    ) async throws {
        // vehicleNumber currently unused at profile level; kept for signature compatibility
        try await upsertProfile(
            userId: userId,
            name: name,
            phone: phone,
            role: role,
            age: age,
            sex: sex
        )
    }

    /// Create or update a user's base profile (for both roles)
    func upsertProfile(
        userId: UUID,
        name: String,
        phone: String,
        role: String,
        age: String?,
        sex: String?
    ) async throws {
        let payload = ProfilePayload(
            id: userId.uuidString,
            name: name,
            phone: phone,
            age: age,
            sex: sex,
            role: role
        )
        try await client
            .from("profiles")
            .upsert([payload])
            .execute()
    }

    /// Fetch an existing profile
    func fetchProfile(for userId: UUID) async throws -> [String: Any]? {
        let response = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()

        // Decode the JSON data into a dictionary. If it's empty JSON, return nil.
        let data = response.data
        // If the backend returns an empty object or no bytes, treat as no profile
        if data.isEmpty { return nil }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = jsonObject as? [String: Any] else {
            // If the shape isn't a dictionary, return nil
            return nil
        }
        return dict
    }

    // MARK: - PAYMENTS

    func linkPaymentMethod(
        userId: UUID,
        provider: String,
        token: String,
        methodType: String,
        last4: String
    ) async throws {
        let payload = PaymentPayload(
            id: UUID().uuidString,
            profile_id: userId.uuidString,
            provider: provider,
            method_type: methodType,
            token: token,
            last4: last4,
            is_default: true
        )
        try await client
            .from("payment_methods")
            .upsert([payload])
            .execute()
    }
}

// MARK: - FILE UPLOADS
// MARK: - DRIVER ONBOARDING
extension SupabaseManager {
    struct DriverOnboardingPayload: Encodable {
        let profile_id: String
        let vehicle_number: String
        let license_number: String
        let vehicle_docs: String?
        let driver_docs: String?
        let selfie_url: String?
        let verified: Bool?
    }
    
    func upsertDriverOnboarding(
        profileId: UUID,
        vehicleNumber: String,
        licenseNumber: String,
        vehicleDocs: [String]?,
        driverDocs: [String]?,
        selfiePath: String?
    ) async throws {
        print("📦 Vehicle document paths:", vehicleDocs ?? [])
        print("📦 Driver document paths:", driverDocs ?? [])
        print("📸 Selfie path:", selfiePath ?? "none")

        let payload = DriverOnboardingPayload(
            profile_id: profileId.uuidString,
            vehicle_number: vehicleNumber,
            license_number: licenseNumber,
            vehicle_docs: vehicleDocs != nil ? try? JSONEncoder().encodeToJSONString(vehicleDocs!) : nil,
            driver_docs: driverDocs != nil ? try? JSONEncoder().encodeToJSONString(driverDocs!) : nil,
            selfie_url: selfiePath,
            verified: false
        )
        
        do {
            let response = try await client
                .from("driver_onboarding")
                .upsert([payload])
                .select()
                .execute()

            if let json = String(data: response.data, encoding: .utf8) {
                print("✅ Driver onboarding inserted:", json)
            } else {
                print("⚠️ Upsert succeeded but no readable data.")
            }
        } catch {
            print("❌ Driver onboarding failed:", error)
            throw error
        }
    }
}

extension JSONEncoder {
    func encodeToJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try self.encode(value)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

extension SupabaseManager {
    /// Uploads multiple images to Supabase Storage and returns object paths.
    func uploadDriverDocuments(userId: UUID, images: [UIImage], prefix: String) async throws -> [String] {
        guard !images.isEmpty else { return [] }
        let bucket = client.storage.from("driver_docs")
        var paths: [String] = []

        for (index, image) in images.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let path = "\(userId.uuidString)/\(prefix)_\(index + 1).jpg"

            try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            paths.append(path)
            print("⬆️ Uploaded driver document:", path)
        }

        return paths
    }

    /// Uploads a single image and returns its Supabase Storage object path.
    func uploadDriverDocument(userId: UUID, image: UIImage, filename: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }

        let bucket = client.storage.from("driver_docs")
        let path = "\(userId.uuidString)/\(filename)"

        try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))

        print("⬆️ Uploaded driver document:", path)
        return path
    }
}
