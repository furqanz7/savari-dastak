import Foundation
import Supabase
import PostgREST

private struct PaymentPayload: Encodable {
    let id: String
    let profile_id: String
    let provider: String?
    let method_type: String?
    let token: String?
    let last4: String?
    let is_default: Bool
}

extension SupabaseManager {
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
