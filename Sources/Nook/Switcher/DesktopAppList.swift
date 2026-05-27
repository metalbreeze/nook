import Foundation

struct RawAppWindow: Equatable {
    let ownerPID: pid_t
    let layer: Int
    let isOnScreen: Bool
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
        if let index = ordered.firstIndex(of: frontmostPID), index != 0 {
            ordered.remove(at: index)
            ordered.insert(frontmostPID, at: 0)
        }
        return ordered
    }
}
