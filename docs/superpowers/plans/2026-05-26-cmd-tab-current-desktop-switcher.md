# Cmd+Tab Current-Desktop App Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a custom Cmd+Tab app switcher to the existing MyDefineShortcut menu-bar app that lists only apps with a window on the current desktop, with native hold-Cmd / Tab-cycle / release-to-switch interaction.

**Architecture:** Pure-logic units (the current-desktop app-list builder and the wrap-around index cycler) are unit-tested. A CGEventTap watching `keyDown` + `flagsChanged` drives a `@MainActor` controller that shows a SwiftUI icon strip and activates the chosen app. Reuses the existing `OverlayWindow` and `CGWindowList` current-Space patterns.

**Tech Stack:** Swift 5 language mode (Swift 6.3 compiler), AppKit + SwiftUI, CoreGraphics event taps + `CGWindowList`. Project generated via XcodeGen; signed with the Developer ID identity (stable TCC). Tests in XCTest.

---

## File Structure

All new files live under a new `Switcher/` group (auto-discovered by XcodeGen via the existing `Sources/MyDefineShortcut` glob):

```
Sources/MyDefineShortcut/
├── Switcher/
│   ├── DesktopAppList.swift        # PURE: RawAppWindow + ordered unique current-desktop PIDs (tested)
│   ├── SwitcherIndex.swift         # PURE: wrap-around advance/reverse (tested)
│   ├── SwitcherModels.swift        # SwitcherApp (icon/name/pid) + SwitcherModel (ObservableObject)
│   ├── DesktopAppEnumerator.swift  # CGWindowList -> DesktopAppList -> [SwitcherApp] (system)
│   ├── SwitcherView.swift          # SwiftUI centered icon strip
│   ├── SwitcherController.swift    # @MainActor overlay window + state
│   └── SwitcherHotkey.swift        # CGEventTap state machine (keyDown + flagsChanged)
└── App/AppDelegate.swift           # MODIFY: start SwitcherHotkey, wire to SwitcherController
Tests/MyDefineShortcutTests/
├── DesktopAppListTests.swift
└── SwitcherIndexTests.swift
```

Reuses existing `Sources/MyDefineShortcut/Overlay/OverlayWindow.swift`.

**Standard commands:**
- Generate project (after adding files): `xcodegen generate`
- Build: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
- Test: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
- Launch: `open ./build/Build/Products/Debug/MyDefineShortcut.app`

> **TDD red state in Swift:** referencing a not-yet-defined symbol makes the test target fail to COMPILE — that compile error (naming the missing symbol) IS the red state.

---

## Task 1: DesktopAppList (pure, TDD)

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/DesktopAppList.swift`
- Test: `Tests/MyDefineShortcutTests/DesktopAppListTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MyDefineShortcut

final class DesktopAppListTests: XCTestCase {
    private func win(_ pid: pid_t, layer: Int = 0, onScreen: Bool = true) -> RawAppWindow {
        RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen)
    }

    func test_dedupsAndPreservesZOrder() {
        // z-order front-to-back: app 10, app 20, app 10 again, app 30
        let input = [win(10), win(20), win(10), win(30)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10, 20, 30])
    }

    func test_excludesNonZeroLayerAndOffScreen() {
        let input = [win(10), win(20, layer: 25), win(30, onScreen: false)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10])
    }

    func test_movesFrontmostToFront() {
        let input = [win(20), win(30), win(10)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10, 20, 30])
    }

    func test_frontmostNotInListLeavesOrderUnchanged() {
        let input = [win(20), win(30)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 99), [20, 30])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `cannot find 'RawAppWindow' / 'DesktopAppList' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

struct RawAppWindow: Equatable {
    let ownerPID: pid_t
    let layer: Int
    let isOnScreen: Bool
}

enum DesktopAppList {
    /// De-duplicated app PIDs that have at least one normal (layer 0), on-screen
    /// window, in first-appearance (z-order) order, with the current app first.
    static func appPIDs(from windows: [RawAppWindow], frontmostPID: pid_t) -> [pid_t] {
        var seen = Set<pid_t>()
        var ordered: [pid_t] = []
        for window in windows where window.layer == 0 && window.isOnScreen {
            if seen.insert(window.ownerPID).inserted {
                ordered.append(window.ownerPID)
            }
        }
        if let index = ordered.firstIndex(of: frontmostPID), index != 0 {
            ordered.remove(at: index)
            ordered.insert(frontmostPID, at: 0)
        }
        return ordered
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`, 4 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/DesktopAppList.swift Tests/MyDefineShortcutTests/DesktopAppListTests.swift
git commit -m "feat: add current-desktop app-list builder"
```

---

## Task 2: SwitcherIndex (pure, TDD)

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/SwitcherIndex.swift`
- Test: `Tests/MyDefineShortcutTests/SwitcherIndexTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MyDefineShortcut

final class SwitcherIndexTests: XCTestCase {
    func test_advanceMidList() {
        XCTAssertEqual(SwitcherIndex.advance(0, count: 3), 1)
        XCTAssertEqual(SwitcherIndex.advance(1, count: 3), 2)
    }

    func test_advanceWraps() {
        XCTAssertEqual(SwitcherIndex.advance(2, count: 3), 0)
    }

    func test_reverseWraps() {
        XCTAssertEqual(SwitcherIndex.reverse(0, count: 3), 2)
        XCTAssertEqual(SwitcherIndex.reverse(2, count: 3), 1)
    }

    func test_singleItemStaysAtZero() {
        XCTAssertEqual(SwitcherIndex.advance(0, count: 1), 0)
        XCTAssertEqual(SwitcherIndex.reverse(0, count: 1), 0)
    }

    func test_zeroCountIsSafe() {
        XCTAssertEqual(SwitcherIndex.advance(0, count: 0), 0)
        XCTAssertEqual(SwitcherIndex.reverse(0, count: 0), 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `cannot find 'SwitcherIndex' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
