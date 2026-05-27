import CoreGraphics

enum WindowFilter {
    /// `visibleBounds` is the union of the active displays' bounds (in global
    /// display coordinates). Windows whose frame doesn't intersect it are excluded —
    /// this drops windows that have slid off-screen mid Space-switch animation, which
    /// otherwise leak in (still flagged on-screen) right after switching desktops.
    static func visibleWindows(from windows: [RawWindow],
                               frontmostPID: pid_t,
                               visibleBounds: CGRect = .infinite,
                               minSize: CGSize = CGSize(width: 80, height: 80)) -> [WindowInfo] {
        windows
            .filter { $0.ownerPID == frontmostPID }
            .filter { $0.layer == 0 }
            .filter { $0.isOnScreen }
            .filter { $0.frame.width >= minSize.width && $0.frame.height >= minSize.height }
            .filter { $0.frame.intersects(visibleBounds) }
            .map { WindowInfo(windowID: $0.windowID, title: $0.title, frame: $0.frame, appName: $0.appName) }
    }
}
