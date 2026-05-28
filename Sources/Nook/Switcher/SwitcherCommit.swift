import Foundation

/// Resolves what the Cmd+Tab switcher should do when the user releases Cmd
/// (committing the current selection).
///
/// - When the user navigated desktops during the session (`didNavigateDesktop`
///   is true), the model's selected app/window references the pre-navigation
///   desktop and is therefore stale; commit becomes a `.noop` and the
///   controller just closes the overlay.
/// - Otherwise, if a window has been picked (selectedWindowIndex >= 0) it
///   becomes `.window`, else `.app`.
enum SwitcherCommit {
    enum Intent: Equatable {
        case app
        case window(Int)
        case noop
    }

    static func resolve(selectedWindowIndex: Int,
                        windowCount: Int,
                        didNavigateDesktop: Bool = false) -> Intent {
        if didNavigateDesktop { return .noop }
        if selectedWindowIndex >= 0 && selectedWindowIndex < windowCount {
            return .window(selectedWindowIndex)
        }
        return .app
    }
}
