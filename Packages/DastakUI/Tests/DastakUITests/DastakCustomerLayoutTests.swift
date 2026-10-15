import XCTest
@testable import DastakUI

final class DastakCustomerLayoutTests: XCTestCase {
    func testShoppingPanelLeavesRoomForSceneryWithoutScalingContent() {
        let phone = DastakCustomerLayout(width: 393, height: 740, largerText: false)
        XCTAssertEqual(phone.sceneryRevealHeight, 118.4, accuracy: 0.001)
        XCTAssertEqual(phone.panelHorizontalInset, 24)
        XCTAssertEqual(phone.panelDownshift, 136.4, accuracy: 0.001)
        XCTAssertEqual(phone.panelDownshift - phone.sceneryRevealHeight, 18, accuracy: 0.001)
        XCTAssertEqual(DastakCustomerLayout(width: 320, height: 640, largerText: false).panelHorizontalInset, 16)
        XCTAssertEqual(DastakCustomerLayout(width: 768, height: 1024, largerText: false).sceneryRevealHeight, 128)
    }

    func testPanelReturnsScenerySpaceForKeyboardLandscapeAndLargeText() {
        for height in [0.0, 340, 450, 619] {
            XCTAssertEqual(DastakCustomerLayout(width: 393, height: height, largerText: false).sceneryRevealHeight, 0)
            XCTAssertEqual(DastakCustomerLayout(width: 393, height: height, largerText: false).panelDownshift, 0)
        }
        XCTAssertEqual(DastakCustomerLayout(width: 393, height: 740, largerText: true).sceneryRevealHeight, 0)
        XCTAssertEqual(DastakCustomerLayout(width: 393, height: 740, largerText: true).panelDownshift, 0)
    }

    func testNormalPhonePortraitUsesCompactNavigation() {
        for width in [350.0, 375, 390, 393, 430, 440, 599] {
            let layout = DastakCustomerLayout(width: width, height: 740, largerText: false)
            XCTAssertTrue(layout.usesCompactControls)
            XCTAssertEqual(layout.inlineChromeHeight, 264)
        }
    }

    func testTabletWidthRetainsInlineNavigationWhenHeightAllows() {
        for width in [600.0, 768, 1024] {
            XCTAssertFalse(DastakCustomerLayout(width: width, height: 740, largerText: false).usesCompactControls)
        }
    }

    func testNarrowPhonesUseReachableSheetControls() {
        XCTAssertTrue(DastakCustomerLayout(width: 320, height: 640, largerText: false).usesCompactControls)
        XCTAssertTrue(DastakCustomerLayout(width: 349, height: 740, largerText: false).usesCompactControls)
    }

    func testLandscapeAndKeyboardReducedHeightUseCompactControls() {
        XCTAssertTrue(DastakCustomerLayout(width: 852, height: 340, largerText: false).usesCompactControls)
        XCTAssertTrue(DastakCustomerLayout(width: 393, height: 450, largerText: false).usesCompactControls)
        XCTAssertTrue(DastakCustomerLayout(width: 393, height: 619, largerText: false).usesCompactControls)
        XCTAssertTrue(DastakCustomerLayout(width: 393, height: 620, largerText: false).usesCompactControls)
        XCTAssertTrue(DastakCustomerLayout(width: 768, height: 619, largerText: false).usesCompactControls)
        XCTAssertFalse(DastakCustomerLayout(width: 768, height: 620, largerText: false).usesCompactControls)
    }

    func testLargeTextUsesFullHeightScrollableControlSheets() {
        XCTAssertTrue(DastakCustomerLayout(width: 430, height: 900, largerText: true).usesCompactControls)
        XCTAssertTrue(DastakCustomerLayout(width: 1024, height: 900, largerText: true).usesCompactControls)
    }

    func testUnavailableGeometryNeverProducesNegativeChromeHeight() {
        XCTAssertEqual(DastakCustomerLayout(width: 0, height: 0, largerText: false).inlineChromeHeight, 0)
        XCTAssertEqual(DastakCustomerLayout(width: 0, height: -10, largerText: false).inlineChromeHeight, 0)
    }

    func testControlSheetsHaveDistinctStableIdentityAndEnglishTitles() {
        XCTAssertNotEqual(DastakCustomerControlSheet.navigation.id, DastakCustomerControlSheet.services.id)
        XCTAssertEqual(DastakCustomerControlSheet.navigation.title, "Dastak navigation")
        XCTAssertEqual(DastakCustomerControlSheet.services.title, "Services and aisles")
    }
}
