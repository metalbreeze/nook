import CoreGraphics
import Foundation

/// Window IDs currently belonging to a given Space, including off-screen ones
/// (i.e. windows on other desktops). Uses the private CGSCopySpacesForWindows
/// API to ask, per window, "which Spaces is this on?", then keeps the windows
/// whose Space set contains the target.
///
/// Returns an empty set if CGS returns garbage. Best-effort, unsupported.
enum WindowsOnSpace {
    /// Mask passed to CGSCopySpacesForWindows. 0x7 includes user, fullscreen,
    /// and system Spaces — the union "all Spaces" used by Yabai and friends.
    private static let allSpacesMask: UInt64 = 0x7

    static func windowIDs(on spaceID: CGSSpaceID) -> Set<CGWindowID> {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }
        let connection = CGSMainConnectionID()
        var result: Set<CGWindowID> = []
        for info in infoList {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            let windowID = CGWindowID(number)
            let cfIDs = [NSNumber(value: windowID)] as CFArray
            let spaces = CGSCopySpacesForWindows(connection, allSpacesMask, cfIDs) as NSArray
            for case let n as NSNumber in spaces where n.uint64Value == spaceID {
                result.insert(windowID)
                break
            }
        }
        return result
    }
}
