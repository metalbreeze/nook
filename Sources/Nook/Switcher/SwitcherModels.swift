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
struct DesktopVM: Identifiable, Equatable {
    let id: CGSSpaceID            // also the Space ID
    let label: String             // e.g. "1  Work" or "3  Desktop 3"
    let displayUUID: String
    let isCurrent: Bool
}

final class SwitcherModel: ObservableObject {
    @Published var apps: [SwitcherApp]
    @Published var selectedAppIndex: Int
    @Published var windows: [SwitcherWindow]
    @Published var selectedWindowIndex: Int   // -1 = app-level (no window selected)
    @Published var desktopName: String
    @Published var isRenaming: Bool
    @Published var desktops: [DesktopVM]

    init(apps: [SwitcherApp], selectedAppIndex: Int, desktops: [DesktopVM] = []) {
        self.apps = apps
        self.selectedAppIndex = selectedAppIndex
        self.windows = []
        self.selectedWindowIndex = -1
        self.desktopName = DesktopNameStore.defaultName
        self.isRenaming = false
        self.desktops = desktops
    }
}
