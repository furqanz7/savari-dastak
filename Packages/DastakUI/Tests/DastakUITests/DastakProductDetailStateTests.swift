import XCTest
@testable import DastakUI

final class DastakProductDetailStateTests: XCTestCase {
    func testPickerCentersSelectedProductAndCurvesSymmetrically() {
        let center = DastakProductDetailInteraction.pickerPose(distance: 0)
        XCTAssertEqual(center.scale, 1)
        XCTAssertEqual(center.opacity, 1)
        XCTAssertEqual(center.drop, 0)
        XCTAssertEqual(center.rotation, 0)
        let left = DastakProductDetailInteraction.pickerPose(distance: -1.5)
        let right = DastakProductDetailInteraction.pickerPose(distance: 1.5)
        XCTAssertEqual(left.scale, right.scale)
        XCTAssertEqual(left.opacity, right.opacity)
        XCTAssertEqual(left.drop, right.drop)
        XCTAssertEqual(left.rotation, -right.rotation)
        XCTAssertLessThan(left.scale, center.scale)
        XCTAssertGreaterThan(left.drop, center.drop)
    }
    private func draft(_ text: String = "20", current: Int? = 20, selected: Bool = true,
                       adding: Bool = false, stale: Bool = false, busy: Bool = false, active: Bool = true) -> DastakProductStockDraft {
        .init(text: text, currentQuantity: current, reserved: 3, selected: selected,
              addingEmptySKU: adding, stale: stale, busy: busy, active: active)
    }
    func testUnselectedSKUUsesAddAndLocksEditing() {
        XCTAssertEqual(draft(selected: false).actionTitle, "Add")
        XCTAssertTrue(draft(selected: false).canSubmit)
        XCTAssertFalse(draft(selected: false).canEdit)
    }
    func testStockSaveRequiresANumericalChangeAndResetsAfterSave() {
        XCTAssertEqual(draft().actionTitle, "Save Stock")
        XCTAssertTrue(draft().canEdit)
        XCTAssertFalse(draft().canSubmit)
        XCTAssertTrue(draft("21").canSubmit)
        XCTAssertTrue(draft("0").canSubmit)
        XCTAssertFalse(draft("020").canSubmit)
        XCTAssertFalse(draft("21", current: 21).canSubmit)
    }
    func testUntrackedCountAndReaddingZeroStock() {
        XCTAssertFalse(draft("", current: nil).canSubmit)
        XCTAssertTrue(draft("0", current: nil).canSubmit)
        XCTAssertFalse(draft("0", current: 0, selected: false, adding: true).canSubmit)
        XCTAssertTrue(draft("1", current: 0, selected: false, adding: true).canSubmit)
    }
    func testInvalidAndOverCapacityCountsCannotSave() {
        for value in ["", " ", "-1", "1.5", "1e3", "1000000", "99999999999999999999"] {
            XCTAssertFalse(draft(value).canSubmit, value)
        }
    }
    func testStaleBusyAndInactiveCardsCannotWrite() {
        XCTAssertFalse(draft("21", stale: true).canSubmit)
        XCTAssertFalse(draft("21", busy: true).canSubmit)
        XCTAssertFalse(draft("21", active: false).canSubmit)
        XCTAssertFalse(draft(selected: false, stale: true).canSubmit)
        XCTAssertFalse(draft(selected: false, busy: true).canSubmit)
        XCTAssertFalse(draft(selected: false, active: false).canSubmit)
    }
    func testOnlyIntentionalHorizontalSwipesNavigate() {
        XCTAssertEqual(DastakProductDetailInteraction.swipeStep(horizontal: -80, vertical: 10), 1)
        XCTAssertEqual(DastakProductDetailInteraction.swipeStep(horizontal: 80, vertical: 10), -1)
        XCTAssertNil(DastakProductDetailInteraction.swipeStep(horizontal: -40, vertical: 0))
        XCTAssertNil(DastakProductDetailInteraction.swipeStep(horizontal: -80, vertical: 65))
        XCTAssertNil(DastakProductDetailInteraction.swipeStep(horizontal: 0, vertical: 120))
    }
    func testProductNavigationDoesNotWrapOrAcceptMissingProducts() {
        XCTAssertEqual(DastakProductDetailInteraction.nextIndex(current: 1, count: 3, step: 1), 2)
        XCTAssertEqual(DastakProductDetailInteraction.nextIndex(current: 1, count: 3, step: -1), 0)
        XCTAssertNil(DastakProductDetailInteraction.nextIndex(current: 0, count: 3, step: -1))
        XCTAssertNil(DastakProductDetailInteraction.nextIndex(current: 2, count: 3, step: 1))
        XCTAssertNil(DastakProductDetailInteraction.nextIndex(current: -1, count: 3, step: 1))
    }
}
