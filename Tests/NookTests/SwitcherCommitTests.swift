import XCTest
@testable import Nook

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

    func test_didNavigateDesktopOverridesToNoop() {
        XCTAssertEqual(
            SwitcherCommit.resolve(selectedWindowIndex: 0,
                                   windowCount: 3,
                                   didNavigateDesktop: true),
            .noop
        )
    }

    func test_didNavigateDesktopOverridesEvenWithoutWindowSelection() {
        XCTAssertEqual(
            SwitcherCommit.resolve(selectedWindowIndex: -1,
                                   windowCount: 0,
                                   didNavigateDesktop: true),
            .noop
        )
    }

    func test_didNavigateDesktopFalseKeepsExistingBehavior() {
        XCTAssertEqual(
            SwitcherCommit.resolve(selectedWindowIndex: -1,
                                   windowCount: 2,
                                   didNavigateDesktop: false),
            .app
        )
    }
}
