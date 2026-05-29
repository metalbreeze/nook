import AppKit
import ApplicationServices

/// Returns the CGWindowID of an AX window element. This private SPI is present
/// on all macOS versions Nook targets and is the only reliable way to identify
/// an AX window when its kAXPosition/kAXSize is stale (e.g. off-Space windows).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowActivator {
    static func activate(_ target: WindowInfo, pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            // Prefer CGWindowID match — reliable even for windows on non-active
            // Spaces whose AX frame (kAXPosition/kAXSize) is stale or zero.
            let byID: AXUIElement? = target.windowID != kCGNullWindowID
                ? axWindows.first { axWin in
                    var wid: CGWindowID = 0
                    return _AXUIElementGetWindow(axWin, &wid) == .success && wid == target.windowID
                }
                : nil
            if let axWin = byID {
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            } else {
                // Fallback: frame/title matching for callers that have no window
                // ID, or on rare systems where _AXUIElementGetWindow is absent.
                let candidates = axWindows.enumerated().map { idx, win in
                    AXWindowCandidate(index: idx, title: axTitle(win), frame: axFrame(win))
                }
                if let matchIndex = WindowMatcher.bestMatch(for: target, among: candidates),
                   matchIndex < axWindows.count {
                    AXUIElementPerformAction(axWindows[matchIndex], kAXRaiseAction as CFString)
                } else {
                    Log.activate.error("no AX window matched target id=\(target.windowID, privacy: .public)")
                }
            }
        } else {
            Log.activate.error("AX kAXWindowsAttribute unavailable for pid=\(pid, privacy: .public)")
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
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
}
