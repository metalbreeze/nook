import CoreGraphics

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(
    _ cid: CGSConnectionID,
    _ displayUUID: CFString,
    _ spaceID: CGSSpaceID
)

/// Reads the current (active) Space ID via the private CGS/SkyLight API.
/// Returns nil if the call yields 0 (defensive). Private/unsupported.
enum CurrentSpace {
    static func id() -> CGSSpaceID? {
        let space = CGSGetActiveSpace(CGSMainConnectionID())
        return space == 0 ? nil : space
    }
}
