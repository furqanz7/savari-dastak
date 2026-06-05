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
        SavariLog.debug("📦 Vehicle document paths:", vehicleDocs ?? [])
        SavariLog.debug("📦 Driver document paths:", driverDocs ?? [])
        SavariLog.debug("📸 Selfie path:", selfiePath ?? "none")

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
                SavariLog.debug("✅ Driver onboarding inserted:", json)
            } else {
                SavariLog.debug("⚠️ Upsert succeeded but no readable data.")
            }
        } catch {
            SavariLog.debug("❌ Driver onboarding failed:", error)
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
