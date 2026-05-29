import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyTap: HotkeyTap?
    private let overlay = OverlayController()
    private let switcher = SwitcherController()
    private var switcherHotkey: SwitcherHotkey?
    private let nameStore = DesktopNameStore()
    private let menuBarPrefs = MenuBarPreferences()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        ensurePermissions()
        startHotkey()
        startSwitcher()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        updateMenuBarTitle()
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                     accessibilityDescription: "Window Snapshot")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.addItem(withTitle: "Trigger Snapshot", action: #selector(triggerFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        let nameToggle = NSMenuItem(title: "Show Desktop Name in Menu Bar",
                                    action: #selector(toggleDesktopName(_:)),
                                    keyEquivalent: "")
        nameToggle.state = menuBarPrefs.showDesktopName ? .on : .off
        menu.addItem(nameToggle)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Accessibility Settings…", action: #selector(openAX), keyEquivalent: "")
        menu.addItem(withTitle: "Screen Recording Settings…", action: #selector(openSR), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    private func ensurePermissions() {
        if PermissionsManager.accessibilityState() == .denied {
            PermissionsManager.requestAccessibility()
        }
        if PermissionsManager.screenRecordingState() == .denied {
            PermissionsManager.requestScreenRecording()
        }
    }

    private func startHotkey() {
        let tap = HotkeyTap { [weak self] in self?.handleTrigger() }
        if !tap.start() {
            PermissionsManager.requestAccessibility()
        }
        hotkeyTap = tap
    }

    private func startSwitcher() {
        AppActivationTracker.shared.start()
        let hotkey = SwitcherHotkey()
        hotkey.onOpen = { [weak self] in self?.switcher.open() }
        hotkey.onAdvance = { [weak self] in self?.switcher.advance() }
        hotkey.onReverse = { [weak self] in self?.switcher.reverse() }
        hotkey.onWindowLeft = { [weak self] in self?.switcher.windowLeft() }
        hotkey.onWindowRight = { [weak self] in self?.switcher.windowRight() }
        hotkey.onWindowNumber = { [weak self] number in self?.switcher.selectWindow(number: number) }
        hotkey.onDesktopPrev = { [weak self] in self?.switcher.desktopPrev() }
        hotkey.onDesktopNext = { [weak self] in self?.switcher.desktopNext() }
        hotkey.onDesktopNumber = { [weak self] n in self?.switcher.previewDesktop(byNumber: n) }
        hotkey.onCancel = { [weak self] in self?.switcher.cancel() }
        hotkey.onCommit = { [weak self] in self?.switcher.commit() }
        switcher.onDesktopRenamed = { [weak self] in self?.updateMenuBarTitle() }
        switcher.suspendHotkeyTap = { [weak self] in self?.switcherHotkey?.setTapEnabled(false) }
        switcher.resumeHotkeyTap = { [weak self] in self?.switcherHotkey?.setTapEnabled(true) }
        if !hotkey.start() {
            PermissionsManager.requestAccessibility()
        }
        switcherHotkey = hotkey
    }

    @objc private func triggerFromMenu() { handleTrigger() }
    @objc private func openAX() { PermissionsManager.openAccessibilitySettings() }
    @objc private func openSR() { PermissionsManager.openScreenRecordingSettings() }

    private func updateMenuBarTitle() {
        let name: String? = menuBarPrefs.showDesktopName
            ? CurrentSpace.id().flatMap { nameStore.storedName(for: $0) }
            : nil
        statusItem?.button?.title = name ?? ""
    }

    @objc private func toggleDesktopName(_ sender: NSMenuItem) {
        menuBarPrefs.showDesktopName.toggle()
        sender.state = menuBarPrefs.showDesktopName ? .on : .off
        updateMenuBarTitle()
    }

    @objc private func activeSpaceChanged() {
        updateMenuBarTitle()
    }

    private func handleTrigger() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "App"
        Task { await presentSnapshot(pid: pid, appName: appName) }
    }

    private func presentSnapshot(pid: pid_t, appName: String) async {
        do {
            let scWindows = try await WindowEnumerator.filteredSCWindows(forPID: pid)
            guard !scWindows.isEmpty else { return }
            var thumbnails: [WindowThumbnail] = []
            for window in scWindows {
                let info = WindowEnumerator.info(from: window)
                let image = try? await ThumbnailCapturer.capture(window)
                thumbnails.append(WindowThumbnail(id: window.windowID,
                                                  image: image,
                                                  title: info.title,
                                                  info: info,
                                                  pid: pid))
            }
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }
            overlay.show(
                appName: appName,
                thumbnails: thumbnails,
                on: screen,
                onSelect: { thumb in
                    WindowActivator.activate(thumb.info, pid: thumb.pid)
                },
                onCancel: {
                    // Esc / click-away: return focus to the app that was
                    // frontmost when the snapshot was triggered.
                    NSRunningApplication(processIdentifier: pid)?.activate()
                }
            )
        } catch {
            NSLog("Nook snapshot failed: \(error.localizedDescription)")
        }
    }
}
