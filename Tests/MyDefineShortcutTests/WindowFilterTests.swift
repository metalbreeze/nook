import XCTest
import CoreGraphics
@testable import MyDefineShortcut

final class WindowFilterTests: XCTestCase {
    private func raw(id: CGWindowID, pid: pid_t, layer: Int = 0, onScreen: Bool = true,
                     w: CGFloat = 800, h: CGFloat = 600, title: String = "T", app: String = "App") -> RawWindow {
        RawWindow(windowID: id, ownerPID: pid, layer: layer, isOnScreen: onScreen,
                  title: title, appName: app, frame: CGRect(x: 0, y: 0, width: w, height: h))
    }

    func test_keepsOnlyFrontmostAppWindows() {
        let input = [raw(id: 1, pid: 100), raw(id: 2, pid: 200), raw(id: 3, pid: 100)]
        let result = WindowFilter.visibleWindows(from: input, frontmostPID: 100)
        XCTAssertEqual(result.map(\.windowID), [1, 3])
    }

    func test_dropsOffScreenNonZeroLayerAndTinyWindows() {
        let input = [
            raw(id: 1, pid: 100),
            raw(id: 2, pid: 100, onScreen: false),
            raw(id: 3, pid: 100, layer: 25),
            raw(id: 4, pid: 100, w: 10, h: 10),
        ]
        let result = WindowFilter.visibleWindows(from: input, frontmostPID: 100)
        XCTAssertEqual(result.map(\.windowID), [1])
    }

    func test_countAndMetadataPreserved() {
        let input = [raw(id: 7, pid: 100, title: "Doc", app: "Safari")]
        let result = WindowFilter.visibleWindows(from: input, frontmostPID: 100)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Doc")
        XCTAssertEqual(result.first?.appName, "Safari")
    }

    func test_dropsWindowsOutsideVisibleBounds() {
        // Single display at the origin. A window mid-Space-switch has slid off to
        // negative X and must be excluded; the on-screen one is kept.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let onScreen = RawWindow(windowID: 1, ownerPID: 100, layer: 0, isOnScreen: true,
                                 title: "On", appName: "App",
                                 frame: CGRect(x: 213, y: 79, width: 1313, height: 794))
        let offScreen = RawWindow(windowID: 2, ownerPID: 100, layer: 0, isOnScreen: true,
                                  title: "Off", appName: "App",
                                  frame: CGRect(x: -1565, y: 79, width: 1313, height: 794))
        let result = WindowFilter.visibleWindows(from: [onScreen, offScreen],
                                                 frontmostPID: 100, visibleBounds: screen)
        XCTAssertEqual(result.map(\.windowID), [1])
    }
}
