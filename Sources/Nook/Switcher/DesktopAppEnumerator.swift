import AppKit
import CoreGraphics

enum DesktopAppEnumerator {
    /// Apps with at least one normal window on the current desktop, current app
    /// first, in window z-order. Excludes this process. No Screen Recording needed.
    static func currentDesktopApps() -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = onScreenWindows()
        let pids = DesktopAppList.appPIDs(from: raw, frontmostPID: frontmostPID)
        return pids.compactMap { pid in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            return SwitcherApp(pid: pid, name: app.localizedName ?? "", icon: app.icon)
        }
    }

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
}
