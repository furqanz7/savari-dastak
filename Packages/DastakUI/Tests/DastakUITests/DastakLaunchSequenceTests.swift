import XCTest
@testable import DastakLaunchUI

final class DastakLaunchSequenceTests: XCTestCase {
    func testSequenceStartsAtFirstVideo() {
        XCTAssertEqual(DastakLaunchSequence.nextIndex(after: nil, count: 3), 0)
    }

    func testSequenceAdvancesAndWraps() {
        XCTAssertEqual(DastakLaunchSequence.nextIndex(after: 0, count: 3), 1)
        XCTAssertEqual(DastakLaunchSequence.nextIndex(after: 1, count: 3), 2)
        XCTAssertEqual(DastakLaunchSequence.nextIndex(after: 2, count: 3), 0)
    }

    func testSequenceRecoversFromInvalidStoredIndex() {
        XCTAssertEqual(DastakLaunchSequence.nextIndex(after: -1, count: 3), 0)
        XCTAssertEqual(DastakLaunchSequence.nextIndex(after: 99, count: 3), 0)
        XCTAssertEqual(DastakLaunchSequence.nextIndex(after: 0, count: 0), 0)
    }
}