enum SwitcherIndex {
    static func advance(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + 1) % count
    }

    static func reverse(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index - 1 + count) % count
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`, all SwitcherIndex tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherIndex.swift Tests/MyDefineShortcutTests/SwitcherIndexTests.swift
git commit -m "feat: add switcher index wrap-around cycling"
```

---

## Task 3: SwitcherApp/SwitcherModel + DesktopAppEnumerator

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/SwitcherModels.swift`
- Create: `Sources/MyDefineShortcut/Switcher/DesktopAppEnumerator.swift`

- [ ] **Step 1: Write `SwitcherModels.swift`**

```swift
import AppKit
import SwiftUI

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
```

- [ ] **Step 2: Write `DesktopAppEnumerator.swift`**

```swift
import AppKit
import CoreGraphics

enum DesktopAppEnumerator {
    /// Apps with at least one normal window on the current desktop, current app
    /// first, in window z-order. Excludes this process. No Screen Recording needed.
    static func currentDesktopApps() -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = onScreenWindows()
        let pids = DesktopAppList.appPIDs(from: raw, frontmostPID: frontmostPID)
        return pids.compactMap { pid in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            return SwitcherApp(pid: pid, name: app.localizedName ?? "", icon: app.icon)
        }
    }

    private static func onScreenWindows() -> [RawAppWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != selfPID else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            return RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: true)
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherModels.swift Sources/MyDefineShortcut/Switcher/DesktopAppEnumerator.swift
git commit -m "feat: add switcher app model and current-desktop app enumerator"
```

---

## Task 4: SwitcherView (SwiftUI)

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/SwitcherView.swift`

- [ ] **Step 1: Write `SwitcherView.swift`**

```swift
import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    private var selectedName: String {
        guard model.apps.indices.contains(model.selectedIndex) else { return "" }
        return model.apps[model.selectedIndex].name
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                        icon(for: app, selected: index == model.selectedIndex)
                    }
                }
                Text(selectedName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(28)
            .background(.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func icon(for app: SwitcherApp, selected: Bool) -> some View {
        Group {
            if let image = app.icon {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.white)
            }
        }
        .frame(width: 64, height: 64)
        .padding(10)
        .background(selected ? Color.white.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherView.swift
git commit -m "feat: add SwitcherView icon strip"
```

---

