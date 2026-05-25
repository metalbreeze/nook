import XCTest
import CoreGraphics
@testable import MyDefineShortcut

final class WindowMatcherTests: XCTestCase {
    private func target(title: String = "Doc", x: CGFloat = 100, y: CGFloat = 100,
                        w: CGFloat = 800, h: CGFloat = 600) -> WindowInfo {
        WindowInfo(windowID: 1, title: title, frame: CGRect(x: x, y: y, width: w, height: h), appName: "App")
    }

    func test_prefersExactFrameMatch() {
        let candidates = [
            AXWindowCandidate(index: 0, title: "Other", frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
            AXWindowCandidate(index: 1, title: "Other", frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
        ]
        XCTAssertEqual(WindowMatcher.bestMatch(for: target(), among: candidates), 1)
    }

    func test_fallsBackToTitleWhenNoFrameMatch() {
        let candidates = [
            AXWindowCandidate(index: 0, title: "Doc", frame: CGRect(x: 5, y: 5, width: 10, height: 10)),
            AXWindowCandidate(index: 1, title: "Nope", frame: CGRect(x: 9, y: 9, width: 10, height: 10)),
        ]
        XCTAssertEqual(WindowMatcher.bestMatch(for: target(title: "Doc"), among: candidates), 0)
    }

    func test_fallsBackToNearestOriginWhenNoFrameOrTitleMatch() {
        let candidates = [
            AXWindowCandidate(index: 0, title: "", frame: CGRect(x: 500, y: 500, width: 10, height: 10)),
            AXWindowCandidate(index: 1, title: "", frame: CGRect(x: 110, y: 110, width: 10, height: 10)),
        ]
        XCTAssertEqual(WindowMatcher.bestMatch(for: target(title: ""), among: candidates), 1)
    }

    func test_returnsNilForEmptyCandidates() {
        XCTAssertNil(WindowMatcher.bestMatch(for: target(), among: []))
    }
}
