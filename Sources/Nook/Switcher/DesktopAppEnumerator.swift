import AppKit
import CoreGraphics

enum DesktopAppEnumerator {
    private static let minWindowSize = CGSize(width: 80, height: 80)

    /// Apps on the current desktop: active apps (z-order, frontmost first) then
    /// parked apps (Cmd+H or window-less), each parked icon carrying a window
    /// count. Excludes this process.
    static func currentDesktopApps() -> [SwitcherApp] {
        if let currentSpaceID = CurrentSpace.id() {
            return appsOnSpace(currentSpaceID)
        }
        // Fallback when CGS can't tell us the current Space: on-screen apps as
        // active, Cmd+H apps as parked. (No ghost detection on this rare path.)
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = onScreenWindows()
        let pids = MRUOrder.ordered(DesktopAppList.appPIDs(from: raw, frontmostPID: frontmostPID),
                                    byRecency: AppActivationTracker.shared.recency)
        let active = pids.compactMap { activeApp(pid: $0) }
        return active + parkedHiddenApps()
    }

    /// Apps on `spaceID`: active apps first, parked apps appended.
    static func appsOnSpace(_ spaceID: CGSSpaceID) -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = allSpacesWindows()
        let allowed = WindowsOnSpace.windowIDs(on: spaceID)
        let visibleBounds = DisplayBounds.union()
        let orderedPIDs = MRUOrder.ordered(
            DesktopAppList.appPIDs(from: raw,
                                   frontmostPID: frontmostPID,
                                   allowedWindowIDs: allowed),
            byRecency: AppActivationTracker.shared.recency)
        // Authoritative real-window frames per candidate app (from AX). Used to
        // drop auxiliary layer-0 windows (browser find bars, bubbles) that pass
        // the size/Space filter but aren't real top-level windows — otherwise an
        // app whose only window on this Space is such a panel shows up with a
        // bogus preview and "selecting" it jumps to a real window on another
        // Space. Empty list for a PID => AX unavailable => not filtered.
        //
        // AX geometry (kAXPosition/kAXSize) is only reliable for windows on the
        // ACTIVE Space. For a non-current Space the values are stale/zeroed, so
        // real off-Space windows would fail the match and be incorrectly dropped.
        // Aux windows only appear on the active Space, so restricting the filter
        // to the current Space still fixes the Chrome find-bar problem.
        let isCurrentSpace = spaceID == CurrentSpace.id()
        let axFramesByPID: [pid_t: [CGRect]]? = isCurrentSpace
            ? Dictionary(uniqueKeysWithValues:
                orderedPIDs.map { ($0, MinimizedWindows.realWindowFrames(forPID: $0)) })
            : nil
        let realCounts = DesktopAppList.realWindowCounts(from: raw,
                                                         allowedWindowIDs: allowed,
                                                         visibleBounds: visibleBounds,
                                                         minSize: minWindowSize,
                                                         axFramesByPID: axFramesByPID)

        var active: [SwitcherApp] = []
        var parked: [SwitcherApp] = []
        for pid in orderedPIDs {
            // A Cmd+H'd app keeps its windows in the Space set (CGS still
            // reports them), so realCount can be > 0 even while hidden. Read
            // the real hidden state so such an app is parked, not active.
            let isHidden = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
            let realCount = realCounts[pid] ?? 0
            let minimizedCount = realCount > 0 ? 0 : MinimizedWindows.count(forPID: pid)
            let input = WindowClassifier.ClassifierInput(pid: pid,
                                                         realWindowCount: realCount,
                                                         minimizedWindowCount: minimizedCount,
                                                         isHidden: isHidden)
            switch WindowClassifier.classify(input) {
            case .active:
                if let app = activeApp(pid: pid) { active.append(app) }
            case .parked(let count):
                if let app = parkedApp(pid: pid, windowCount: count, isHidden: isHidden) {
                    parked.append(app)
                }
            }
        }

        // Cmd+H apps (sourced from NSWorkspace — their windows don't reliably
        // report a Space). De-dup against anything already added.
        let already = Set((active + parked).map(\.pid))
        let hidden = parkedHiddenApps().filter { !already.contains($0.pid) }

        return active + (parked + hidden).sorted { $0.name < $1.name }
    }

    // MARK: - App builders

    private static func activeApp(pid: pid_t) -> SwitcherApp? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else { return nil }
        return SwitcherApp(pid: pid, name: app.localizedName ?? "", icon: app.icon,
                           isHidden: app.isHidden, isParked: false, windowCount: 0)
    }

    private static func parkedApp(pid: pid_t, windowCount: Int, isHidden: Bool) -> SwitcherApp? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else { return nil }
        return SwitcherApp(pid: pid, name: app.localizedName ?? "", icon: app.icon,
                           isHidden: isHidden, isParked: true, windowCount: windowCount)
    }

    /// Cmd+H-hidden regular apps as parked apps, badge = their real-sized window
    /// count (PID-wide CGWindowList, since hidden windows don't report a Space).
    private static func parkedHiddenApps() -> [SwitcherApp] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter {
                $0.isHidden && $0.activationPolicy == .regular &&
                $0.processIdentifier > 0 && $0.processIdentifier != selfPID
            }
            .compactMap { app -> SwitcherApp? in
                let count = realSizedWindowCount(forPID: app.processIdentifier)
                return SwitcherApp(pid: app.processIdentifier, name: app.localizedName ?? "",
                                   icon: app.icon, isHidden: true, isParked: true, windowCount: count)
            }
    }

    /// Count of an app's layer-0 windows that meet the min-size bar, regardless
    /// of Space or on-screen state (used for the Cmd+H badge).
    private static func realSizedWindowCount(forPID pid: pid_t) -> Int {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        var count = 0
        for info in infoList {
            guard let p = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid_t(p) == pid else { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            guard layer == 0 else { continue }
            let frame: CGRect = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            if frame.width >= minWindowSize.width && frame.height >= minWindowSize.height { count += 1 }
        }
        return count
    }

    // MARK: - Window enumeration

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
            let frame: CGRect = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            let onScreen = frame == .zero ? true : frame.intersects(visibleBounds)
            let windowID: CGWindowID? = (info[kCGWindowNumber as String] as? NSNumber)
                .map { CGWindowID($0.uint32Value) }
            return RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen,
                                windowID: windowID, frame: frame)
        }
    }

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
            let frame: CGRect = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            let windowID: CGWindowID? = (info[kCGWindowNumber as String] as? NSNumber)
                .map { CGWindowID($0.uint32Value) }
            return RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: true,
                                windowID: windowID, frame: frame)
        }
    }
}
