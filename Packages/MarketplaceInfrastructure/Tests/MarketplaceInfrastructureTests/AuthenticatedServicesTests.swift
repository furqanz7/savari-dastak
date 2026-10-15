import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class AuthenticatedServicesTests: XCTestCase {
    func testStalledSharedTokenReadExpiresAndNextRequestCanLoadFreshToken() async throws {
        let loader = StalledAccessTokenLoader()
        let broker = MarketplaceAccessTokenBroker(timeout: .milliseconds(40)) { await loader.load() }
        let first = Task { try await broker.accessToken() }
        await loader.waitUntilStarted()
        let joined = Task { try await broker.accessToken() }
        for request in [first, joined] {
            do { _ = try await request.value; XCTFail("A stalled token read must not poison every later request") }
            catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        }
        let next = try await broker.accessToken()
        XCTAssertEqual(next, "new-token")
        await loader.releaseOldRead()
        let afterLateReply = try await broker.accessToken()
        XCTAssertEqual(afterLateReply, "new-token", "A late worker cannot return an obsolete token to a newer caller")
    }

    func testAccessTokenBrokerCoalescesConcurrentSessionReads() async throws {
        let loader = AccessTokenLoader()
        let broker = MarketplaceAccessTokenBroker {
            try await loader.load()
        }

        async let first = broker.accessToken()
        async let second = broker.accessToken()
        async let third = broker.accessToken()

        let tokens = try await [first, second, third]
        XCTAssertEqual(tokens, ["coalesced-token", "coalesced-token", "coalesced-token"])
        let coalescedCallCount = await loader.calls()
        XCTAssertEqual(coalescedCallCount, 1)
    }

    func testAccessTokenBrokerRecoversAfterLoaderFailure() async throws {
        let loader = AccessTokenLoader(failsFirstCall: true)
        let broker = MarketplaceAccessTokenBroker {
            try await loader.load()
        }

        do {
            _ = try await broker.accessToken()
            XCTFail("Expected the first token load to fail.")
        } catch {
            XCTAssertEqual(error as? AccessTokenLoaderError, .unavailable)
        }

        let token = try await broker.accessToken()
        XCTAssertEqual(token, "coalesced-token")
        let recoveredCallCount = await loader.calls()
        XCTAssertEqual(recoveredCallCount, 2)
    }

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

    func testAppAccessUsesAuthenticatedResolver() async throws {
        let services = MarketplaceAuthenticatedServices(
            functions: UnusedFunctionClient(),
            accountIDProvider: { UUID() },
            objectUploader: { _, _, _, _, _ in },
            appAccessProvider: { application in
                application == .dastakMerchant ? .active : .accessDenied
            }
        )

        let merchantAccess = try await services.resolveAppAccess(.dastakMerchant)
        let adminAccess = try await services.resolveAppAccess(.dastakAdmin)
        XCTAssertEqual(merchantAccess, .active)
        XCTAssertEqual(adminAccess, .accessDenied)
    }
}

private enum AccessTokenLoaderError: Error, Equatable {
    case unavailable
}

private actor StalledAccessTokenLoader {
    private var oldRead: CheckedContinuation<String?, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var calls = 0
    func load() async -> String? {
        calls += 1
        if calls > 1 { return "new-token" }
        return await withCheckedContinuation {
            oldRead = $0; started?.resume(); started = nil
        }
    }
    func waitUntilStarted() async {
        if oldRead != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func releaseOldRead() { oldRead?.resume(returning: "old-token"); oldRead = nil }
}

private actor AccessTokenLoader {
    private var callCount = 0
    private let failsFirstCall: Bool

    init(failsFirstCall: Bool = false) {
        self.failsFirstCall = failsFirstCall
    }

    func load() async throws -> String? {
        callCount += 1
        try await Task.sleep(for: .milliseconds(20))
        if failsFirstCall, callCount == 1 {
            throw AccessTokenLoaderError.unavailable
        }
        return "coalesced-token"
    }

    func calls() -> Int {
        callCount
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
