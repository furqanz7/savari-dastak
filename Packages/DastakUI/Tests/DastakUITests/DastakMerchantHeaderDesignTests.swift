import ImageIO
import SwiftUI
import XCTest
import MarketplaceDesignSystem
@testable import DastakUI

@MainActor
final class DastakMerchantHeaderDesignTests: XCTestCase {
    func testLongStoreNameGrowsInsteadOfBeingClippedAtNarrowWidths() throws {
        let header = DastakMerchantStoreHeading(name: "The Corner Kitchen & Coffee House",
            service: "Restaurant / Café", symbol: "fork.knife", presentation: .orders, refresh: {})
        let wide = try render(header, width: 360)
        let narrow = try render(header, width: 180)
        XCTAssertEqual(narrow.width, 180)
        XCTAssertGreaterThan(narrow.height, wide.height)
    }

    func testEveryPresentationRendersWithLightDarkAndAccessibilityEnvironments() throws {
        for presentation in DastakMerchantStoreHeading.Presentation.allCases {
            for scheme: ColorScheme in [.light, .dark] {
                let header = DastakMerchantStoreHeading(name: "Craft", service: "Restaurant / Café",
                    symbol: "fork.knife", presentation: presentation, refresh: {})
                let image = try render(header.environment(\.dynamicTypeSize, .accessibility3), width: 180, scheme: scheme)
                XCTAssertEqual(image.width, 180)
                XCTAssertGreaterThanOrEqual(image.height, 44)
            }
        }
    }

    func testCompactIdentityDoesNotReintroduceABannerSizedBlock() throws {
        let header = DastakMerchantStoreHeading(name: "Craft", service: "Restaurant / Café",
            symbol: "fork.knife", refresh: {})
        let image = try render(header, width: 320)
        XCTAssertGreaterThanOrEqual(image.height, 44)
        XCTAssertLessThan(image.height, 80)
    }

    func testRenderOrdersHeaderComposition() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let heading = DastakMerchantStoreHeading(name: "Craft", service: "Restaurant / Café",
                symbol: "fork.knife", presentation: .orders, refresh: {})
            let page = VStack(alignment: .leading, spacing: 20) {
                heading
                DastakMerchantDeskOverview(incoming: 2, preparing: 3, ready: 1, selection: .constant(.all))
                DastakMerchantQueuePicker(selection: .constant(.all))
                Text("Needs your response").font(.title3.weight(.semibold))
                if let order = try? DastakMerchantDesignSamples.fulfilment() {
                    DastakMerchantIncomingCard(number: "DSK-SAMPLE-001", branch: "Craft", lines: order.lines,
                        productSubtotalPaise: order.productSubtotalPaise, expiresAt: nil, prepOptions: [10, 15, 20, 30],
                        isFood: true, subset: false, busy: false, canRespond: false, openDetail: {}) { _, _, _ in }
                }
            }.padding(18)
            let image = try render(page, width: 393, scheme: scheme)
            XCTAssertEqual(image.width, 393)
            try exportIfRequested(image, name: scheme == .dark ? "orders-dark.png" : "orders-light.png")
            try exportIfRequested(try render(heading.padding(18), width: 393, scheme: scheme),
                name: scheme == .dark ? "orders-header-dark.png" : "orders-header-light.png")
        }
        for presentation in [DastakMerchantStoreHeading.Presentation.menu, .catalogue] {
            let name = presentation == .menu ? "Craft" : "Everyday Essentials"
            let header = DastakMerchantStoreHeading(name: name,
                service: presentation == .menu ? "Restaurant / Café" : "Grocery",
                symbol: presentation == .menu ? "fork.knife" : "storefront", presentation: presentation, refresh: {})
            try exportIfRequested(try render(header.padding(18), width: 393),
                name: presentation == .menu ? "menu-header-light.png" : "catalogue-header-light.png")
        }
    }

    // Real SwiftUI components, local sample data, no navigation/system-bar pass
    // implied. macOS does not reproduce native iOS Dynamic Type scaling.
    private func render<V: View>(_ view: V, width: CGFloat, scheme: ColorScheme = .light) throws -> CGImage {
        let content = view.frame(width: width)
            .foregroundStyle(MarketplaceColors.primaryText(for: scheme))
            .background(MarketplaceColors.canvas(for: scheme))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func exportIfRequested(_ image: CGImage, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["DASTAK_MERCHANT_HEADER_PREVIEWS"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
