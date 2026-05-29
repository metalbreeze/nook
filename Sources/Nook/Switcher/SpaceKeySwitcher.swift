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

    /// Posts `|delta|` Ctrl+Arrow keystrokes (rightward if delta > 0).
    static func postSteps(_ delta: Int) {
        guard delta != 0 else { return }
        for _ in 0..<abs(delta) { postStep(rightward: delta > 0) }
    }

    /// Posts one Ctrl+Arrow keystroke by asking System Events to perform it.
    /// `CGEventPost`-injected events are filtered out by WindowServer for Space
    /// switching; routing the keystroke through System Events (an Apple process
    /// Nook is authorized to control via the Automation TCC grant) injects it on
    /// a path that may be honored. Requires the apple-events entitlement +
    /// NSAppleEventsUsageDescription + the user's Automation approval.
    static func postStep(rightward: Bool) {
        let code = rightward ? 124 : 123
        let source = "tell application \"System Events\" to key code \(code) using control down"
        guard let script = NSAppleScript(source: source) else {
            Log.hotkey.error("SpaceKeySwitcher: could not build AppleScript")
            return
        }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        if let err {
            Log.hotkey.error("SpaceKeySwitcher AppleScript error: \(err, privacy: .public)")
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
