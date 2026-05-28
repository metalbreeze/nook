import AppKit
import SwiftUI

@MainActor
final class SwitcherController {
    private var window: OverlayWindow?
    private var model: SwitcherModel?
    private var generation = 0
    private let nameStore = DesktopNameStore()
    private var spaceID: CGSSpaceID?
    var onDesktopRenamed: (() -> Void)?

    func open() {
        let apps = DesktopAppEnumerator.currentDesktopApps()
        guard !apps.isEmpty else { return }
        let currentSpaceID = CurrentSpace.id()
        spaceID = currentSpaceID
        let screen = NSScreen.main ?? NSScreen.screens.first
        let entries = screen.map { DesktopEnumerator.desktopsForCurrentScreen($0) } ?? []
        let desktopVMs: [DesktopVM] = entries.map { entry in
            let isCurrent = entry.spaceID == currentSpaceID
            let storedName = nameStore.storedName(for: entry.spaceID)
            return DesktopVM(
                id: entry.spaceID,
                index: entry.indexInDisplay,
                name: storedName ?? "Desktop \(entry.indexInDisplay)",
                displayUUID: entry.displayUUID,
                isPreviewed: isCurrent,
                isReal: isCurrent
            )
        }
        let model = SwitcherModel(apps: apps,
                                  selectedAppIndex: 0,
                                  desktops: desktopVMs)
        model.previewedSpaceID = currentSpaceID
        model.realSpaceID = currentSpaceID
        if let currentSpaceID {
            model.desktopName = nameStore.name(for: currentSpaceID)
            loadWindows(forAppIndex: 0, onSpace: currentSpaceID)
        }
        self.model = model
        showWindow(model: model)
    }

