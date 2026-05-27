import XCTest
@testable import Nook

final class SwitcherIndexTests: XCTestCase {
    func test_advanceMidList() {
        XCTAssertEqual(SwitcherIndex.advance(0, count: 3), 1)
        XCTAssertEqual(SwitcherIndex.advance(1, count: 3), 2)
    }

    func test_advanceWraps() {
        XCTAssertEqual(SwitcherIndex.advance(2, count: 3), 0)
    }

    func test_reverseWraps() {
        XCTAssertEqual(SwitcherIndex.reverse(0, count: 3), 2)
        XCTAssertEqual(SwitcherIndex.reverse(2, count: 3), 1)
    }

    func test_singleItemStaysAtZero() {
        XCTAssertEqual(SwitcherIndex.advance(0, count: 1), 0)
        XCTAssertEqual(SwitcherIndex.reverse(0, count: 1), 0)
    }

    func test_zeroCountIsSafe() {
        XCTAssertEqual(SwitcherIndex.advance(0, count: 0), 0)
        XCTAssertEqual(SwitcherIndex.reverse(0, count: 0), 0)
    }
}
