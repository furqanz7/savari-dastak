import Foundation
import Supabase
import UIKit

extension SupabaseManager {
    func uploadDriverDocuments(userId: UUID, images: [UIImage], prefix: String) async throws -> [String] {
        guard !images.isEmpty else { return [] }
        let bucket = client.storage.from("driver_docs")
        var paths: [String] = []

        for (index, image) in images.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let path = "\(userId.uuidString)/\(prefix)_\(index + 1).jpg"

            try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            paths.append(path)
            SavariLog.debug("⬆️ Uploaded driver document:", path)
        }

        return paths
    }

    func uploadDriverDocument(userId: UUID, image: UIImage, filename: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }

        let bucket = client.storage.from("driver_docs")
        let path = "\(userId.uuidString)/\(filename)"

        try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))

        SavariLog.debug("⬆️ Uploaded driver document:", path)
        return path
    }
}