## Task 5: SwitcherController (@MainActor)

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/SwitcherController.swift`

- [ ] **Step 1: Write `SwitcherController.swift`**

```swift
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
        let model = SwitcherModel(apps: apps, selectedIndex: 0)
        self.model = model
        showWindow(model: model)
    }

    func advance() {
        guard let model, !model.apps.isEmpty else { return }
        model.selectedIndex = SwitcherIndex.advance(model.selectedIndex, count: model.apps.count)
    }

    func reverse() {
        guard let model, !model.apps.isEmpty else { return }
        model.selectedIndex = SwitcherIndex.reverse(model.selectedIndex, count: model.apps.count)
    }

    /// Releasing Cmd: switch to the highlighted app and close.
    func commit() {
        guard let model, model.apps.indices.contains(model.selectedIndex) else {
            close()
            return
        }
        let pid = model.apps[model.selectedIndex].pid
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherController.swift
git commit -m "feat: add switcher controller (overlay window + state)"
```

---

## Task 6: SwitcherHotkey (CGEventTap state machine)

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/SwitcherHotkey.swift`

- [ ] **Step 1: Write `SwitcherHotkey.swift`**

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -6`
Expected: `** BUILD SUCCEEDED **`. Report any concurrency warnings verbatim. (If the compiler errors on capturing the optional callbacks, do NOT restructure broadly — report the exact message.)

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherHotkey.swift
git commit -m "feat: add Cmd+Tab event-tap state machine"
```

---

## Task 7: Wire the switcher into AppDelegate

**Files:**
- Modify: `Sources/MyDefineShortcut/App/AppDelegate.swift`

- [ ] **Step 1: Add stored properties**

In `AppDelegate`, alongside the existing `hotkeyTap` and `overlay` properties, add:

```swift
    private let switcher = SwitcherController()
    private var switcherHotkey: SwitcherHotkey?
```

- [ ] **Step 2: Start the switcher hotkey in `applicationDidFinishLaunching`**

Add a call `startSwitcher()` after the existing `startHotkey()` line in `applicationDidFinishLaunching`, then add this method:

```swift
    private func startSwitcher() {
        let hotkey = SwitcherHotkey()
        hotkey.onOpen = { [weak self] in self?.switcher.open() }
        hotkey.onAdvance = { [weak self] in self?.switcher.advance() }
        hotkey.onReverse = { [weak self] in self?.switcher.reverse() }
        hotkey.onCancel = { [weak self] in self?.switcher.cancel() }
        hotkey.onCommit = { [weak self] in self?.switcher.commit() }
        _ = hotkey.start()
        switcherHotkey = hotkey
    }
```

Note: the callbacks call `@MainActor` `SwitcherController` methods; `SwitcherHotkey` always invokes them via `DispatchQueue.main.async`, so they run on the main thread. In Swift 5 language mode this compiles. If you hit a hard concurrency ERROR (not a warning), wrap each body as `{ [weak self] in MainActor.assumeIsolated { self?.switcher.open() } }` and report what you changed.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -6`
Expected: `** BUILD SUCCEEDED **`. Report warnings verbatim.

- [ ] **Step 4: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/App/AppDelegate.swift
git commit -m "feat: wire Cmd+Tab switcher hotkey into AppDelegate"
```

---

## Task 8: End-to-end manual verification

**Files:** none (verification + final launch).

Requires Accessibility (already granted to the Developer-ID-signed app). No Screen Recording needed.

- [ ] **Step 1: Build and launch**

Run:
```bash
xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build
open ./build/Build/Products/Debug/MyDefineShortcut.app
```

- [ ] **Step 2: Verify Cmd+Tab interception + current-desktop scoping**

With several apps open — at least one app whose windows are ALL on a *different* desktop (Space) — press and hold **Cmd**, tap **Tab**.
Expected:
- The system Cmd+Tab switcher does NOT appear; our custom icon strip appears instead.
- Only apps with a window on the **current** desktop are shown. The app whose windows are all on another desktop is absent.
- The current app's icon is highlighted first.

*If the system switcher still appears:* this is the documented suppression risk — report it rather than layering fixes.

- [ ] **Step 3: Verify cycling + commit + cancel**

- Hold Cmd; tap Tab repeatedly → highlight advances and wraps; **Shift+Tab** moves backward.
- Release Cmd → the app switches to the highlighted app; the strip disappears.
- Press Cmd+Tab again, then **Esc** (still holding Cmd) → strip disappears, no switch, focus stays on the current app.
- Press Cmd+Tab once and release immediately → stays on the current app (no switch), per design.

- [ ] **Step 4: Verify coexistence with Ctrl+Down**

Press **Ctrl+Down** → the window-snapshot overlay still works as before. The two features don't interfere.

- [ ] **Step 5: Final commit (if any tweaks were needed)**

```bash
git add -A
git commit -m "chore: finalize Cmd+Tab switcher after manual verification"
```

---

## Spec Coverage Check

- Intercept Cmd+Tab + suppress system switcher → Task 6 (tap, swallow), Task 8 step 2.
- Current-desktop apps only → Task 1 (list builder), Task 3 (enumerator via CGWindowList onScreen), Task 8 step 2.
- App icons strip → Task 3 (icons), Task 4 (view).
- Hold-Cmd / Tab cycle / Shift+Tab reverse / Esc cancel / release-to-switch → Task 6 (state machine), Task 5 (controller), Task 8 step 3.
- Current app first, index 0, quick-tap = no switch → Task 1 (frontmost-first), Task 5 (`selectedIndex = 0`), Task 8 step 3.
- App-level activation → Task 5 (`NSRunningApplication.activate`).
- Z-order ordering → Task 1 (first-appearance order), Task 3 (CGWindowList z-order).
- Accessibility only, no Screen Recording → Task 3 (CGWindowList owner PID, no capture), Task 8 (no SR step).
- Coexist with Ctrl+Down → Task 7 (separate hotkey), Task 8 step 4.
- Single display → Task 5 (`NSScreen.main`).
- Don't steal focus until commit → Task 5 (`orderFrontRegardless`, `ignoresMouseEvents`, no `NSApp.activate`).
```

