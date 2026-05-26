import XCTest
@testable import MyDefineShortcut

final class SwitcherCommitTests: XCTestCase {
    func test_noWindowSelected_isApp() {
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: -1, windowCount: 3), .app)
    }

    func test_validWindowIndex_isThatWindow() {
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: 0, windowCount: 3), .window(0))
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: 2, windowCount: 3), .window(2))
    }

    func test_outOfRangeIndex_isApp() {
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: 5, windowCount: 3), .app)
    }

    func test_emptyWindows_isApp() {
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: 0, windowCount: 0), .app)
    }
}
