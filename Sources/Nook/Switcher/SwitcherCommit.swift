enum SwitcherCommit: Equatable {
    case app
    case window(Int)

    /// Resolves what releasing Cmd should do: raise the selected window if one is
    /// selected and in range, otherwise activate the app.
    static func resolve(selectedWindowIndex: Int, windowCount: Int) -> SwitcherCommit {
        if selectedWindowIndex >= 0 && selectedWindowIndex < windowCount {
            return .window(selectedWindowIndex)
        }
        return .app
    }
}
