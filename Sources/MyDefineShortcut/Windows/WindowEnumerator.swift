import ScreenCaptureKit

enum WindowEnumerator {
    /// Fetches the focused app's visible windows on the current desktop, as SCWindow objects.
    /// Filtering is delegated to the tested WindowFilter via a windowID allow-set.
    static func filteredSCWindows(forPID pid: pid_t) async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let raw = content.windows.map { rawWindow(from: $0) }
        let allowedIDs = Set(WindowFilter.visibleWindows(from: raw, frontmostPID: pid).map(\.windowID))
        return content.windows.filter { allowedIDs.contains($0.windowID) }
    }

    static func info(from window: SCWindow) -> WindowInfo {
        WindowInfo(windowID: window.windowID,
                   title: window.title ?? "",
                   frame: window.frame,
                   appName: window.owningApplication?.applicationName ?? "")
    }

    private static func rawWindow(from window: SCWindow) -> RawWindow {
        RawWindow(windowID: window.windowID,
                  ownerPID: pid_t(window.owningApplication?.processID ?? 0),
                  layer: window.windowLayer,
                  isOnScreen: window.isOnScreen,
                  title: window.title ?? "",
                  appName: window.owningApplication?.applicationName ?? "",
                  frame: window.frame)
    }
}
