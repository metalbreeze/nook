import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private var window: OverlayWindow?
    private var keyMonitor: Any?

    func show(appName: String,
              thumbnails: [WindowThumbnail],
              on screen: NSScreen,
              onSelect: @escaping (WindowThumbnail) -> Void) {
        dismiss()

        let root = SnapshotView(
            appName: appName,
            thumbnails: thumbnails,
            onSelect: { [weak self] thumb in
                self?.dismiss()
                onSelect(thumb)
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let win = OverlayWindow(contentRect: screen.frame,
                                styleMask: [.borderless],
                                backing: .buffered,
                                defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visual = NSVisualEffectView(frame: screen.frame)
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: root)
        hosting.frame = visual.bounds
        hosting.autoresizingMask = [.width, .height]
        visual.addSubview(hosting)

        win.contentView = visual
        win.setFrame(screen.frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window?.orderOut(nil)
        window = nil
    }
}
