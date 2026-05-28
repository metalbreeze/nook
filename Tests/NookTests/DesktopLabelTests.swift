import XCTest
@testable import Nook

final class DesktopLabelTests: XCTestCase {
    func test_namedDesktopUsesStoredName() {
        XCTAssertEqual(DesktopLabel.label(index: 1, storedName: "Work"), "1  Work")
    }

    func test_unnamedDesktopFallsBackToDesktopN() {
        XCTAssertEqual(DesktopLabel.label(index: 3, storedName: nil), "3  Desktop 3")
    }

    func test_indexIsPreservedAtSmallAndLargeValues() {
        XCTAssertEqual(DesktopLabel.label(index: 1, storedName: nil), "1  Desktop 1")
        XCTAssertEqual(DesktopLabel.label(index: 9, storedName: "Mail"), "9  Mail")
    }
}
