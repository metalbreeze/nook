import Foundation

/// Pure decision: is an app "active" (Tab-navigable, normal icon) or "parked"
/// (Cmd+H-hidden or window-less; small dimmed icon with a count badge)?
enum WindowClassifier {
    struct ClassifierInput: Equatable {
        let pid: pid_t
        let realWindowCount: Int       // real, ON-SCREEN windows on this desktop
        let minimizedWindowCount: Int  // minimized / off-screen / hidden windows
        let isHidden: Bool             // Cmd+H (NSRunningApplication.isHidden)
    }

    enum AppClass: Equatable {
        case active
        case parked(windowCount: Int)
    }

    static func classify(_ input: ClassifierInput) -> AppClass {
        if input.isHidden {
            return .parked(windowCount: input.realWindowCount)
        }
        // Active only with a real, on-screen window. An app whose windows on this
        // desktop are all minimized / hidden is parked at the end, badged with
        // how many it has stashed.
        if input.realWindowCount > 0 {
            return .active
        }
        if input.minimizedWindowCount > 0 {
            return .parked(windowCount: input.minimizedWindowCount)
        }
        return .parked(windowCount: 0)
    }
}
