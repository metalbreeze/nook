import AppKit
import SwiftUI

@MainActor
final class SwitcherController {
    private var window: OverlayWindow?
    private var model: SwitcherModel?
    private var generation = 0

    func open() {
        let apps = DesktopAppEnumerator.currentDesktopApps()
        guard !apps.isEmpty else { return }
        let model = SwitcherModel(apps: apps, selectedAppIndex: 0)
        self.model = model
        showWindow(model: model)
        loadWindows(forAppIndex: 0)
    }

    func advance() {
        guard let model, !model.apps.isEmpty else { return }
        model.selectedAppIndex = SwitcherIndex.advance(model.selectedAppIndex, count: model.apps.count)
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: model.selectedAppIndex)
    }

    func reverse() {
        guard let model, !model.apps.isEmpty else { return }
        model.selectedAppIndex = SwitcherIndex.reverse(model.selectedAppIndex, count: model.apps.count)
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: model.selectedAppIndex)
    }

    func windowLeft() {
        guard let model, !model.windows.isEmpty else { return }
        model.selectedWindowIndex = model.selectedWindowIndex < 0
            ? 0
            : SwitcherIndex.reverse(model.selectedWindowIndex, count: model.windows.count)
    }

    func windowRight() {
        guard let model, !model.windows.isEmpty else { return }
        model.selectedWindowIndex = model.selectedWindowIndex < 0
            ? 0
            : SwitcherIndex.advance(model.selectedWindowIndex, count: model.windows.count)
    }

    func hoverWindow(_ index: Int) {
        guard let model, model.windows.indices.contains(index) else { return }
        model.selectedWindowIndex = index
    }

    func clickWindow(_ index: Int) {
        guard let model, model.windows.indices.contains(index) else { return }
        let window = model.windows[index]
        close()
        WindowActivator.activate(window.info, pid: window.pid)
    }

    func commit() {
        guard let model else { close(); return }
        let intent = SwitcherCommit.resolve(selectedWindowIndex: model.selectedWindowIndex,
                                            windowCount: model.windows.count)
        switch intent {
        case .window(let index):
            let window = model.windows[index]
            close()
            WindowActivator.activate(window.info, pid: window.pid)
        case .app:
            guard model.apps.indices.contains(model.selectedAppIndex) else { close(); return }
            let pid = model.apps[model.selectedAppIndex].pid
            close()
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    func cancel() {
        close()
    }

    /// Loads the highlighted app's current-desktop windows, then captures thumbnails
    /// asynchronously. A generation token discards stale results when the user Tabs fast.
    private func loadWindows(forAppIndex appIndex: Int) {
        guard let model, model.apps.indices.contains(appIndex) else { return }
        generation += 1
        let token = generation
        let pid = model.apps[appIndex].pid
        model.windows = []
        Task { [weak self] in
            let scWindows = (try? await WindowEnumerator.filteredSCWindows(forPID: pid)) ?? []
            guard let self, self.generation == token, let model = self.model else { return }
            var built: [SwitcherWindow] = scWindows.map { scWindow in
                let info = WindowEnumerator.info(from: scWindow)
                return SwitcherWindow(windowID: scWindow.windowID, title: info.title,
                                      info: info, pid: pid, image: nil)
            }
            model.windows = built
            for (index, scWindow) in scWindows.enumerated() {
                let image = try? await ThumbnailCapturer.capture(scWindow)
                guard self.generation == token, let model = self.model,
                      built.indices.contains(index) else { return }
                built[index].image = image
                model.windows = built
            }
        }
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
        generation += 1
    }
}
