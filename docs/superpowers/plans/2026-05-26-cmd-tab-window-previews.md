# Cmd+Tab Window Previews + Window-Level Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing Cmd+Tab switcher so the highlighted app previews its current-desktop windows as thumbnails, and the user can switch to a specific window via Left/Right arrows or the mouse.

**Architecture:** Reuse `WindowEnumerator`/`ThumbnailCapturer`/`WindowActivator`/`SwitcherIndex`. Extend the switcher's `SwitcherModel` with a window list + selection, load the highlighted app's window thumbnails lazily/async (guarded by a generation token), render them in a clickable/hoverable row, and make the overlay accept mouse via `acceptsFirstMouse`. A small pure helper resolves commit intent (window vs app).

**Tech Stack:** Swift 5 language mode (Swift 6.3 compiler), AppKit + SwiftUI, CoreGraphics. Project via XcodeGen, Developer ID signing. Tests in XCTest.

---

## File Structure

```
Sources/MyDefineShortcut/Switcher/
├── SwitcherCommit.swift        # NEW (pure, tested): resolve window-vs-app commit
├── SwitcherModels.swift        # MODIFY: add SwitcherWindow; extend SwitcherModel; rename selectedIndex
├── SwitcherHotkey.swift        # MODIFY: add Left/Right arrow callbacks + handling
├── SwitcherController.swift    # MODIFY: window load (async+generation), nav, hover/click, commit, mouse overlay
├── SwitcherView.swift          # MODIFY: window-thumbnail row (hover + click)
└── FirstMouseHostingView.swift # NEW: NSHostingView that accepts first mouse
Sources/MyDefineShortcut/App/AppDelegate.swift  # MODIFY: wire arrow callbacks
Tests/MyDefineShortcutTests/SwitcherCommitTests.swift  # NEW
```

Reuses unchanged: `DesktopAppEnumerator`, `WindowEnumerator`, `ThumbnailCapturer`, `WindowActivator`, `SwitcherIndex`, `OverlayWindow`.

**Standard commands:**
- Generate: `xcodegen generate`
- Build: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
- Test: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`

> **TDD red state in Swift:** referencing a not-yet-defined symbol makes the test target fail to COMPILE — that compile error IS the red state.

---

## Task 1: SwitcherCommit (pure, TDD)

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/SwitcherCommit.swift`
- Test: `Tests/MyDefineShortcutTests/SwitcherCommitTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MyDefineShortcut

final class SwitcherCommitTests: XCTestCase {
    func test_noWindowSelected_isApp() {
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: -1, windowCount: 3), .app)
    }

    func test_validWindowIndex_isThatWindow() {
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: 0, windowCount: 3), .window(0))
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: 2, windowCount: 3), .window(2))
    }

    func test_outOfRangeIndex_isApp() {
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: 5, windowCount: 3), .app)
    }

    func test_emptyWindows_isApp() {
        XCTAssertEqual(SwitcherCommit.resolve(selectedWindowIndex: 0, windowCount: 0), .app)
    }
}
```

- [ ] **Step 2: Run tests to verify red**

Run: `xcodegen generate && xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `cannot find 'SwitcherCommit' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
enum SwitcherCommit: Equatable {
    case app
    case window(Int)

    /// Resolves what releasing Cmd should do: raise the selected window if one is
    /// selected and in range, otherwise activate the app.
    static func resolve(selectedWindowIndex: Int, windowCount: Int) -> SwitcherCommit {
        if selectedWindowIndex >= 0 && selectedWindowIndex < windowCount {
            return .window(selectedWindowIndex)
        }
        return .app
    }
}
```

- [ ] **Step 4: Run tests to verify green**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`, 4 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherCommit.swift Tests/MyDefineShortcutTests/SwitcherCommitTests.swift
git commit -m "feat: add switcher commit-intent resolver"
```

---

## Task 2: Extend SwitcherModels (+ rename selectedIndex)

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherModels.swift`
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherView.swift`
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherController.swift`

- [ ] **Step 1: Replace `SwitcherModels.swift` entirely with:**

```swift
import AppKit
import Combine
import CoreGraphics

struct SwitcherApp: Identifiable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    var id: pid_t { pid }
}

struct SwitcherWindow: Identifiable {
    let windowID: CGWindowID
    let title: String
    let info: WindowInfo
    let pid: pid_t
    var image: CGImage?
    var id: CGWindowID { windowID }
}

final class SwitcherModel: ObservableObject {
    @Published var apps: [SwitcherApp]
    @Published var selectedAppIndex: Int
    @Published var windows: [SwitcherWindow]
    @Published var selectedWindowIndex: Int   // -1 = app-level (no window selected)

    init(apps: [SwitcherApp], selectedAppIndex: Int) {
        self.apps = apps
        self.selectedAppIndex = selectedAppIndex
        self.windows = []
        self.selectedWindowIndex = -1
    }
}
```

- [ ] **Step 2: Update `SwitcherView.swift` for the rename**

