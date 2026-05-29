import AppKit
import ApplicationServices
import CoreGraphics

/// One minimized (Cmd+M) window of an app, resolved to a CGWindowID by
/// matching the AX window against the CGWindowList entry for the same PID.
struct MinimizedWindow: Equatable {
    let windowID: CGWindowID   // 0 if no CGWindowList match was found
    let title: String
    let frame: CGRect
    let appName: String
}

/// Accessibility-backed queries about an app's minimized windows. All calls
/// are synchronous and rely on the Accessibility grant the app already holds.
enum MinimizedWindows {
    /// Fast count of windows with kAXMinimized == true for `pid`.
    static func count(forPID pid: pid_t) -> Int {
        axWindows(forPID: pid).filter { isMinimized($0) }.count
    }

    /// Minimized windows of `pid`, each resolved (best-effort) to a CGWindowID
    /// via frame/title matching against CGWindowList.
    static func windows(forPID pid: pid_t) -> [MinimizedWindow] {
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
        let cgWindows = cgWindowList(forPID: pid)
        return axWindows(forPID: pid)
            .filter { isMinimized($0) }
            .map { axWin in
                let title = axTitle(axWin)
                let frame = axFrame(axWin)
                let windowID = matchWindowID(title: title, frame: frame, in: cgWindows)
                return MinimizedWindow(windowID: windowID ?? 0,
                                       title: title,
                                       frame: frame,
                                       appName: appName)
            }
    }

    /// Un-minimize the AX window matching `info` (kAXMinimized = false), then
    /// raise it and activate the app.
    static func restore(_ info: WindowInfo, pid: pid_t) {
        let candidates = axWindows(forPID: pid)
        // Prefer an exact title match, else nearest origin.
        let target = candidates.first(where: { axTitle($0) == info.title && !info.title.isEmpty })
            ?? candidates.min(by: {
                originDistance(axFrame($0), info.frame) < originDistance(axFrame($1), info.frame)
            })
        if let target {
            AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    // MARK: - AX plumbing

    private static func axWindows(forPID pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success,
              let number = value as? Bool else { return false }
        return number
    }

    private static func axTitle(_ window: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String else { return "" }
        return title
    }

    private static func axFrame(_ window: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
           let posValue, CFGetTypeID(posValue) == AXValueGetTypeID() {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
        }
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - CGWindowList match

    private struct CGWin { let id: CGWindowID; let title: String; let frame: CGRect }

    private static func cgWindowList(forPID pid: pid_t) -> [CGWin] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let p = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid_t(p) == pid,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
            let title = (info[kCGWindowName as String] as? String) ?? ""
            let frame: CGRect = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            return CGWin(id: CGWindowID(number), title: title, frame: frame)
        }
    }

    private static func matchWindowID(title: String, frame: CGRect, in cgWindows: [CGWin]) -> CGWindowID? {
        if let byFrame = cgWindows.first(where: { framesEqual($0.frame, frame) }) { return byFrame.id }
        if !title.isEmpty, let byTitle = cgWindows.first(where: { $0.title == title }) { return byTitle.id }
        return cgWindows.first?.id
    }

    private static func framesEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance && abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.size.width - b.size.width) <= tolerance && abs(a.size.height - b.size.height) <= tolerance
    }

    private static func originDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.origin.x - b.origin.x, dy = a.origin.y - b.origin.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
