import ScreenCaptureKit
import CoreGraphics

enum WindowEnumerator {
    /// Fetches the focused app's visible windows on the current desktop, as SCWindow objects.
    /// Filtering is delegated to the tested WindowFilter via a windowID allow-set.
    static func filteredSCWindows(forPID pid: pid_t) async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let currentSpaceIDs = currentSpaceWindowIDs()
        let visibleBounds = DisplayBounds.union()
        let raw = content.windows.map { rawWindow(from: $0, currentSpaceIDs: currentSpaceIDs) }
        let allowedIDs = Set(WindowFilter.visibleWindows(from: raw, frontmostPID: pid, visibleBounds: visibleBounds).map(\.windowID))
        return keepingAXRealWindows(content.windows, pid: pid, allowedIDs: allowedIDs)
    }

    /// Same as `filteredSCWindows(forPID:)` but the on-Space filter is the
    /// explicit `spaceID` rather than the active Space. Used by the preview
    /// path in the Cmd+Tab switcher.
    static func filteredSCWindows(forPID pid: pid_t,
                                  onSpace spaceID: CGSSpaceID) async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let allowed = WindowsOnSpace.windowIDs(on: spaceID)
        let visibleBounds = DisplayBounds.union()
        let raw = content.windows.map { rawWindow(from: $0, onSpaceIDs: allowed) }
        let allowedIDs = Set(WindowFilter.visibleWindows(from: raw,
                                                          frontmostPID: pid,
                                                          visibleBounds: visibleBounds).map(\.windowID))
        // AX geometry is only reliable for the active Space — skip the filter
        // for non-current Spaces so real off-Space windows are not dropped.
        return keepingAXRealWindows(content.windows, pid: pid, allowedIDs: allowedIDs,
                                    applyAXFilter: spaceID == CurrentSpace.id())
    }

    /// Keeps only the windows whose ID is allowed AND (when AX is available AND
    /// `applyAXFilter` is true) whose frame matches one of the app's real AX
    /// window frames. This drops auxiliary layer-0 windows (browser find bars,
    /// bubbles) that survive the size/Space filter but are not real top-level
    /// windows. If AX yields no frames for the PID, the AX check is skipped
    /// (allow-set only). Pass `applyAXFilter: false` for non-current Spaces
    /// because kAXPosition/kAXSize is unreliable for off-Space windows.
    private static func keepingAXRealWindows(_ windows: [SCWindow],
                                             pid: pid_t,
                                             allowedIDs: Set<CGWindowID>,
                                             applyAXFilter: Bool = true) -> [SCWindow] {
        guard applyAXFilter else {
            return windows.filter { allowedIDs.contains($0.windowID) }
        }
        let axFrames = MinimizedWindows.realWindowFrames(forPID: pid)
        return windows.filter { window in
            guard allowedIDs.contains(window.windowID) else { return false }
            return axFrames.isEmpty || AXFrameMatch.matches(window.frame, anyOf: axFrames)
        }
    }

    private static func rawWindow(from window: SCWindow, onSpaceIDs: Set<CGWindowID>) -> RawWindow {
        RawWindow(windowID: window.windowID,
                  ownerPID: pid_t(window.owningApplication?.processID ?? 0),
                  layer: window.windowLayer,
                  isOnScreen: onSpaceIDs.contains(window.windowID),
                  title: window.title ?? "",
                  appName: window.owningApplication?.applicationName ?? "",
                  frame: window.frame)
    }

    static func info(from window: SCWindow) -> WindowInfo {
        WindowInfo(windowID: window.windowID,
                   title: window.title ?? "",
                   frame: window.frame,
                   appName: window.owningApplication?.applicationName ?? "")
    }

    /// Window IDs that are on the CURRENT Space (active desktop).
    ///
    /// We use CGWindowList's `.optionOnScreenOnly` rather than `SCWindow.isOnScreen`
    /// because CGWindowList authoritatively returns only windows on the *active* Space —
    /// windows on other desktops are excluded. `SCWindow.isOnScreen` does NOT reliably
    /// exclude other-Space windows, which caused the overlay to show windows from other
    /// desktops. Reading only the window number requires no Screen Recording permission.
    private static func currentSpaceWindowIDs() -> Set<CGWindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids = Set<CGWindowID>()
        for info in infoList {
            if let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value {
                ids.insert(number)
            }
        }
        return ids
    }

    private static func rawWindow(from window: SCWindow, currentSpaceIDs: Set<CGWindowID>) -> RawWindow {
        RawWindow(windowID: window.windowID,
                  ownerPID: pid_t(window.owningApplication?.processID ?? 0),
                  layer: window.windowLayer,
                  isOnScreen: currentSpaceIDs.contains(window.windowID),
                  title: window.title ?? "",
                  appName: window.owningApplication?.applicationName ?? "",
                  frame: window.frame)
    }
}
