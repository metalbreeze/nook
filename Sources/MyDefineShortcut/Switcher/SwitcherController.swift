import AppKit
import SwiftUI

@MainActor
final class SwitcherController {
    private var window: OverlayWindow?
    private var model: SwitcherModel?

    /// Opens the switcher with the current-desktop apps, current app highlighted.
    func open() {
        let apps = DesktopAppEnumerator.currentDesktopApps()
        guard !apps.isEmpty else { return }
        let model = SwitcherModel(apps: apps, selectedAppIndex: 0)
        self.model = model
        showWindow(model: model)
    }

    func advance() {
        guard let model, !model.apps.isEmpty else { return }
        model.selectedAppIndex = SwitcherIndex.advance(model.selectedAppIndex, count: model.apps.count)
    }

    func reverse() {
        guard let model, !model.apps.isEmpty else { return }
        model.selectedAppIndex = SwitcherIndex.reverse(model.selectedAppIndex, count: model.apps.count)
    }

    /// Releasing Cmd: switch to the highlighted app and close.
    func commit() {
        guard let model, model.apps.indices.contains(model.selectedAppIndex) else {
            close()
            return
        }
        let pid = model.apps[model.selectedAppIndex].pid
        close()
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Esc: close without switching (focus never left the original app).
    func cancel() {
        close()
    }

    private func showWindow(model: SwitcherModel) {
        guard let screen = NSScreen.main else { return }
        let win = OverlayWindow(contentRect: screen.frame,
                                styleMask: [.borderless],
                                backing: .buffered,
                                defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.ignoresMouseEvents = true

        let hosting = NSHostingView(rootView: SwitcherView(model: model))
        hosting.frame = screen.frame
        hosting.autoresizingMask = [.width, .height]
        win.contentView = hosting
        win.setFrame(screen.frame, display: true)
        win.orderFrontRegardless() // show on top WITHOUT activating our app / stealing focus
        window = win
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        model = nil
    }
}
