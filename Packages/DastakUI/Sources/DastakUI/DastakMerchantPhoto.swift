import Foundation
import ImageIO
import UniformTypeIdentifiers
import MarketplaceInfrastructure

enum DastakMerchantPhotoError: LocalizedError, Equatable {
    case unreadable, unsupported, unsupportedReady, dimensions, tooLarge(Int), conversion
    var errorDescription: String? {
        switch self {
        case .unreadable: "This photo could not be opened. Download it from iCloud or choose another photo."
        case .unsupported: "Choose a JPEG, PNG, WebP or HEIC photo. Animated images and other formats are not supported here."
        case .unsupportedReady: "Choose a JPEG, PNG or HEIC Ready photo. WebP and animated images are not supported for Ready evidence."
        case .dimensions: "This photo is too large to process safely. Export a smaller photo and try again."
        case let .tooLarge(limit): "This photo is too large. Choose a photo up to \(limit) MB."
        case .conversion: "The HEIC photo could not be converted. Export it as JPEG or choose another photo."
        }
    }
}

struct DastakMerchantPreparedPhoto: Sendable {
    let data: Data
    let contentType: String
    let fileExtension: String
    let converted: Bool
}

enum DastakMerchantPhoto {
    enum Purpose: Sendable, Equatable { case catalogue, ready }
    static func load(purpose: Purpose, timeout: Duration = .seconds(20),
                     data: @escaping @Sendable () async throws -> Data?) async throws -> DastakMerchantPreparedPhoto {
        try await MarketplaceRequestDeadline.run(after: timeout) {
            guard let bytes = try await data() else { throw DastakMerchantPhotoError.unreadable }
            return try prepare(bytes, purpose: purpose)
        }
    }
    static func prepare(_ data: Data, purpose: Purpose) throws -> DastakMerchantPreparedPhoto {
        let inputLimit = purpose == .catalogue ? 20 : 10
        guard !data.isEmpty else { throw DastakMerchantPhotoError.unreadable }
        guard data.count <= inputLimit * 1_024 * 1_024 else { throw DastakMerchantPhotoError.tooLarge(inputLimit) }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String)
        else { throw DastakMerchantPhotoError.unreadable }
        guard CGImageSourceGetCount(source) == 1 else { throw purpose == .ready ? DastakMerchantPhotoError.unsupportedReady : .unsupported }
        let heic = type == .heic || type == .heif
        let format: (String, String)
        if type == .jpeg { format = ("image/jpeg", "jpg") }
        else if type == .png { format = ("image/png", "png") }
        else if type == .webP, purpose == .catalogue { format = ("image/webp", "webp") }
        else if heic { format = ("image/heic", "heic") }
        else { throw purpose == .ready ? DastakMerchantPhotoError.unsupportedReady : .unsupported }
        let limit = purpose == .catalogue ? 5 : 10
        if !(purpose == .catalogue && heic), data.count > limit * 1_024 * 1_024 { throw DastakMerchantPhotoError.tooLarge(limit) }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000,
              Double(width) * Double(height) <= 64_000_000 else { throw DastakMerchantPhotoError.dimensions }
        let converting = purpose == .catalogue && heic
        // Decode a bounded thumbnail to verify pixels without allocating a full-resolution photo.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: converting ? 2_560 : 32
        ] as CFDictionary) else { throw DastakMerchantPhotoError.unreadable }
        if converting {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw DastakMerchantPhotoError.conversion }
            // Fresh JPEG pixels; no source location/EXIF dictionary is copied.
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(destination), output.length > 0 else { throw DastakMerchantPhotoError.conversion }
            guard output.length <= 5 * 1_024 * 1_024 else { throw DastakMerchantPhotoError.tooLarge(5) }
            return .init(data: output as Data, contentType: "image/jpeg", fileExtension: "jpg", converted: true)
        }
        return .init(data: data, contentType: format.0, fileExtension: format.1, converted: false)
    }
    static func failureMessage(_ error: any Error) -> String {
        if let known = error as? DastakMerchantPhotoError { return known.localizedDescription }
        if (error as? URLError)?.code == .timedOut { return "Loading this photo took too long. Check its iCloud download or choose another photo, then try again." }
        return "This photo could not be loaded. Download it from iCloud or choose another photo."
    }
}
