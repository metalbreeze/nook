import AppKit

/// Tracks app activation order (most-recently-used first) by observing
/// NSWorkspace activation notifications, so the switcher can order apps like the
/// native Cmd+Tab. Excludes Nook itself.
final class AppActivationTracker {
    static let shared = AppActivationTracker()

    /// Most-recently-activated PIDs, most recent first.
    private(set) var recency: [pid_t] = []
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    private init() {}

    func start() {
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           front != selfPID {
            recency = [front]
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
    }

    @objc private func didActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        recordActivation(app.processIdentifier)
    }

    /// Move `pid` to the front of the recency list. Called both from the
    /// NSWorkspace notification (native switches) and explicitly when Nook
    /// activates an app/window — Nook focuses via SkyLight, which does not
    /// reliably post the activation notification, so without this the MRU order
    /// wouldn't update for Nook-initiated switches.
    func recordActivation(_ pid: pid_t) {
        guard pid != selfPID, pid > 0 else { return }   // don't let Nook pollute the order
        recency.removeAll { $0 == pid }
        recency.insert(pid, at: 0)
    }
}
