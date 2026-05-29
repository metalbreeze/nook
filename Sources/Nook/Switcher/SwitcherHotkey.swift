import CoreGraphics

/// CGEventTap implementing the native Cmd+Tab hold-and-cycle interaction,
/// scoped by the controller to current-desktop apps.
///
/// Idle: Cmd+Tab keyDown opens the switcher (swallowed).
/// Active: Tab advances, Shift+Tab reverses, Left/Right select a window,
///         Esc cancels (all swallowed); releasing Cmd commits. Requires Accessibility.
final class SwitcherHotkey {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var active = false

    var onOpen: (() -> Void)?
    var onAdvance: (() -> Void)?
    var onReverse: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?
    var onWindowLeft: (() -> Void)?
    var onWindowRight: (() -> Void)?
    var onWindowNumber: ((Int) -> Void)?
    var onDesktopPrev: (() -> Void)?
    var onDesktopNext: (() -> Void)?
    var onDesktopNumber: ((Int) -> Void)?

    private static let tabKeyCode: Int64 = 48
    private static let escKeyCode: Int64 = 53
    private static let leftKeyCode: Int64 = 123
    private static let rightKeyCode: Int64 = 124
    private static let digitKeyCodes: [Int64: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]
    private static let leftBracketKeyCode: Int64 = 33   // [
    private static let rightBracketKeyCode: Int64 = 30  // ]
    private static let backtickKeyCode: Int64 = 50   // `

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
            Log.hotkey.error("event tap DISABLED (\(type == .tapDisabledByTimeout ? "timeout" : "userInput", privacy: .public)) — re-enabling; native Cmd+Tab may leak")
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let cmdHeld = flags.contains(.maskCommand)

        if type == .flagsChanged {
            if active && !cmdHeld {
                active = false
                Log.hotkey.notice("Cmd released -> commit")
                fire(\.onCommit)
            }
            return Unmanaged.passUnretained(event) // never swallow modifier changes
        }

        // keyDown
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if !active {
            if keyCode == Self.tabKeyCode && cmdHeld {
                active = true
                Log.hotkey.notice("Cmd+Tab -> open (suppressed)")
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
        if keyCode == Self.leftKeyCode {
            fire(\.onWindowLeft)
            return nil
        }
        if keyCode == Self.rightKeyCode {
            fire(\.onWindowRight)
            return nil
        }
        if keyCode == Self.rightBracketKeyCode {
            fire(\.onDesktopNext)
            return nil
        }
        if keyCode == Self.leftBracketKeyCode {
            fire(\.onDesktopPrev)
            return nil
        }
        if keyCode == Self.backtickKeyCode {
            // macOS convention: Cmd+` = next, Cmd+Shift+` = previous.
            if flags.contains(.maskShift) {
                fire(\.onDesktopPrev)
            } else {
                fire(\.onDesktopNext)
            }
            return nil
        }
        if keyCode == Self.escKeyCode {
            active = false
            fire(\.onCancel)
            return nil
        }
        if let number = Self.digitKeyCodes[keyCode], flags.contains(.maskShift) {
            let callback = onDesktopNumber
            DispatchQueue.main.async { callback?(number) }
            return nil
        }
        if let number = Self.digitKeyCodes[keyCode] {
            let callback = onWindowNumber
            DispatchQueue.main.async { callback?(number) }
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
