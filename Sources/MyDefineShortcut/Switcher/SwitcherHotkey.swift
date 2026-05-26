import CoreGraphics

/// CGEventTap implementing the native Cmd+Tab hold-and-cycle interaction,
/// scoped by the controller to current-desktop apps.
///
/// Idle: Cmd+Tab keyDown opens the switcher (swallowed).
/// Active: Tab advances, Shift+Tab reverses, Esc cancels (all swallowed);
///         releasing Cmd commits. Requires Accessibility.
final class SwitcherHotkey {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var active = false

    var onOpen: (() -> Void)?
    var onAdvance: (() -> Void)?
    var onReverse: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    private static let tabKeyCode: Int64 = 48
    private static let escKeyCode: Int64 = 53

    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let hotkey = Unmanaged<SwitcherHotkey>.fromOpaque(refcon).takeUnretainedValue()
            return hotkey.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            // SAFETY: passUnretained because AppDelegate owns this SwitcherHotkey for
            // the app's lifetime and calls stop() before the reference can be released.
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let cmdHeld = flags.contains(.maskCommand)

        if type == .flagsChanged {
            if active && !cmdHeld {
                active = false
                fire(\.onCommit)
            }
            return Unmanaged.passUnretained(event) // never swallow modifier changes
        }

        // keyDown
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if !active {
            if keyCode == Self.tabKeyCode && cmdHeld {
                active = true
                fire(\.onOpen)
                return nil // suppress system Cmd+Tab
            }
            return Unmanaged.passUnretained(event)
        }

        // active
        if keyCode == Self.tabKeyCode {
            if flags.contains(.maskShift) {
                fire(\.onReverse)
            } else {
                fire(\.onAdvance)
            }
            return nil
        }
        if keyCode == Self.escKeyCode {
            active = false
            fire(\.onCancel)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func fire(_ keyPath: KeyPath<SwitcherHotkey, (() -> Void)?>) {
        let callback = self[keyPath: keyPath]
        DispatchQueue.main.async { callback?() }
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
}
