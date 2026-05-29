import XCTest
@testable import Nook

final class DesktopAppListTests: XCTestCase {
    private func win(_ pid: pid_t,
                     layer: Int = 0,
                     onScreen: Bool = true,
                     windowID: CGWindowID? = nil,
                     frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)) -> RawAppWindow {
        RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen, windowID: windowID, frame: frame)
    }

    func test_dedupsAndPreservesZOrder() {
        let input = [win(10), win(20), win(10), win(30)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10, 20, 30])
    }

    func test_excludesNonZeroLayerAndOffScreen() {
        let input = [win(10), win(20, layer: 25), win(30, onScreen: false)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10])
    }

    func test_movesFrontmostToFront() {
        let input = [win(20), win(30), win(10)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10, 20, 30])
    }

    func test_frontmostNotInListLeavesOrderUnchanged() {
        let input = [win(20), win(30)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 99), [20, 30])
    }

    // --- new variant: filter by allowed windowID set ---

    func test_allowedWindowIDsFiltersOutMissing() {
        let input = [
            win(10, windowID: 101),
            win(20, windowID: 202),
            win(30, windowID: 303),
        ]
        XCTAssertEqual(
            DesktopAppList.appPIDs(from: input,
                                   frontmostPID: 0,
                                   allowedWindowIDs: [101, 303]),
            [10, 30]
        )
    }

    func test_allowedWindowIDsKeepsOnePIDEvenIfMultipleWindowsAllowed() {
        let input = [
            win(10, windowID: 101),
            win(10, windowID: 102),
            win(20, windowID: 202),
        ]
        XCTAssertEqual(
            DesktopAppList.appPIDs(from: input,
                                   frontmostPID: 20,
                                   allowedWindowIDs: [101, 102, 202]),
            [20, 10]
        )
    }

    func test_allowedWindowIDsSkipsNilWindowIDEvenIfPIDMatches() {
        // RawAppWindow with no windowID (legacy default) is excluded from the
        // allowed-set variant — the variant requires the window to be known.
        let input = [
            win(10),                     // windowID nil
            win(20, windowID: 202),
        ]
        XCTAssertEqual(
            DesktopAppList.appPIDs(from: input,
                                   frontmostPID: 0,
                                   allowedWindowIDs: [202]),
            [20]
        )
    }

    // --- realWindowCounts ---

    func test_realWindowCounts_countsLayer0InAllowedSetMeetingMinSize() {
        let bounds = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        let input = [
            win(10, windowID: 101, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
            win(10, windowID: 102, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
            win(20, windowID: 201, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
        ]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101, 102, 201],
                                                     visibleBounds: bounds,
                                                     minSize: CGSize(width: 80, height: 80))
        XCTAssertEqual(counts[10], 2)
        XCTAssertEqual(counts[20], 1)
    }

    func test_realWindowCounts_excludesTinyOffscreenNonZeroLayerOutOfSet() {
        let bounds = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        let input = [
            win(10, windowID: 101, frame: CGRect(x: 0, y: 0, width: 10, height: 10)),     // too small
            win(10, windowID: 102, frame: CGRect(x: 9000, y: 9000, width: 200, height: 200)), // off bounds
            win(10, layer: 3, windowID: 103, frame: CGRect(x: 0, y: 0, width: 200, height: 200)), // non-zero layer
            win(10, windowID: 104, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),    // not in allowed set
            win(10, windowID: 105, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),    // OK
        ]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101, 102, 103, 105],
                                                     visibleBounds: bounds,
                                                     minSize: CGSize(width: 80, height: 80))
        XCTAssertEqual(counts[10], 1) // only windowID 105 qualifies
    }

    func test_realWindowCounts_emptyWhenNothingQualifies() {
        let counts = DesktopAppList.realWindowCounts(from: [win(10, windowID: 101, frame: CGRect(x: 0, y: 0, width: 5, height: 5))],
                                                     allowedWindowIDs: [101],
                                                     visibleBounds: CGRect(x: 0, y: 0, width: 2000, height: 2000),
                                                     minSize: CGSize(width: 80, height: 80))
        XCTAssertTrue(counts.isEmpty)
    }

    // --- realWindowCounts AX-frame filtering (auxiliary-window exclusion) ---

    private let bigBounds = CGRect(x: 0, y: 0, width: 4000, height: 4000)
    private let minWin = CGSize(width: 80, height: 80)

    func test_realWindowCounts_axFilterExcludesAuxWindow() {
        // Chrome on a Space where its only window is a 1051x136 find bar that
        // passes size/Space filters but is NOT in the app's AX window list.
        let aux = CGRect(x: 0, y: 0, width: 1051, height: 136)
        let main = CGRect(x: 0, y: 0, width: 1591, height: 904)
        let input = [
            win(10, windowID: 101, frame: aux),   // find bar — only this is on the Space
        ]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101],
                                                     visibleBounds: bigBounds,
                                                     minSize: minWin,
                                                     axFramesByPID: [10: [main]])
        XCTAssertTrue(counts.isEmpty, "aux window must not count as a real window")
    }

    func test_realWindowCounts_axFilterKeepsMatchingWindow() {
        let main = CGRect(x: 0, y: 0, width: 1591, height: 904)
        let input = [win(10, windowID: 101, frame: main)]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101],
                                                     visibleBounds: bigBounds,
                                                     minSize: minWin,
                                                     axFramesByPID: [10: [main]])
        XCTAssertEqual(counts[10], 1)
    }

    func test_realWindowCounts_pidAbsentFromAXMapIsNotFiltered() {
        // AX unavailable for this PID -> fall back to size/Space behavior.
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let input = [win(10, windowID: 101, frame: frame)]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101],
                                                     visibleBounds: bigBounds,
                                                     minSize: minWin,
                                                     axFramesByPID: [20: [frame]]) // only PID 20 present
        XCTAssertEqual(counts[10], 1)
    }

    func test_realWindowCounts_pidWithEmptyAXListIsNotFiltered() {
        // Empty AX list also means "AX unavailable" -> do not filter.
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let input = [win(10, windowID: 101, frame: frame)]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101],
                                                     visibleBounds: bigBounds,
                                                     minSize: minWin,
                                                     axFramesByPID: [10: []])
        XCTAssertEqual(counts[10], 1)
    }

    func test_realWindowCounts_nilAXMapPreservesLegacyBehavior() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let input = [win(10, windowID: 101, frame: frame)]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101],
                                                     visibleBounds: bigBounds,
                                                     minSize: minWin,
                                                     axFramesByPID: nil)
        XCTAssertEqual(counts[10], 1)
    }
}
