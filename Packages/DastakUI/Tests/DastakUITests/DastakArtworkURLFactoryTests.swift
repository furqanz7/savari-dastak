import XCTest
@testable import DastakUI

final class DastakArtworkURLFactoryTests: XCTestCase {
    func testBuildsOptimizedThumbnailAndOriginalFallbackURLs() throws {
        let request = try XCTUnwrap(DastakArtworkURLFactory.request(
            for: "canonical/staging/Brand Name/product image.webp",
            baseURLString: "https://project.supabase.co/",
            pixelSize: 384
        ))

        XCTAssertEqual(
            request.originalURL.absoluteString,
            "https://project.supabase.co/storage/v1/object/public/dastak-catalogue/canonical/staging/Brand%20Name/product%20image.webp"
        )
        XCTAssertEqual(
            request.thumbnailURL.path,
            "/storage/v1/render/image/public/dastak-catalogue/canonical/staging/Brand Name/product image.webp"
        )
        XCTAssertEqual(
            URLComponents(url: request.thumbnailURL, resolvingAgainstBaseURL: false)?.queryItems,
            [
                URLQueryItem(name: "width", value: "384"),
                URLQueryItem(name: "height", value: "384"),
                URLQueryItem(name: "resize", value: "contain"),
                URLQueryItem(name: "quality", value: "72"),
            ]
        )
        XCTAssertEqual(request.candidateURLs, [request.thumbnailURL, request.originalURL])
    }

    func testRejectsUnsafeOrMalformedImageKeys() {
        let base = "https://project.supabase.co"
        XCTAssertNil(DastakArtworkURLFactory.request(for: nil, baseURLString: base))
        XCTAssertNil(DastakArtworkURLFactory.request(for: "", baseURLString: base))
        XCTAssertNil(DastakArtworkURLFactory.request(for: "../secret.webp", baseURLString: base))
        XCTAssertNil(DastakArtworkURLFactory.request(for: "folder//image.webp", baseURLString: base))
        XCTAssertNil(DastakArtworkURLFactory.request(for: "folder\\image.webp", baseURLString: base))
    }

    func testClampsThumbnailDimension() throws {
        let base = "https://project.supabase.co"
        let small = try XCTUnwrap(DastakArtworkURLFactory.request(for: "image.webp", baseURLString: base, pixelSize: 10))
        let large = try XCTUnwrap(DastakArtworkURLFactory.request(for: "image.webp", baseURLString: base, pixelSize: 4_000))

        XCTAssertTrue(small.thumbnailURL.query?.contains("width=128") == true)
        XCTAssertTrue(large.thumbnailURL.query?.contains("width=1024") == true)
    }
}
