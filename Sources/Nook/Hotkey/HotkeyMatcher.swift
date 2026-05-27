import CoreGraphics

enum HotkeyMatcher {
    static let downArrowKeyCode: Int64 = 125

    static func isCtrlDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == downArrowKeyCode else { return false }
        let hasControl = flags.contains(.maskControl)
        let hasOtherModifier = flags.contains(.maskShift)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskCommand)
        return hasControl && !hasOtherModifier
    }
}
