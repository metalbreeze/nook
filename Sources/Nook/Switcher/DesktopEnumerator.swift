import AppKit
import CoreGraphics

/// One row in the Cmd+Tab desktop chip strip.
struct DesktopEntry: Equatable {
    let spaceID: CGSSpaceID
    let displayUUID: String
    /// 1-based position within the screen's user-space desktops (contiguous,
    /// fullscreen-app Spaces are skipped in numbering).
    let indexInDisplay: Int
}

/// Reads the active per-display Space layout via the private
/// CGSCopyManagedDisplaySpaces API and returns the user-space desktops on
/// the given screen in Mission Control order.
enum DesktopEnumerator {
    static func desktopsForCurrentScreen(_ screen: NSScreen) -> [DesktopEntry] {
        guard let uuidString = displayUUIDString(for: screen) else { return [] }
        let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as NSArray
        for case let displayDict as [String: Any] in raw {
            let displayID =
                displayDict["Display Identifier"] as? String
                ?? displayDict["DisplayIdentifier"] as? String
            guard displayID == uuidString else { continue }
            guard let spaces = displayDict["Spaces"] as? [[String: Any]] else { return [] }
            var result: [DesktopEntry] = []
            var index = 1
            for space in spaces {
                let type = (space["type"] as? NSNumber)?.intValue ?? -1
                guard type == 0 else { continue } // 0 = user desktop
                guard let sid = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
                else { continue }
                result.append(DesktopEntry(spaceID: sid,
                                           displayUUID: uuidString,
                                           indexInDisplay: index))
                index += 1
            }
            return result
        }
        return []
    }

    private static func displayUUIDString(for screen: NSScreen) -> String? {
        guard let number =
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuidRef) as String
    }
}
