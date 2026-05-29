import XCTest
@testable import Nook

final class AXFrameMatchTests: XCTestCase {
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    func test_exactMatch() {
        let ax = [rect(100, 200, 800, 600)]
        XCTAssertTrue(AXFrameMatch.matches(rect(100, 200, 800, 600), anyOf: ax))
    }

    func test_matchWithinTolerance() {
        let ax = [rect(100, 200, 800, 600)]
        // 1pt off on each component — within the default 2pt tolerance.
        XCTAssertTrue(AXFrameMatch.matches(rect(101, 199, 799, 601), anyOf: ax))
    }

    func test_noMatchOutsideTolerance() {
        let ax = [rect(100, 200, 800, 600)]
        // The find-bar / aux-window case: shares nothing with the real window.
        XCTAssertFalse(AXFrameMatch.matches(rect(0, 0, 403, 84), anyOf: ax))
    }

    func test_emptyAXFramesNeverMatches() {
        XCTAssertFalse(AXFrameMatch.matches(rect(0, 0, 100, 100), anyOf: []))
    }

    func test_matchesAnyOfSeveral() {
        let ax = [rect(0, 0, 1591, 904), rect(0, 0, 1728, 1036)]
        XCTAssertTrue(AXFrameMatch.matches(rect(0, 0, 1728, 1036), anyOf: ax))
        XCTAssertFalse(AXFrameMatch.matches(rect(0, 0, 1051, 136), anyOf: ax))
    }
}
