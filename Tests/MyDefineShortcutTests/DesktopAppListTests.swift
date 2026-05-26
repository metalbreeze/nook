import XCTest
@testable import MyDefineShortcut

final class DesktopAppListTests: XCTestCase {
    private func win(_ pid: pid_t, layer: Int = 0, onScreen: Bool = true) -> RawAppWindow {
        RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen)
    }

    func test_dedupsAndPreservesZOrder() {
        // z-order front-to-back: app 10, app 20, app 10 again, app 30
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
}
