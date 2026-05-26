import AppKit
import Combine

struct SwitcherApp: Identifiable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    var id: pid_t { pid }
}

final class SwitcherModel: ObservableObject {
    @Published var apps: [SwitcherApp]
    @Published var selectedIndex: Int

    init(apps: [SwitcherApp], selectedIndex: Int) {
        self.apps = apps
        self.selectedIndex = selectedIndex
    }
}