    func advance() {
        guard let model, !model.isRenaming, !model.apps.isEmpty,
              let spaceID = model.previewedSpaceID else { return }
        model.selectedAppIndex = SwitcherIndex.advance(model.selectedAppIndex, count: model.apps.count)
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: model.selectedAppIndex, onSpace: spaceID)
    }

    func reverse() {
        guard let model, !model.isRenaming, !model.apps.isEmpty,
              let spaceID = model.previewedSpaceID else { return }
        model.selectedAppIndex = SwitcherIndex.reverse(model.selectedAppIndex, count: model.apps.count)
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: model.selectedAppIndex, onSpace: spaceID)
    }

    func windowLeft() {
        guard let model, !model.isRenaming, !model.windows.isEmpty else { return }
        model.selectedWindowIndex = model.selectedWindowIndex < 0
            ? 0
            : SwitcherIndex.reverse(model.selectedWindowIndex, count: model.windows.count)
    }

    func windowRight() {
        guard let model, !model.isRenaming, !model.windows.isEmpty else { return }
        model.selectedWindowIndex = model.selectedWindowIndex < 0
            ? 0
            : SwitcherIndex.advance(model.selectedWindowIndex, count: model.windows.count)
    }

    func hoverWindow(_ index: Int) {
        guard let model, !model.isRenaming, model.windows.indices.contains(index) else { return }
        model.selectedWindowIndex = index
    }

    func clickWindow(_ index: Int) {
        guard let model, !model.isRenaming, model.windows.indices.contains(index) else { return }
        let win = model.windows[index]
        close()
        WindowActivator.activate(win.info, pid: win.pid)
    }

    func selectWindow(number: Int) {
        guard let model, !model.isRenaming else { return }
        let index = number - 1
        guard model.windows.indices.contains(index) else { return }
        let win = model.windows[index]
        close()
        WindowActivator.activate(win.info, pid: win.pid)
    }

    func clickDesktop(_ index: Int) {
        guard let model, !model.isRenaming else { return }
        guard model.desktops.indices.contains(index) else { return }
        let target = model.desktops[index]
        if target.isReal { return }      // already on this desktop
        close()
        SpaceSwitcher.switchTo(spaceID: target.id, displayUUID: target.displayUUID)
    }

    /// Bracket-driven (and Cmd+Shift+digit-driven) preview: re-flags the chip
    /// row and reloads apps + windows for `target`, but does **not** call
    /// `SpaceSwitcher.switchTo`. The actual Space switch happens on commit
    /// (Cmd release) if `previewedSpaceID` still differs from `realSpaceID`.
    private func previewDesktop(at index: Int) {
        guard let model, !model.isRenaming else { return }
        guard model.desktops.indices.contains(index) else { return }
        let target = model.desktops[index]
        if target.isPreviewed { return }            // already viewing it

        spaceID = target.id                          // rename target follows preview
        model.previewedSpaceID = target.id
        model.desktopName = nameStore.name(for: target.id)
        model.desktops = model.desktops.map { vm in
            DesktopVM(id: vm.id,
                      index: vm.index,
                      name: vm.name,
                      displayUUID: vm.displayUUID,
                      isPreviewed: vm.id == target.id,
                      isReal: vm.isReal)
        }
        model.apps = DesktopAppEnumerator.appsOnSpace(target.id)
        model.selectedAppIndex = 0
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: 0, onSpace: target.id)
    }

    /// 1-based; `n` is the chip position in `model.desktops`. No-op if `n`
    /// exceeds the count.
    func previewDesktop(byNumber n: Int) {
        guard n >= 1, let model, model.desktops.indices.contains(n - 1) else { return }
        previewDesktop(at: n - 1)
    }

    func desktopNext() {
        guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
        let currentIdx = model.desktops.firstIndex(where: { $0.isPreviewed }) ?? 0
        let next = SwitcherIndex.advance(currentIdx, count: model.desktops.count)
        previewDesktop(at: next)
    }

    func desktopPrev() {
        guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
        let currentIdx = model.desktops.firstIndex(where: { $0.isPreviewed }) ?? 0
        let prev = SwitcherIndex.reverse(currentIdx, count: model.desktops.count)
        previewDesktop(at: prev)
    }

    func commit() {
        guard let model, !model.isRenaming else { return }
        let previewedUUID = model.desktops.first(where: { $0.isPreviewed })?.displayUUID
        let intent = SwitcherCommit.resolve(
            selectedWindowIndex: model.selectedWindowIndex,
            windowCount: model.windows.count,
            previewedSpaceID: model.previewedSpaceID,
            realSpaceID: model.realSpaceID,
            previewedDisplayUUID: previewedUUID
        )
        switch intent {
        case .window(let index):
            let win = model.windows[index]
            close()
            WindowActivator.activate(win.info, pid: win.pid)
        case .switchSpace(let target, let uuid):
            close()
            SpaceSwitcher.switchTo(spaceID: target, displayUUID: uuid)
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

    func beginRename(targetSpaceID: CGSSpaceID) {
        guard let model else { return }
        model.renamingDesktopID = targetSpaceID
        model.isRenaming = true
        spaceID = targetSpaceID
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishRename(save: Bool, newName: String) {
        let target = model?.renamingDesktopID ?? spaceID
        if save, let target {
            nameStore.setName(newName, for: target)
            onDesktopRenamed?()
        }
        close()
    }

    /// Loads the highlighted app's windows on `spaceID`, then captures thumbnails
    /// asynchronously. A generation token discards stale results when the user Tabs fast.
    private func loadWindows(forAppIndex appIndex: Int, onSpace spaceID: CGSSpaceID) {
        guard let model, model.apps.indices.contains(appIndex) else { return }
        generation += 1
        let token = generation
        let pid = model.apps[appIndex].pid
        // Keep the existing model.windows visible until the new fetch returns
        // (the generation token discards stale async results). Clearing here
        // used to make the VStack reflow vertically — a visible flicker on
        // every Tab press.
        Task { [weak self] in
            let scWindows = (try? await WindowEnumerator.filteredSCWindows(forPID: pid,
                                                                          onSpace: spaceID)) ?? []
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
        win.ignoresMouseEvents = false // switcher window thumbnails are clickable

        let root = SwitcherView(
            model: model,
            onHoverWindow: { [weak self] index in self?.hoverWindow(index) },
            onClickWindow: { [weak self] index in self?.clickWindow(index) },
            onBeginRename: { [weak self] target in self?.beginRename(targetSpaceID: target) },
            onFinishRename: { [weak self] save, name in self?.finishRename(save: save, newName: name) },
            onClickDesktop: { [weak self] index in self?.clickDesktop(index) }
        )
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = screen.frame
        hosting.autoresizingMask = [.width, .height]
        win.contentView = hosting
        win.setFrame(screen.frame, display: true)
        win.orderFrontRegardless() // show on top WITHOUT activating our app
        window = win
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        model = nil
        generation += 1
    }
}
