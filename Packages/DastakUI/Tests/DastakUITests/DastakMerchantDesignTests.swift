import XCTest
import SwiftUI
@testable import DastakUI

@MainActor
final class DastakMerchantDesignTests: XCTestCase {
    func testHeadingGrowsWhenWidthNarrowsInsteadOfClippingToAFixedHeight() throws {
        let heading = DastakMerchantHeading(eyebrow: "THE ORDER DESK", title: "Good things, in motion.",
            subtitle: "From the first request to the final handoff.", symbol: "storefront")
        let normal = try image(heading, size: .large)
        let narrow = try image(heading, size: .accessibility3, width: 180)
        XCTAssertEqual(normal.width, 320)
        XCTAssertGreaterThan(narrow.height, normal.height)
    }

    func testMerchantActionRetainsMinimumHeightAndWrapsLargeLabels() throws {
        let button = Button("Confirm every package and mark this order ready") {}
            .buttonStyle(DastakMerchantActionStyle(primary: true))
        let normal = try image(button, size: .large)
        let narrow = try image(button, size: .accessibility3, width: 120)
        XCTAssertGreaterThanOrEqual(normal.height, 48)
        XCTAssertGreaterThan(narrow.height, normal.height)
        XCTAssertEqual(narrow.width, 120)
    }

    func testLocalGalleryDataHasEveryLineAndNoReadyAuthorization() throws {
        let order = try DastakMerchantDesignSamples.fulfilment()
        XCTAssertEqual(order.lines.count, 4)
        XCTAssertEqual(Set(order.lines.map(\.id)).count, 4)
        XCTAssertEqual(order.lines.reduce(0) { $0 + ($1.lineSubtotalPaise ?? 0) }, order.productSubtotalPaise)
        XCTAssertFalse(order.canMarkReady)
        XCTAssertNil(order.delivery)
        XCTAssertTrue(order.displayOrderNumber.contains("SAMPLE"))
    }

    // macOS does not scale iOS Dynamic Type. These are wrapping/minimum-height
    // checks only; native accessibility scaling is checked in the simulator.
    private func image<V: View>(_ view: V, size: DynamicTypeSize, width: CGFloat = 320) throws -> CGImage {
        let renderer = ImageRenderer(content: view.environment(\.dynamicTypeSize, size).frame(width: width))
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }
}
