import CoreGraphics

struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let title: String
    let frame: CGRect
    let appName: String
}

struct RawWindow: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let layer: Int
    let isOnScreen: Bool
    let title: String
    let appName: String
    let frame: CGRect
}
