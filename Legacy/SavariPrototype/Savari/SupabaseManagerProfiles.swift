import Foundation
import Supabase
import PostgREST

private struct ProfilePayload: Encodable {
    let id: String
    let name: String
    let phone: String
    let age: String?
    let sex: String?
    let role: String
}

extension SupabaseManager {
    func upsertUserProfile(
        userId: UUID,
        name: String,
        phone: String,
        role: String,
        age: String?,
        sex: String?,
        vehicleNumber: String?
    ) async throws {
        try await upsertProfile(
            userId: userId,
            name: name,
            phone: phone,
            role: role,
            age: age,
            sex: sex
        )
    }

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

    func fetchProfile(for userId: UUID) async throws -> [String: Any]? {
        let response = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()

        guard !response.data.isEmpty else {
            return nil
        }

        let jsonObject = try JSONSerialization.jsonObject(with: response.data, options: [])
        return jsonObject as? [String: Any]
    }
}
