import AppKit
import Combine
import CoreGraphics

struct SwitcherApp: Identifiable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    let isHidden: Bool          // Cmd+H — still needed for unhide-on-click
    var isParked: Bool = false  // small dimmed icon + badge + Tab-skip
    var windowCount: Int = 0    // badge value (parked only)
    var id: pid_t { pid }
}

struct SwitcherWindow: Identifiable {
    let windowID: CGWindowID
    let title: String
    let info: WindowInfo
    let pid: pid_t
    var image: CGImage?
    var isMinimized: Bool = false   // smaller + gray + un-minimize on select
    var id: CGWindowID { windowID }
}

/// View model for one desktop chip in the Cmd+Tab overlay.
///
/// Two flags so the chip row can convey both "where macOS actually is right
/// now" (isReal → solid fill) and "what the user is peeking at" (isPreviewed
/// → outlined border) at once. They coincide on overlay open.
struct DesktopVM: Identifiable, Equatable {
    let id: CGSSpaceID                  // also the Space ID
    let index: Int                      // 1-based chip position
    let name: String                    // current display name (stored or default)
    let displayUUID: String
    let isPreviewed: Bool
    let isReal: Bool

    var label: String { DesktopLabel.label(index: index, storedName: name) }
}

final class SwitcherModel: ObservableObject {
    @Published var apps: [SwitcherApp]
    @Published var selectedAppIndex: Int
    @Published var windows: [SwitcherWindow]
    @Published var selectedWindowIndex: Int   // -1 = app-level (no window selected)
    @Published var desktopName: String
    @Published var isRenaming: Bool
    @Published var renamingDesktopID: CGSSpaceID?
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
        self.renamingDesktopID = nil
        self.desktops = desktops
        self.previewedSpaceID = nil
        self.realSpaceID = nil
    }
}
