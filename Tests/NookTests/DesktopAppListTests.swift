import XCTest
@testable import Nook

final class DesktopAppListTests: XCTestCase {
    private func win(_ pid: pid_t,
                     layer: Int = 0,
                     onScreen: Bool = true,
                     windowID: CGWindowID? = nil) -> RawAppWindow {
        RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen, windowID: windowID)
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
}
