import Supabase

public enum DastakEvidenceUpload {
    /// Only for retrying the same saved, immutable, account-owned object path.
    public static func isDuplicate(_ error: Error) -> Bool {
        guard let error = error as? StorageError else { return false }
        return error.statusCode == "409" || error.error == "Duplicate"
    }
}
