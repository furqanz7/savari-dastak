import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class AuthenticatedServicesTests: XCTestCase {
    func testAccountIDAndUploadForwardAuthenticatedValues() async throws {
        let accountID = UUID(uuidString: "4B90C9BA-95C7-4C5F-B4D3-B8D9A6576BA1")!
        let recorder = UploadRecorder()
        let services = MarketplaceAuthenticatedServices(
            functions: UnusedFunctionClient(),
            accountIDProvider: { accountID },
            objectUploader: { bucket, path, data, contentType, cacheControl in
                await recorder.record(
                    bucket: bucket,
                    path: path,
                    data: data,
                    contentType: contentType,
                    cacheControl: cacheControl
                )
            }
        )

        let resolvedAccountID = try await services.accountID()
        XCTAssertEqual(resolvedAccountID, accountID)
        try await services.uploadObject(
            bucket: "dastak-catalogue",
            path: "merchant/\(accountID.uuidString.lowercased())/item.jpg",
            data: Data([1, 2, 3]),
            contentType: "image/jpeg",
            cacheControl: "7200"
        )

        let recordedUpload = await recorder.lastUpload()
        let upload = try XCTUnwrap(recordedUpload)
        XCTAssertEqual(upload.bucket, "dastak-catalogue")
        XCTAssertEqual(upload.path, "merchant/\(accountID.uuidString.lowercased())/item.jpg")
        XCTAssertEqual(upload.data, Data([1, 2, 3]))
        XCTAssertEqual(upload.contentType, "image/jpeg")
        XCTAssertEqual(upload.cacheControl, "7200")
    }

    func testUploadRejectsPathTraversalBeforeCallingStorage() async throws {
        let recorder = UploadRecorder()
        let services = MarketplaceAuthenticatedServices(
            functions: UnusedFunctionClient(),
            accountIDProvider: { UUID() },
            objectUploader: { bucket, path, data, contentType, cacheControl in
                await recorder.record(
                    bucket: bucket,
                    path: path,
                    data: data,
                    contentType: contentType,
                    cacheControl: cacheControl
                )
            }
        )

        do {
            try await services.uploadObject(
                bucket: "dastak-evidence",
                path: "merchant/../secret.pdf",
                data: Data([1]),
                contentType: "application/pdf"
            )
            XCTFail("Expected an invalid path error.")
        } catch {
            XCTAssertEqual(
                error as? MarketplaceAuthenticatedServicesError,
                .invalidObjectPath
            )
        }

        let recordedUpload = await recorder.lastUpload()
        XCTAssertNil(recordedUpload)
    }
}

private struct RecordedUpload: Sendable {
    let bucket: String
    let path: String
    let data: Data
    let contentType: String
    let cacheControl: String
}

private actor UploadRecorder {
    private var upload: RecordedUpload?

    func record(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        cacheControl: String
    ) {
        upload = RecordedUpload(
            bucket: bucket,
            path: path,
            data: data,
            contentType: contentType,
            cacheControl: cacheControl
        )
    }

    func lastUpload() -> RecordedUpload? {
        upload
    }
}

private struct UnusedFunctionClient: FunctionClient {
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        throw FunctionClientError.invalidResponse
    }
}
