import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import MarketplaceInfrastructure
@testable import DastakUI

final class DastakMerchantValidationTests: XCTestCase {
    func testPackageRangeMatchesServerIncludingMoreThanTwenty() {
        for text in ["1", "21", "999", "1000", " 25 "] { XCTAssertNotNil(DastakMerchantValidation.packageCount(text)) }
        for text in ["", "0", "1001", "-1", "2.0", "1e2", "2x", "999999999999999999"] {
            XCTAssertNil(DastakMerchantValidation.packageCount(text), text)
        }
        XCTAssertEqual(DastakMerchantValidation.packageRange, 1...1000)
    }
    func testPriceParserRejectsPartialNumbersAndExplainsItsUpperLimit() {
        for text in ["1abc", "1e2", "+5", "1,000", "1.000", "NaN", "Infinity", "1000000.01"] {
            XCTAssertThrowsError(try DastakMerchantPriceParser.paise(from: text), text)
            XCTAssertNil(DastakMerchantPriceParser.optionalPaise(from: text))
        }
        XCTAssertEqual(try DastakMerchantPriceParser.paise(from: " 1000000.00 "), 100_000_000)
        XCTAssertEqual(try DastakMerchantPriceParser.paise(from: "0.01"), 1)
        XCTAssertEqual(DastakMerchantPriceParser.optionalNonnegativePaise(from: "0"), 0)
        XCTAssertTrue(DastakMerchantValidation.priceHelp.contains("10,00,000"))
    }
    func testMenuNamesDescriptionsAndChoiceLimitsHaveActionableIssues() {
        let id = UUID()
        XCTAssertNotNil(DastakMerchantValidation.menuIssue(.category(name: " ", description: "", sortOrder: 0, status: "ACTIVE")))
        XCTAssertNotNil(DastakMerchantValidation.menuIssue(.category(name: "Tea", description: String(repeating: "a", count: 501), sortOrder: 0, status: "ACTIVE")))
        XCTAssertNotNil(DastakMerchantValidation.menuIssue(.item(categoryID: id, name: "Tea", description: "", imageKey: "", basePricePaise: 0, taxRateBps: 0, logisticsAttributes: .init(), status: "ACTIVE")))
        XCTAssertNotNil(DastakMerchantValidation.menuIssue(.optionGroup(menuItemID: id, name: "Extras", selectionType: "SINGLE", minimumSelections: 0, maximumSelections: 2, sortOrder: 0, status: "ACTIVE")))
        XCTAssertNotNil(DastakMerchantValidation.menuIssue(.optionGroup(menuItemID: id, name: "Extras", selectionType: "MULTIPLE", minimumSelections: 3, maximumSelections: 2, sortOrder: 0, status: "ACTIVE")))
        XCTAssertNil(DastakMerchantValidation.menuIssue(.option(optionGroupID: id, name: "Free cream", priceDeltaPaise: 0, sortOrder: 0, status: "ACTIVE")))
        XCTAssertNil(DastakMerchantValidation.menuIssue(.optionGroup(menuItemID: id, name: "Extras", selectionType: "MULTIPLE", minimumSelections: 0, maximumSelections: 25, sortOrder: 0, status: "ACTIVE")))
    }
    func testDecodedPNGAndJPEGKeepTheirActualBytesAndType() throws {
        for type in [UTType.png, .jpeg] {
            let original = try encodedPhoto(type)
            let prepared = try DastakMerchantPhoto.prepare(original, purpose: .catalogue)
            XCTAssertEqual(prepared.data, original); XCTAssertFalse(prepared.converted)
            XCTAssertEqual(prepared.contentType, type.preferredMIMEType)
            XCTAssertEqual(DastakMerchantImageInspector.inspect(original)?.contentType, prepared.contentType)
        }
    }
    func testHEICIsConvertedToAnOrientedJPEGWithoutCopyingLocationMetadata() throws {
        let original = try encodedPhoto(.heic, rotated: true)
        let prepared = try DastakMerchantPhoto.prepare(original, purpose: .catalogue)
        XCTAssertTrue(prepared.converted); XCTAssertEqual(prepared.contentType, "image/jpeg")
        XCTAssertEqual(prepared.fileExtension, "jpg"); XCTAssertLessThanOrEqual(prepared.data.count, 5 * 1_024 * 1_024)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 20)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 40)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(DastakMerchantImageInspector.inspect(original), "Unconverted HEIC must not be relabelled JPEG")
        XCTAssertEqual(DastakMerchantImageInspector.inspect(prepared.data)?.contentType, "image/jpeg")
    }
    func testReadyEvidenceRetainsSupportedHEICWithoutConversion() throws {
        let original = try encodedPhoto(.heic)
        let prepared = try DastakMerchantPhoto.prepare(original, purpose: .ready)
        XCTAssertEqual(prepared.data, original); XCTAssertFalse(prepared.converted)
        XCTAssertEqual(prepared.contentType, "image/heic"); XCTAssertEqual(prepared.fileExtension, "heic")
    }
    func testCorruptAndUnsupportedPhotosAreExplainedRatherThanSilentlyIgnored() throws {
        for bytes in [Data(), Data("not an image".utf8), Data([0x89, 0x50, 0x4E, 0x47])] {
            XCTAssertThrowsError(try DastakMerchantPhoto.prepare(bytes, purpose: .catalogue)) { error in
                XCTAssertFalse(DastakMerchantPhoto.failureMessage(error).isEmpty)
            }
        }
        XCTAssertThrowsError(try DastakMerchantPhoto.prepare(encodedPhoto(.gif), purpose: .catalogue)) {
            XCTAssertEqual($0 as? DastakMerchantPhotoError, .unsupported)
        }
        XCTAssertThrowsError(try DastakMerchantPhoto.prepare(encodedPhoto(.gif), purpose: .ready)) {
            XCTAssertEqual($0 as? DastakMerchantPhotoError, .unsupportedReady)
        }
    }
    func testSizeLimitsAreCheckedBeforeLargeImageDecode() {
        XCTAssertThrowsError(try DastakMerchantPhoto.prepare(Data(repeating: 0, count: 20 * 1_024 * 1_024 + 1), purpose: .catalogue)) {
            XCTAssertEqual($0 as? DastakMerchantPhotoError, .tooLarge(20))
        }
        XCTAssertThrowsError(try DastakMerchantPhoto.prepare(Data(repeating: 0, count: 10 * 1_024 * 1_024 + 1), purpose: .ready)) {
            XCTAssertEqual($0 as? DastakMerchantPhotoError, .tooLarge(10))
        }
    }
    func testMissingPhotoDataAndNonCooperativeTimeoutHaveRetryGuidance() async throws {
        do { _ = try await DastakMerchantPhoto.load(purpose: .catalogue) { nil }; XCTFail() }
        catch { XCTAssertEqual(error as? DastakMerchantPhotoError, .unreadable) }
        let gate = PhotoDataGate()
        let read = Task { try await DastakMerchantPhoto.load(purpose: .catalogue, timeout: .milliseconds(40)) { await gate.load() } }
        await gate.wait()
        do { _ = try await read.value; XCTFail("A photo load owned the UI indefinitely") }
        catch { XCTAssertTrue(DastakMerchantPhoto.failureMessage(error).contains("too long")) }
        await gate.release()
    }
}
private func encodedPhoto(_ type: UTType, rotated: Bool = false) throws -> Data {
    let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.5, green: 0.2, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    let image = try XCTUnwrap(context.makeImage()), bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyOrientation: rotated ? 6 : 1,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 1.0, kCGImagePropertyGPSLatitudeRef: "N"]
    ] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return bytes as Data
}
private actor PhotoDataGate {
    private var continuation: CheckedContinuation<Data?, Never>?, started: CheckedContinuation<Void, Never>?
    func load() async -> Data? { await withCheckedContinuation { continuation = $0; started?.resume(); started = nil } }
    func wait() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func release() { continuation?.resume(returning: nil); continuation = nil }
}
