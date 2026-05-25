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
}
