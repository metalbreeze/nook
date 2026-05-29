import Foundation

/// Pure formatter for the desktop chip label shown in the Cmd+Tab overlay.
///
/// `index` is the 1-based position in the current screen's user-space
/// desktop list (fullscreen-app Spaces are skipped in numbering).
/// `storedName` is the user-given name from `DesktopNameStore.storedName`
/// (nil when the desktop has never been named).
enum DesktopLabel {
    static func label(index: Int, storedName: String?) -> String {
        let name = storedName ?? "Desktop \(index)"
        return "\(index)  \(name)"
    }
}
