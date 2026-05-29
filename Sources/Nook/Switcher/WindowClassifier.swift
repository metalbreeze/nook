import Foundation

/// Pure decision: is an app "active" (Tab-navigable, normal icon) or "parked"
/// (Cmd+H-hidden or window-less; small dimmed icon with a count badge)?
enum WindowClassifier {
    struct ClassifierInput: Equatable {
        let pid: pid_t
        let realWindowCount: Int       // windows passing the real-window bar
        let minimizedWindowCount: Int  // from AX kAXMinimized
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
        if input.realWindowCount > 0 || input.minimizedWindowCount > 0 {
            return .active
        }
        return .parked(windowCount: 0)
    }
}
