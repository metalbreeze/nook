import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyTap: HotkeyTap?
    private let overlay = OverlayController()
    private let switcher = SwitcherController()
    private var switcherHotkey: SwitcherHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        ensurePermissions()
        startHotkey()
        startSwitcher()
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                     accessibilityDescription: "Window Snapshot")
        let menu = NSMenu()
        menu.addItem(withTitle: "Trigger Snapshot", action: #selector(triggerFromMenu), keyEquivalent: "")
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
        let hotkey = SwitcherHotkey()
        hotkey.onOpen = { [weak self] in self?.switcher.open() }
        hotkey.onAdvance = { [weak self] in self?.switcher.advance() }
        hotkey.onReverse = { [weak self] in self?.switcher.reverse() }
        hotkey.onCancel = { [weak self] in self?.switcher.cancel() }
        hotkey.onCommit = { [weak self] in self?.switcher.commit() }
        if !hotkey.start() {
            PermissionsManager.requestAccessibility()
        }
        switcherHotkey = hotkey
    }

    @objc private func triggerFromMenu() { handleTrigger() }
    @objc private func openAX() { PermissionsManager.openAccessibilitySettings() }
    @objc private func openSR() { PermissionsManager.openScreenRecordingSettings() }

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
            NSLog("MyDefineShortcut snapshot failed: \(error.localizedDescription)")
        }
    }
}
