import CoreGraphics
import Foundation

/// Switches Spaces by simulating the Mission Control "Move left/right a space"
/// keyboard shortcut (Ctrl+←/→).
///
/// Why not CGSManagedDisplaySetCurrentSpace? On current macOS that private call
/// only takes effect from a process injected into Dock (the yabai / SIP-disabled
/// approach). From a normally-signed app it is a silent no-op — it updates no
/// visible Space. Synthesizing the system shortcut is the only mechanism a
/// regular app has. Requires the shortcut to be enabled (it is by default) and
/// Accessibility permission (which Nook already needs for its event tap).
enum SpaceKeySwitcher {
    private static let leftArrow: CGKeyCode = 123
    private static let rightArrow: CGKeyCode = 124

    /// Signed number of Mission Control steps from `current` to `target` along
    /// the display's ordered Space list (positive = rightward). 0 if they're the
    /// same or either isn't found on a common display.
    static func steps(from current: CGSSpaceID, to target: CGSSpaceID) -> Int {
        let ordered = orderedSpaceIDs(containing: current)
        guard let ci = ordered.firstIndex(of: current),
              let ti = ordered.firstIndex(of: target) else { return 0 }
        return ti - ci
    }

    /// Posts one Ctrl+Arrow keystroke (rightward or leftward).
    static func postStep(rightward: Bool) {
        let key = rightward ? rightArrow : leftArrow
        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) {
            down.flags = .maskControl
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) {
            up.flags = .maskControl
            up.post(tap: .cghidEventTap)
        }
    }

    /// Full ordered list of ManagedSpaceIDs (all Space types, in Mission Control
    /// order) for the display whose Space set contains `spaceID`. Ctrl+Arrow
    /// steps through every Space in this order, so the count must include
    /// fullscreen/system Spaces too.
    private static func orderedSpaceIDs(containing spaceID: CGSSpaceID) -> [CGSSpaceID] {
        let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as NSArray
        for case let display as [String: Any] in raw {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
            if ids.contains(spaceID) { return ids }
        }
        return []
    }
}
