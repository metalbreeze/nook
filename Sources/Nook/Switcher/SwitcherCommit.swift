import Foundation

/// Resolves what the Cmd+Tab switcher should do on commit (Cmd release).
///
/// Order of precedence:
///   1. A valid `selectedWindowIndex` always wins → `.window(i)`.
///   2. If `previewedSpaceID != realSpaceID` (and we have a `displayUUID`),
///      the user committed via desktop preview → `.switchSpace`.
///   3. Otherwise → `.app` (activate the selected app on the real desktop).
enum SwitcherCommit {
    enum Intent: Equatable {
        case app
        case window(Int)
        case switchSpace(CGSSpaceID, displayUUID: String)
    }

    static func resolve(selectedWindowIndex: Int,
                        windowCount: Int,
                        previewedSpaceID: CGSSpaceID?,
                        realSpaceID: CGSSpaceID?,
                        previewedDisplayUUID: String?) -> Intent {
        if selectedWindowIndex >= 0 && selectedWindowIndex < windowCount {
            return .window(selectedWindowIndex)
        }
        if let preview = previewedSpaceID,
           let real = realSpaceID,
           let uuid = previewedDisplayUUID,
           preview != real {
            return .switchSpace(preview, displayUUID: uuid)
        }
        return .app
    }
}
