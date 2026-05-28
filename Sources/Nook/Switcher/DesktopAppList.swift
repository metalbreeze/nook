import CoreGraphics
import Foundation

struct RawAppWindow: Equatable {
    let ownerPID: pid_t
    let layer: Int
    let isOnScreen: Bool
    let windowID: CGWindowID?

    init(ownerPID: pid_t,
         layer: Int,
         isOnScreen: Bool,
         windowID: CGWindowID? = nil) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.windowID = windowID
    }
}

enum DesktopAppList {
    /// De-duplicated app PIDs that have at least one normal (layer 0), on-screen
    /// window, in first-appearance (z-order) order, with the current app first.
    static func appPIDs(from windows: [RawAppWindow], frontmostPID: pid_t) -> [pid_t] {
        var seen = Set<pid_t>()
        var ordered: [pid_t] = []
        for window in windows where window.layer == 0 && window.isOnScreen {
            if seen.insert(window.ownerPID).inserted {
                ordered.append(window.ownerPID)
            }
        }
        return reorderFrontmost(ordered, frontmostPID: frontmostPID)
    }

    /// Same shape, but filters to windows whose ID is in `allowedWindowIDs`
    /// (used to enumerate the apps on a non-current Space, where the windowID
    /// allow-set comes from `WindowsOnSpace`). `isOnScreen` is not consulted —
    /// the allow-set is the authoritative membership signal for non-current
    /// Spaces. Windows whose `windowID` is `nil` are skipped (caller forgot to
    /// populate them).
    static func appPIDs(from windows: [RawAppWindow],
                        frontmostPID: pid_t,
                        allowedWindowIDs: Set<CGWindowID>) -> [pid_t] {
        var seen = Set<pid_t>()
        var ordered: [pid_t] = []
        for window in windows where window.layer == 0 {
            guard let id = window.windowID, allowedWindowIDs.contains(id) else { continue }
            if seen.insert(window.ownerPID).inserted {
                ordered.append(window.ownerPID)
            }
        }
        return reorderFrontmost(ordered, frontmostPID: frontmostPID)
    }

    private static func reorderFrontmost(_ ordered: [pid_t], frontmostPID: pid_t) -> [pid_t] {
        var result = ordered
        if let index = result.firstIndex(of: frontmostPID), index != 0 {
            result.remove(at: index)
            result.insert(frontmostPID, at: 0)
        }
        return result
    }
}
