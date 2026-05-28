import AppKit
import Combine
import CoreGraphics

struct SwitcherApp: Identifiable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    var id: pid_t { pid }
}

struct SwitcherWindow: Identifiable {
    let windowID: CGWindowID
    let title: String
    let info: WindowInfo
    let pid: pid_t
    var image: CGImage?
    var id: CGWindowID { windowID }
}

/// View model for one desktop chip in the Cmd+Tab overlay.
///
/// Two flags so the chip row can convey both "what the user is looking at"
/// (isPreviewed → solid fill) and "where macOS actually is right now"
/// (isReal → outlined border). They coincide on overlay open.
struct DesktopVM: Identifiable, Equatable {
    let id: CGSSpaceID            // also the Space ID
    let label: String             // e.g. "1  Work" or "3  Desktop 3"
    let displayUUID: String
    let isPreviewed: Bool
    let isReal: Bool
}

final class SwitcherModel: ObservableObject {
    @Published var apps: [SwitcherApp]
    @Published var selectedAppIndex: Int
    @Published var windows: [SwitcherWindow]
    @Published var selectedWindowIndex: Int   // -1 = app-level (no window selected)
    @Published var desktopName: String
    @Published var isRenaming: Bool
    @Published var desktops: [DesktopVM]
    @Published var previewedSpaceID: CGSSpaceID?
    @Published var realSpaceID: CGSSpaceID?

    init(apps: [SwitcherApp], selectedAppIndex: Int, desktops: [DesktopVM] = []) {
        self.apps = apps
        self.selectedAppIndex = selectedAppIndex
        self.windows = []
        self.selectedWindowIndex = -1
        self.desktopName = DesktopNameStore.defaultName
        self.isRenaming = false
        self.desktops = desktops
        self.previewedSpaceID = nil
        self.realSpaceID = nil
    }
}
