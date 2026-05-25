import CoreGraphics

struct WindowThumbnail: Identifiable {
    let id: CGWindowID
    let image: CGImage?
    let title: String
    let info: WindowInfo
    let pid: pid_t
}
