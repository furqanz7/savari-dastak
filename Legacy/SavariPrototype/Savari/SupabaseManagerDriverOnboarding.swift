import Foundation
import Supabase
import PostgREST

private struct DriverOnboardingPayload: Encodable {
    let profile_id: String
    let vehicle_number: String
    let license_number: String
    let vehicle_docs: String?
    let driver_docs: String?
    let selfie_url: String?
    let verified: Bool?
}

extension SupabaseManager {
    func upsertDriverOnboarding(
        profileId: UUID,
        vehicleNumber: String,
        licenseNumber: String,
        vehicleDocs: [String]?,
        driverDocs: [String]?,
        selfiePath: String?
    ) async throws {
        SavariLog.debug(
            "[DriverOnboarding] documents prepared:",
            "vehicle=\(vehicleDocs?.count ?? 0)",
            "driver=\(driverDocs?.count ?? 0)",
            "selfie=\(selfiePath == nil ? "missing" : "present")"
        )

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

            SavariLog.debug("[DriverOnboarding] upsert succeeded:", response.data.count, "bytes")
        } catch {
            SavariLog.debug("[DriverOnboarding] upsert failed:", error)
            throw error
        }
    }
}

private extension JSONEncoder {
    func encodeToJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
