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
        Log.activate.notice("activate request pid=\(pid, privacy: .public) targetID=\(target.windowID, privacy: .public) targetFrame=\(target.frame.logDesc, privacy: .public) title=\(target.title, privacy: .public)")
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            Log.activate.notice("AX windows for pid=\(pid, privacy: .public): count=\(axWindows.count, privacy: .public)")
            for (i, axWin) in axWindows.enumerated() {
                var wid: CGWindowID = 0
                let err = _AXUIElementGetWindow(axWin, &wid)
                Log.activate.notice("  ax[\(i, privacy: .public)] getWindowErr=\(err.rawValue, privacy: .public) id=\(wid, privacy: .public) frame=\(axFrame(axWin).logDesc, privacy: .public) title=\(axTitle(axWin), privacy: .public)")
            }
            // Prefer CGWindowID match — reliable even for windows on non-active
            // Spaces whose AX frame (kAXPosition/kAXSize) is stale or zero.
            let byID: AXUIElement? = target.windowID != kCGNullWindowID
                ? axWindows.first { axWin in
                    var wid: CGWindowID = 0
                    return _AXUIElementGetWindow(axWin, &wid) == .success && wid == target.windowID
                }
                : nil
            if let axWin = byID {
                Log.activate.notice("matched by CGWindowID -> raising id=\(target.windowID, privacy: .public)")
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            } else {
                // Fallback: frame/title matching for callers that have no window
                // ID, or on rare systems where _AXUIElementGetWindow is absent.
                let candidates = axWindows.enumerated().map { idx, win in
                    AXWindowCandidate(index: idx, title: axTitle(win), frame: axFrame(win))
                }
                if let matchIndex = WindowMatcher.bestMatch(for: target, among: candidates),
                   matchIndex < axWindows.count {
                    Log.activate.notice("no ID match; FALLBACK frame/title -> ax index \(matchIndex, privacy: .public)")
                    AXUIElementPerformAction(axWindows[matchIndex], kAXRaiseAction as CFString)
                } else {
                    Log.activate.error("no AX window matched target id=\(target.windowID, privacy: .public)")
                }
            }
        } else {
            Log.activate.error("AX kAXWindowsAttribute unavailable for pid=\(pid, privacy: .public)")
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
        Log.activate.notice("called NSRunningApplication.activate() pid=\(pid, privacy: .public)")
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
