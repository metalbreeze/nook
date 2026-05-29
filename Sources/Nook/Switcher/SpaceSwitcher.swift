import CoreGraphics

/// One-shot helper that asks WindowServer to make `spaceID` the active Space
/// on the display identified by `displayUUID`. Uses the same private CGS /
/// SkyLight surface as `CurrentSpace` — unsupported by Apple but stable
/// across macOS releases for many years. No-ops if the target is already
/// the active Space.
enum SpaceSwitcher {
    static func switchTo(spaceID: CGSSpaceID, displayUUID: String) {
        guard spaceID != CurrentSpace.id() else { return }
        CGSManagedDisplaySetCurrentSpace(
            CGSMainConnectionID(),
            displayUUID as CFString,
            spaceID
        )
    }
}
