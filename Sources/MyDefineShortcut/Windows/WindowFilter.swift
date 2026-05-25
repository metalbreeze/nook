import CoreGraphics

enum WindowFilter {
    static func visibleWindows(from windows: [RawWindow],
                               frontmostPID: pid_t,
                               minSize: CGSize = CGSize(width: 80, height: 80)) -> [WindowInfo] {
        windows
            .filter { $0.ownerPID == frontmostPID }
            .filter { $0.layer == 0 }
            .filter { $0.isOnScreen }
            .filter { $0.frame.width >= minSize.width && $0.frame.height >= minSize.height }
            .map { WindowInfo(windowID: $0.windowID, title: $0.title, frame: $0.frame, appName: $0.appName) }
    }
}
