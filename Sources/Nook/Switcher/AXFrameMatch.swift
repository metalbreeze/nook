import CoreGraphics

/// Tells a genuine top-level window from an auxiliary one.
///
/// Browsers (Chrome especially) put find bars, permission bubbles, and other
/// transient panels on window layer 0 — the same layer as real browser
/// windows — and these can pass a plain size/Space filter. They are, however,
/// absent from the app's Accessibility window list (`kAXWindowsAttribute`),
/// which is the authoritative set of windows macOS's own Cmd+Tab and window
/// menu operate on. We therefore keep a CoreGraphics / ScreenCaptureKit window
/// only if its frame matches one of the app's AX window frames.
///
/// Matching is by frame within a small tolerance because AX exposes no
/// CGWindowID; this is the same cross-API frame match `WindowActivator` already
/// relies on to raise the correct window.
enum AXFrameMatch {
    static func matches(_ frame: CGRect, anyOf axFrames: [CGRect], tolerance: CGFloat = 2) -> Bool {
        axFrames.contains { framesEqual($0, frame, tolerance: tolerance) }
    }

    static func framesEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
        abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.size.width - b.size.width) <= tolerance &&
        abs(a.size.height - b.size.height) <= tolerance
    }
}
