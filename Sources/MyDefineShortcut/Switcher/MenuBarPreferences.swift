import Foundation

/// Persists whether the menu-bar icon shows the current desktop's name.
/// Defaults to true when unset.
struct MenuBarPreferences {
    private let defaults: UserDefaults
    private let key = "showDesktopNameInMenuBar"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showDesktopName: Bool {
        get { defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key) }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}
