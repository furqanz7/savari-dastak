import Foundation
import Supabase

/// Only used at a session/refresh boundary, never to classify arbitrary API 401s.
enum SupabaseSessionFailure {
    static func isConfirmedSessionLoss(_ error: Error) -> Bool {
        guard let error = error as? AuthError else { return false }
        if case .sessionMissing = error { return true }
        guard case let .api(_, code, _, response) = error,
              (400..<500).contains(response.statusCode)
        else { return false }
        return [ErrorCode.sessionNotFound, .sessionExpired, .refreshTokenNotFound,
                .refreshTokenAlreadyUsed, .userNotFound].contains(code)
    }
}
