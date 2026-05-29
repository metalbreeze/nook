import AppKit
import CoreGraphics

enum DesktopAppEnumerator {
    /// Apps with at least one normal window on the current desktop, current app
    /// first, in window z-order, with all hidden (Cmd+H) running apps appended
    /// at the end. Excludes this process.
    static func currentDesktopApps() -> [SwitcherApp] {
        if let currentSpaceID = CurrentSpace.id() {
            return appsOnSpace(currentSpaceID)
        }
        // Fallback when CGS can't tell us the current Space.
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = onScreenWindows()
        let pids = DesktopAppList.appPIDs(from: raw, frontmostPID: frontmostPID)
        let visible = pids.compactMap(makeApp(pid:)).filter { !$0.isHidden }
        return visible + hiddenRunningApps()
    }

    /// Apps with at least one normal window on `spaceID`, with the current
    /// frontmost app first if it has a window there, plus all hidden (Cmd+H)
    /// running apps appended at the end. Hidden apps are sourced from
    /// `NSWorkspace.runningApplications` rather than per-Space CGS
    /// enumeration — CGS sometimes doesn't report Spaces for windows of
    /// hidden apps, so a Space-only path can drop them entirely. The view
    /// renders the trailing hidden group differently so they don't visually
    /// compete with the navigable visible group.
    static func appsOnSpace(_ spaceID: CGSSpaceID) -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = allSpacesWindows()
        let allowed = WindowsOnSpace.windowIDs(on: spaceID)
        let pids = DesktopAppList.appPIDs(from: raw,
                                          frontmostPID: frontmostPID,
                                          allowedWindowIDs: allowed)
        let visibleOnSpace = pids.compactMap(makeApp(pid:)).filter { !$0.isHidden }
        return visibleOnSpace + hiddenRunningApps()
    }

    /// All currently-hidden regular apps, sorted by name for a stable order.
    /// They appear on every desktop's chip-row tail since their actual Space
    /// affiliation is unreliable while hidden.
    private static func hiddenRunningApps() -> [SwitcherApp] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter {
                $0.isHidden &&
                $0.activationPolicy == .regular &&
                $0.processIdentifier > 0 &&
                $0.processIdentifier != selfPID
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            .map { SwitcherApp(pid: $0.processIdentifier,
                               name: $0.localizedName ?? "",
                               icon: $0.icon,
                               isHidden: true) }
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
        return SwitcherApp(pid: pid,
                           name: app.localizedName ?? "",
                           icon: app.icon,
                           isHidden: app.isHidden)
    }
}
