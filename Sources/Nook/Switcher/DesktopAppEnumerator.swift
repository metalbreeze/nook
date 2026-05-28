import AppKit
import CoreGraphics

enum DesktopAppEnumerator {
    /// Apps with at least one normal window on the current desktop, current app
    /// first, in window z-order. Excludes this process. No Screen Recording needed.
    static func currentDesktopApps() -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = onScreenWindows()
        let pids = DesktopAppList.appPIDs(from: raw, frontmostPID: frontmostPID)
        return pids.compactMap(makeApp(pid:))
    }

    /// Apps with at least one normal window on `spaceID`, in window z-order,
    /// with the current frontmost app first if it has a window there. Uses
    /// `WindowsOnSpace` (private CGS) to compute the allow-set; the frontmost
    /// signal is the same as for `currentDesktopApps()` and is only useful when
    /// `spaceID` is the active Space (otherwise the frontmost is unlikely to
    /// own a window there, so the call falls through to z-order).
    static func appsOnSpace(_ spaceID: CGSSpaceID) -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = allSpacesWindows()
        let allowed = WindowsOnSpace.windowIDs(on: spaceID)
        let pids = DesktopAppList.appPIDs(from: raw,
                                          frontmostPID: frontmostPID,
                                          allowedWindowIDs: allowed)
        return pids.compactMap(makeApp(pid:))
    }

    /// On-screen (current Space) windows, with off-screen mid-Space-switch
    /// windows filtered out via the visible-bounds intersection.
    private static func onScreenWindows() -> [RawAppWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let visibleBounds = DisplayBounds.union()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != selfPID else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            // A window mid Space-switch has slid off all displays; mark it off-screen so
            // DesktopAppList's isOnScreen filter excludes its app (no other-desktop leakage).
            let onScreen: Bool
            if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
               let frame = CGRect(dictionaryRepresentation: boundsDict) {
                onScreen = frame.intersects(visibleBounds)
            } else {
                onScreen = true
            }
            let windowID: CGWindowID? = (info[kCGWindowNumber as String] as? NSNumber)
                .map { CGWindowID($0.uint32Value) }
            return RawAppWindow(ownerPID: pid,
                                layer: layer,
                                isOnScreen: onScreen,
                                windowID: windowID)
        }
    }

    /// All windows across all Spaces. `isOnScreen` is set to `true` so callers
    /// using the `allowedWindowIDs` variant don't accidentally reject by the
    /// legacy filter. This process is excluded.
    private static func allSpacesWindows() -> [RawAppWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != selfPID else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let windowID: CGWindowID? = (info[kCGWindowNumber as String] as? NSNumber)
                .map { CGWindowID($0.uint32Value) }
            return RawAppWindow(ownerPID: pid,
                                layer: layer,
                                isOnScreen: true,
                                windowID: windowID)
        }
    }

    private static func makeApp(pid: pid_t) -> SwitcherApp? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return SwitcherApp(pid: pid, name: app.localizedName ?? "", icon: app.icon)
    }
}
