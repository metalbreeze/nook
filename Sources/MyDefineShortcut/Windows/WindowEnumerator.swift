import ScreenCaptureKit
import CoreGraphics

enum WindowEnumerator {
    /// Fetches the focused app's visible windows on the current desktop, as SCWindow objects.
    /// Filtering is delegated to the tested WindowFilter via a windowID allow-set.
    static func filteredSCWindows(forPID pid: pid_t) async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let currentSpaceIDs = currentSpaceWindowIDs()
        let raw = content.windows.map { rawWindow(from: $0, currentSpaceIDs: currentSpaceIDs) }
        let allowedIDs = Set(WindowFilter.visibleWindows(from: raw, frontmostPID: pid).map(\.windowID))
        return content.windows.filter { allowedIDs.contains($0.windowID) }
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
