import XCTest
@testable import DastakUI

final class DastakPanelReadabilityTests: XCTestCase {
    func testApprovedDarkAppearanceRetainsAdaptiveGlass() {
        XCTAssertEqual(DastakPanelReadability.surface(isDark: true, supportsNativeGlass: true,
            reduceTransparency: false, increasedContrast: false), .adaptiveGlass)
    }

    func testLightAppearanceUsesClearGlassWithOnlyASubtleNativeTint() {
        XCTAssertEqual(DastakPanelReadability.surface(isDark: false, supportsNativeGlass: true,
            reduceTransparency: false, increasedContrast: false), .clearGlass)
        XCTAssertGreaterThan(DastakPanelReadability.lightGlassTintOpacity, 0)
        XCTAssertLessThanOrEqual(DastakPanelReadability.lightGlassTintOpacity, 0.1)
    }

    func testAccessibilityPreferencesRetainOpaqueFallback() {
        for (reduceTransparency, increasedContrast) in [(true, false), (false, true), (true, true)] {
            for isDark in [false, true] {
                XCTAssertEqual(DastakPanelReadability.surface(isDark: isDark, supportsNativeGlass: true,
                    reduceTransparency: reduceTransparency, increasedContrast: increasedContrast), .opaque)
            }
        }
    }

    func testLightAvailabilityNoticeDoesNotCoverGlassWithAnOpaqueBar() {
        XCTAssertGreaterThan(DastakPanelReadability.lightNoticeOpacity, 0)
        XCTAssertLessThanOrEqual(DastakPanelReadability.lightNoticeOpacity, 0.5)
    }

    func testOlderOperatingSystemsRetainOpaqueFallback() {
        for isDark in [false, true] {
            XCTAssertEqual(DastakPanelReadability.surface(isDark: isDark, supportsNativeGlass: false,
                reduceTransparency: false, increasedContrast: false), .opaque)
        }
    }
}
