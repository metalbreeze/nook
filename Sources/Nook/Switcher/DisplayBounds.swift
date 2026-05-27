import CoreGraphics

/// Union of all active displays' bounds, in the global display coordinate space
/// (top-left origin) — the same space CGWindow/SCWindow frames use, so no Y-flip is
/// needed. Used to exclude windows that have slid off-screen during a Space-switch
/// animation (their frames are momentarily outside any display).
enum DisplayBounds {
    static func union() -> CGRect {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return .infinite }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return .infinite }
        var union = CGRect.null
        for display in displays {
            union = union.union(CGDisplayBounds(display))
        }
        return union.isNull ? .infinite : union
    }
}
