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

final class SwitcherModel: ObservableObject {
    @Published var apps: [SwitcherApp]
    @Published var selectedAppIndex: Int
    @Published var windows: [SwitcherWindow]
    @Published var selectedWindowIndex: Int   // -1 = app-level (no window selected)
    @Published var desktopName: String
    @Published var isRenaming: Bool

    init(apps: [SwitcherApp], selectedAppIndex: Int) {
        self.apps = apps
        self.selectedAppIndex = selectedAppIndex
        self.windows = []
        self.selectedWindowIndex = -1
        self.desktopName = DesktopNameStore.defaultName
        self.isRenaming = false
    }
}
