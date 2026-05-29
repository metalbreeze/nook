import XCTest
@testable import Nook

final class SwitcherCommitTests: XCTestCase {
    private let s1: CGSSpaceID = 1001
    private let s2: CGSSpaceID = 1002
    private let uuid = "UUID-DISPLAY-A"

    // MARK: window has precedence over everything

    func test_validWindowIndex_isWindow_evenWhenPreviewMatchesReal() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: 0, windowCount: 3,
                previewedSpaceID: s1, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .window(0)
        )
    }

    func test_validWindowIndex_isWindow_evenWhenPreviewDiffersFromReal() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: 2, windowCount: 5,
                previewedSpaceID: s2, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .window(2)
        )
    }

    // MARK: switchSpace when previewed differs from real

    func test_previewDiffersFromReal_isSwitchSpace() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 0,
                previewedSpaceID: s2, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .switchSpace(s2, displayUUID: uuid)
        )
    }

    func test_previewDiffersFromReal_isSwitchSpace_evenWithOutOfRangeWindowIndex() {
        // Out-of-range selectedWindowIndex falls through to the preview check.
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: 5, windowCount: 3,
                previewedSpaceID: s2, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .switchSpace(s2, displayUUID: uuid)
        )
    }

    // MARK: app when no window selected and preview == real

    func test_noWindowSelected_previewEqualsReal_isApp() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 3,
                previewedSpaceID: s1, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .app
        )
    }

    // MARK: app when state is degenerate (nil previewed or real)

    func test_nilPreview_isApp() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 0,
                previewedSpaceID: nil, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .app
        )
    }

    func test_nilReal_isApp() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 0,
                previewedSpaceID: s2, realSpaceID: nil, previewedDisplayUUID: uuid
            ),
            .app
        )
    }

    func test_nilUUID_isApp() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 0,
                previewedSpaceID: s2, realSpaceID: s1, previewedDisplayUUID: nil
            ),
            .app
        )
    }
}
