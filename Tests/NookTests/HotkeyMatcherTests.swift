import XCTest
import CoreGraphics
@testable import Nook

final class HotkeyMatcherTests: XCTestCase {
    func test_matchesControlDownArrow() {
        XCTAssertTrue(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: [.maskControl]))
    }

    func test_rejectsWrongKeyCode() {
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 126, flags: [.maskControl]))
    }

    func test_rejectsControlPlusOtherModifier() {
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: [.maskControl, .maskShift]))
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: [.maskControl, .maskCommand]))
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: [.maskControl, .maskAlternate]))
    }

    func test_rejectsNoControl() {
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: []))
    }

    func test_ignoresDeviceIndependentNoiseBits() {
        let flags: CGEventFlags = [.maskControl, .maskNonCoalesced]
        XCTAssertTrue(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: flags))
    }
}
