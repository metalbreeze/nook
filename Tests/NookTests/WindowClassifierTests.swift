import XCTest
@testable import Nook

final class WindowClassifierTests: XCTestCase {
    private func input(real: Int, minimized: Int, hidden: Bool) -> WindowClassifier.ClassifierInput {
        WindowClassifier.ClassifierInput(pid: 42,
                                         realWindowCount: real,
                                         minimizedWindowCount: minimized,
                                         isHidden: hidden)
    }

    func test_hidden_isParkedWithItsWindowCount() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 3, minimized: 0, hidden: true)),
                       .parked(windowCount: 3))
    }

    func test_hidden_withZeroWindows_isParkedZero() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 0, minimized: 0, hidden: true)),
                       .parked(windowCount: 0))
    }

    func test_hasRealWindows_isActive() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 2, minimized: 0, hidden: false)),
                       .active)
    }

    func test_onlyMinimizedWindows_isParkedWithCount() {
        // An app whose windows on this desktop are all minimized / hidden parks
        // at the end, badged with how many it has stashed.
        XCTAssertEqual(WindowClassifier.classify(input(real: 0, minimized: 2, hidden: false)),
                       .parked(windowCount: 2))
    }

    func test_hasRealWindows_evenWithMinimized_isActive() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 1, minimized: 3, hidden: false)),
                       .active)
    }

    func test_noRealNoMinimizedNotHidden_isParkedZero() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 0, minimized: 0, hidden: false)),
                       .parked(windowCount: 0))
    }
}