Read the file. Replace every occurrence of `model.selectedIndex` with `model.selectedAppIndex` (there are two: the icon-highlight comparison `index == model.selectedAppIndex`, and `selectedName`'s `model.apps[model.selectedAppIndex].name`). Do not change anything else in this task.

- [ ] **Step 3: Update `SwitcherController.swift` for the rename**

Read the file. In `open()`, change `SwitcherModel(apps: apps, selectedIndex: 0)` to `SwitcherModel(apps: apps, selectedAppIndex: 0)`. In `advance()` and `reverse()`, replace `model.selectedIndex` with `model.selectedAppIndex`. In `commit()`, replace `model.selectedIndex` with `model.selectedAppIndex`. Do not change behavior otherwise in this task.

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. (If any `selectedIndex` reference remains, the compiler will name the file/line — fix it.)

- [ ] **Step 5: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherModels.swift Sources/MyDefineShortcut/Switcher/SwitcherView.swift Sources/MyDefineShortcut/Switcher/SwitcherController.swift
git commit -m "feat: extend SwitcherModel with window list + selection"
```

---

## Task 3: SwitcherHotkey — Left/Right arrow handling

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherHotkey.swift`

- [ ] **Step 1: Add two callbacks and two keycodes**

Read the file. Alongside the existing `var onOpen/onAdvance/onReverse/onCancel/onCommit` declarations, add:
```swift
    var onWindowLeft: (() -> Void)?
    var onWindowRight: (() -> Void)?
```
Alongside the existing `tabKeyCode`/`escKeyCode` static constants, add:
```swift
    private static let leftKeyCode: Int64 = 123
    private static let rightKeyCode: Int64 = 124
```

- [ ] **Step 2: Handle the arrows in the active branch**

In `handle(type:event:)`, inside the `// active` section (after the `keyCode == Self.tabKeyCode` block and before the `keyCode == Self.escKeyCode` block), add:
```swift
        if keyCode == Self.leftKeyCode {
            fire(\.onWindowLeft)
            return nil
        }
        if keyCode == Self.rightKeyCode {
            fire(\.onWindowRight)
            return nil
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherHotkey.swift
git commit -m "feat: add Left/Right arrow handling to switcher hotkey"
```

---

## Task 4: SwitcherController — window loading, navigation, commit

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherController.swift`

This task replaces the controller's methods with versions that load the highlighted app's windows and support window selection. `showWindow(model:)` stays as-is in this task (it's rewritten in Task 5).

- [ ] **Step 1: Add a generation token property**

Read the file. Add, next to `private var model: SwitcherModel?`:
```swift
    private var generation = 0
```

- [ ] **Step 2: Replace `open()`, `advance()`, `reverse()` and add the new methods**

Replace the existing `open()`, `advance()`, `reverse()`, `commit()`, `cancel()` methods with the following, and add `windowLeft()`, `windowRight()`, `hoverWindow(_:)`, `clickWindow(_:)`, `loadWindows(forAppIndex:)`. Keep the existing private `showWindow(model:)` and `close()` (close gets one added line, see Step 3).

```swift
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
```

- [ ] **Step 3: Bump the generation token in `close()`**

In `close()`, after `model = nil`, add `generation += 1` so any in-flight `loadWindows` Task is discarded:
```swift
    private func close() {
        window?.orderOut(nil)
        window = nil
        model = nil
        generation += 1
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -6`
Expected: `** BUILD SUCCEEDED **`. Report any concurrency warnings verbatim.

- [ ] **Step 5: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherController.swift
git commit -m "feat: load per-app window thumbnails and support window selection"
```

---

## Task 5: Interactive window-preview view + mouse-enabled overlay

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/FirstMouseHostingView.swift`
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherView.swift`
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherController.swift` (`showWindow` only)

- [ ] **Step 1: Create `FirstMouseHostingView.swift`**

```swift
import AppKit
import SwiftUI

/// Hosting view that responds to a click even when its window/app isn't active,
/// so the switcher's window thumbnails are clickable without first activating us.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

- [ ] **Step 2: Replace `SwitcherView.swift` entirely with:**

```swift
import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onHoverWindow: (Int) -> Void
    let onClickWindow: (Int) -> Void

    private var selectedName: String {
        guard model.apps.indices.contains(model.selectedAppIndex) else { return "" }
        return model.apps[model.selectedAppIndex].name
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                        appIcon(app, selected: index == model.selectedAppIndex)
                    }
                }
                Text(selectedName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !model.windows.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, win in
                            windowThumb(win, selected: index == model.selectedWindowIndex, index: index)
                        }
                    }
                }
            }
            .padding(28)
            .background(.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func appIcon(_ app: SwitcherApp, selected: Bool) -> some View {
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

    @ViewBuilder
    private func windowThumb(_ win: SwitcherWindow, selected: Bool, index: Int) -> some View {
        VStack(spacing: 6) {
            Group {
                if let image = win.image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.gray.opacity(0.3))
                        .overlay(Image(systemName: "macwindow").foregroundStyle(.white))
                }
            }
            .frame(width: 200, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(win.title.isEmpty ? "Untitled" : win.title)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 200)
        }
        .padding(8)
        .background(selected ? Color.white.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovering in if hovering { onHoverWindow(index) } }
        .onTapGesture { onClickWindow(index) }
    }
}
```

- [ ] **Step 3: Replace `showWindow(model:)` in `SwitcherController.swift` with:**

```swift
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
            onClickWindow: { [weak self] index in self?.clickWindow(index) }
        )
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = screen.frame
        hosting.autoresizingMask = [.width, .height]
        win.contentView = hosting
        win.setFrame(screen.frame, display: true)
        win.orderFrontRegardless() // show on top WITHOUT activating our app
        window = win
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -6`
Expected: `** BUILD SUCCEEDED **`. Report warnings verbatim. (If `FirstMouseHostingView(rootView:)` fails to resolve the generic initializer, report the exact error — `NSHostingView`'s `required init(rootView:)` should be inherited.)

- [ ] **Step 5: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/FirstMouseHostingView.swift Sources/MyDefineShortcut/Switcher/SwitcherView.swift Sources/MyDefineShortcut/Switcher/SwitcherController.swift
git commit -m "feat: window-preview row with hover/click + mouse-enabled overlay"
```

---

## Task 6: Wire arrow callbacks in AppDelegate

**Files:**
- Modify: `Sources/MyDefineShortcut/App/AppDelegate.swift`

- [ ] **Step 1: Wire the two new callbacks**

Read the file. In `startSwitcher()`, after the existing `hotkey.onReverse = ...` line (and before `hotkey.onCancel = ...`), add:
```swift
        hotkey.onWindowLeft = { [weak self] in self?.switcher.windowLeft() }
        hotkey.onWindowRight = { [weak self] in self?.switcher.windowRight() }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. Report warnings verbatim.

- [ ] **Step 3: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/MyDefineShortcut/App/AppDelegate.swift
git commit -m "feat: wire switcher window-navigation arrow callbacks"
```

---

## Task 7: End-to-end manual verification

**Files:** none (verification + final launch).

Requires Accessibility + Screen Recording (both already granted to the Developer-ID-signed app).

- [ ] **Step 1: Build and launch**

Run:
```bash
xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build
open ./build/Build/Products/Debug/MyDefineShortcut.app
```

- [ ] **Step 2: Verify previews + app cycling**

Have an app with 2+ windows on the current desktop. Hold **Cmd**, tap **Tab**.
Expected: the app strip appears; under the highlighted app, its current-desktop window thumbnails load (placeholders first, then images). Tab/Shift+Tab cycles apps and the preview row updates.

- [ ] **Step 3: Verify arrow window selection + commit**

Hold Cmd, Tab to a multi-window app, press **Left/Right** → a window thumbnail highlights and cycles (first press selects the first window). **Release Cmd** → that exact window is raised. Repeat and release Cmd *without* pressing an arrow → the app is activated (no specific window).

- [ ] **Step 4: Verify mouse**

Hold Cmd, open the switcher, **hover** a window thumbnail → it highlights; **click** it → that window is raised and the switcher closes.

- [ ] **Step 5: Verify fast-Tab + fallback**

- Tab quickly across several apps → no app shows another app's thumbnails (generation token).
- Press Esc → closes, no switch.
- (Optional) Temporarily revoke Screen Recording → windows show as icon placeholders; arrow/click selection still raises the right window. Re-enable afterward.

- [ ] **Step 6: Verify coexistence**

**Ctrl+Down** still shows the window-snapshot overlay; the two features don't interfere.

- [ ] **Step 7: Final commit (if any tweaks were needed)**

```bash
git add -A
git commit -m "chore: finalize Cmd+Tab window previews after manual verification"
```

---

## Spec Coverage Check

- Preview highlighted app's current-desktop windows → Task 4 (loadWindows via WindowEnumerator), Task 5 (window row), Task 7 step 2.
- App-level default; Tab cycles apps → Task 4 (selectedWindowIndex reset to -1 on app change), Task 7 step 2.
- Left/Right arrows select windows (first press → first window) → Task 3 (hotkey), Task 4 (windowLeft/windowRight), Task 6 (wiring), Task 7 step 3.
- Mouse hover highlights, click switches → Task 5 (onHover/onTapGesture, FirstMouseHostingView, ignoresMouseEvents=false), Task 7 step 4.
- Release Cmd → window if selected else app → Task 1 (SwitcherCommit), Task 4 (commit), Task 7 step 3.
- Lazy async thumbnail capture + generation token → Task 4 (loadWindows), Task 7 step 5.
- Screen Recording required, placeholder fallback → Task 5 (placeholder), Task 7 step 5.
- Reuse existing units → Tasks 4/5 (WindowEnumerator/ThumbnailCapturer/WindowActivator/SwitcherIndex).
- Window-level raise via Accessibility → Task 4 (WindowActivator.activate), Task 7 steps 3-4.
- Coexist with Ctrl+Down + existing switcher → Task 6/7 step 6.
```

