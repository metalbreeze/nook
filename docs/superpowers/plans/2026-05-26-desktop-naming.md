# Per-Desktop Naming in the Cmd+Tab Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an editable name for the current desktop at the top of the Cmd+Tab switcher, with a rename button that detaches the overlay into a focused text field (Enter saves, Esc cancels).

**Architecture:** A `DesktopNameStore` persists `spaceID → name` in UserDefaults; `CurrentSpace` reads the active Space ID via the private CGS API (graceful nil if unavailable). The switcher controller resolves the name on open and manages a `renameMode` (`isRenaming`) during which the hotkey's nav/commit callbacks no-op; the SwiftUI view shows the name + rename button, or a focused text field while renaming.

**Tech Stack:** Swift 5 language mode (Swift 6.3 compiler), AppKit + SwiftUI, CoreGraphics, private CGS (SkyLight) symbols. Project via XcodeGen, Developer ID signing. Tests in XCTest.

---

## File Structure

```
Sources/MyDefineShortcut/Switcher/
├── DesktopNameStore.swift   # NEW (testable): spaceID->name in UserDefaults, "Desktop" default
├── CGSSpace.swift           # NEW: private CGS current-Space ID (graceful nil)
├── SwitcherModels.swift     # MODIFY: add desktopName + isRenaming to SwitcherModel
├── SwitcherController.swift # MODIFY: resolve name on open; beginRename/finishRename; renameMode guards
└── SwitcherView.swift       # MODIFY: top name row (label + rename button / TextField)
Tests/MyDefineShortcutTests/DesktopNameStoreTests.swift  # NEW
```

Reuses unchanged: the rest of the switcher (`SwitcherHotkey`, `DesktopAppEnumerator`, `WindowEnumerator`, `ThumbnailCapturer`, `WindowActivator`, `SwitcherIndex`, `SwitcherCommit`, `FirstMouseHostingView`, `OverlayWindow`) and `AppDelegate` (no new wiring — rename is internal to controller/view; existing hotkey callbacks no-op via `isRenaming`).

**Standard commands:**
- Generate: `xcodegen generate`
- Build: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
- Test: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`

> **TDD red state in Swift:** referencing a not-yet-defined symbol makes the test target fail to COMPILE — that compile error IS the red state.

---

## Task 1: DesktopNameStore (TDD)

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/DesktopNameStore.swift`
- Test: `Tests/MyDefineShortcutTests/DesktopNameStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MyDefineShortcut

final class DesktopNameStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.desktopNames"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_defaultWhenAbsent() {
        let store = DesktopNameStore(defaults: defaults)
        XCTAssertEqual(store.name(for: 1), "Desktop")
    }

    func test_setThenGet() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("Work", for: 1)
        XCTAssertEqual(store.name(for: 1), "Work")
    }

    func test_perSpaceIndependence() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("Work", for: 1)
        store.setName("Play", for: 2)
        XCTAssertEqual(store.name(for: 1), "Work")
        XCTAssertEqual(store.name(for: 2), "Play")
    }

    func test_emptyOrWhitespaceNameRemovesEntry() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("Work", for: 1)
        store.setName("   ", for: 1)
        XCTAssertEqual(store.name(for: 1), "Desktop")
    }

    func test_nameIsTrimmed() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("  Mail  ", for: 1)
        XCTAssertEqual(store.name(for: 1), "Mail")
    }
}
```

- [ ] **Step 2: Run tests to verify red**

Run: `xcodegen generate && xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `cannot find 'DesktopNameStore' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Persists per-Space desktop names in UserDefaults. Falls back to "Desktop"
/// when a Space has no name. Keyed by the Space ID (as a String).
struct DesktopNameStore {
    static let defaultName = "Desktop"

    private let defaults: UserDefaults
    private let key = "desktopNames"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func name(for spaceID: UInt64) -> String {
        let map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return map[String(spaceID)] ?? Self.defaultName
    }

    func setName(_ name: String, for spaceID: UInt64) {
        var map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            map[String(spaceID)] = nil
        } else {
            map[String(spaceID)] = trimmed
        }
        defaults.set(map, forKey: key)
    }
}
```

- [ ] **Step 4: Run tests to verify green**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`, 5 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/DesktopNameStore.swift Tests/MyDefineShortcutTests/DesktopNameStoreTests.swift
git commit -m "feat: add per-Space desktop name store"
```

---

## Task 2: CGSSpace — current Space ID via private CGS

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/CGSSpace.swift`

- [ ] **Step 1: Write the implementation (primary: @_silgen_name)**

```swift
import CoreGraphics

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

/// Reads the current (active) Space ID via the private CGS/SkyLight API.
/// Returns nil if the call yields 0 (defensive). Private/unsupported — see spec.
enum CurrentSpace {
    static func id() -> CGSSpaceID? {
        let space = CGSGetActiveSpace(CGSMainConnectionID())
        return space == 0 ? nil : space
    }
}
```

- [ ] **Step 2: Build to verify it compiles AND links**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`.

**IF the build fails with a LINKER error** (e.g. `Undefined symbol: _CGSGetActiveSpace` or `_CGSMainConnectionID`), the `@_silgen_name` symbols didn't resolve at link time. Replace the file's contents with this dynamic-lookup (`dlsym`) version, which is link-safe and degrades to nil if the symbols are absent, then rebuild:

```swift
import Foundation

typealias CGSSpaceID = UInt64

/// Reads the current (active) Space ID via the private CGS/SkyLight API,
/// resolved dynamically with dlsym so there is no link-time dependency.
/// Returns nil if the symbols are unavailable or the call yields 0.
enum CurrentSpace {
    private typealias MainConnFn = @convention(c) () -> UInt32
    private typealias ActiveSpaceFn = @convention(c) (UInt32) -> UInt64

    static func id() -> CGSSpaceID? {
        let handle = dlopen(nil, RTLD_NOW)
        guard let connSym = dlsym(handle, "CGSMainConnectionID"),
              let spaceSym = dlsym(handle, "CGSGetActiveSpace") else {
            return nil
        }
        let mainConnection = unsafeBitCast(connSym, to: MainConnFn.self)
        let activeSpace = unsafeBitCast(spaceSym, to: ActiveSpaceFn.self)
        let space = activeSpace(mainConnection())
        return space == 0 ? nil : space
    }
}
```

Report which version you ended up using and the exact linker error if you switched.

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/CGSSpace.swift
git commit -m "feat: read current Space ID via private CGS API"
```

---

## Task 3: Extend SwitcherModel with desktopName + isRenaming

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherModels.swift`

- [ ] **Step 1: Add two published properties + initialize them**

Read the file. In `SwitcherModel`, add these two properties alongside the existing `@Published` ones:
```swift
    @Published var desktopName: String
    @Published var isRenaming: Bool
```
And in `init(apps:selectedAppIndex:)`, after the existing assignments, add:
```swift
        self.desktopName = DesktopNameStore.defaultName
        self.isRenaming = false
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherModels.swift
git commit -m "feat: add desktopName + isRenaming to SwitcherModel"
```

---

## Task 4: SwitcherController — name resolution, rename mode, guards

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherController.swift`

`showWindow(model:)` is NOT changed in this task (it's updated in Task 5).

- [ ] **Step 1: Add two properties**

Read the file. Next to `private var model: SwitcherModel?` (and `private var generation = 0`), add:
```swift
    private let nameStore = DesktopNameStore()
    private var spaceID: CGSSpaceID?
```

- [ ] **Step 2: Replace `open()` with the name-resolving version**

```swift
    func open() {
        let apps = DesktopAppEnumerator.currentDesktopApps()
        guard !apps.isEmpty else { return }
        let model = SwitcherModel(apps: apps, selectedAppIndex: 0)
        spaceID = CurrentSpace.id()
        if let spaceID {
            model.desktopName = nameStore.name(for: spaceID)
        }
        self.model = model
        showWindow(model: model)
        loadWindows(forAppIndex: 0)
    }
```

- [ ] **Step 3: Add `!model.isRenaming` guards to the nav/commit/mouse methods**

Replace each of these methods with the guarded version below (only the `guard` lines change; bodies are otherwise identical to current):

```swift
    func advance() {
        guard let model, !model.isRenaming, !model.apps.isEmpty else { return }
        model.selectedAppIndex = SwitcherIndex.advance(model.selectedAppIndex, count: model.apps.count)
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: model.selectedAppIndex)
    }

    func reverse() {
        guard let model, !model.isRenaming, !model.apps.isEmpty else { return }
        model.selectedAppIndex = SwitcherIndex.reverse(model.selectedAppIndex, count: model.apps.count)
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: model.selectedAppIndex)
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

    func commit() {
        guard let model, !model.isRenaming else { return }
        let intent = SwitcherCommit.resolve(selectedWindowIndex: model.selectedWindowIndex,
                                            windowCount: model.windows.count)
        switch intent {
        case .window(let index):
            let win = model.windows[index]
            close()
            WindowActivator.activate(win.info, pid: win.pid)
        case .app:
            guard model.apps.indices.contains(model.selectedAppIndex) else { close(); return }
            let pid = model.apps[model.selectedAppIndex].pid
            close()
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }
```

- [ ] **Step 4: Add `beginRename()` and `finishRename(save:newName:)`**

Add these methods (e.g. right after `cancel()`):
```swift
    func beginRename() {
        guard let model else { return }
        model.isRenaming = true
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishRename(save: Bool, newName: String) {
        if save, let spaceID {
            nameStore.setName(newName, for: spaceID)
        }
        close()
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -6`
Expected: `** BUILD SUCCEEDED **`. Report warnings verbatim.

- [ ] **Step 6: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherController.swift
git commit -m "feat: resolve desktop name on open + rename mode in switcher controller"
```

---

## Task 5: SwitcherView — name row + rename field

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherView.swift`
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherController.swift` (`showWindow` only)

- [ ] **Step 1: Replace `SwitcherView.swift` entirely with:**

```swift
import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onHoverWindow: (Int) -> Void
    let onClickWindow: (Int) -> Void
    let onBeginRename: () -> Void
    let onFinishRename: (Bool, String) -> Void

    @State private var editName: String = ""
    @FocusState private var nameFieldFocused: Bool

    private var selectedName: String {
        guard model.apps.indices.contains(model.selectedAppIndex) else { return "" }
        return model.apps[model.selectedAppIndex].name
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 18) {
                nameRow

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
    private var nameRow: some View {
        if model.isRenaming {
            TextField("Desktop name", text: $editName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($nameFieldFocused)
                .onAppear {
                    editName = model.desktopName
                    nameFieldFocused = true
                }
                .onSubmit { onFinishRename(true, editName) }
                .onExitCommand { onFinishRename(false, editName) }
        } else {
            HStack(spacing: 10) {
                Text(model.desktopName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Button("Rename") { onBeginRename() }
                    .buttonStyle(.bordered)
            }
        }
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

- [ ] **Step 2: Replace `showWindow(model:)` in `SwitcherController.swift` with the version wiring the two new closures:**

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
        win.ignoresMouseEvents = false

        let root = SwitcherView(
            model: model,
            onHoverWindow: { [weak self] index in self?.hoverWindow(index) },
            onClickWindow: { [weak self] index in self?.clickWindow(index) },
            onBeginRename: { [weak self] in self?.beginRename() },
            onFinishRename: { [weak self] save, name in self?.finishRename(save: save, newName: name) }
        )
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = screen.frame
        hosting.autoresizingMask = [.width, .height]
        win.contentView = hosting
        win.setFrame(screen.frame, display: true)
        win.orderFrontRegardless()
        window = win
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -6`
Expected: `** BUILD SUCCEEDED **`. Report warnings verbatim. (If `.onExitCommand` doesn't resolve, report the exact error.)

- [ ] **Step 4: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherView.swift Sources/MyDefineShortcut/Switcher/SwitcherController.swift
git commit -m "feat: desktop name row with rename field in switcher view"
```

---

## Task 6: End-to-end manual verification

**Files:** none (verification + final launch).

- [ ] **Step 1: Build and launch**

```bash
xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build
open ./build/Build/Products/Debug/MyDefineShortcut.app
```

- [ ] **Step 2: Verify name display**

Hold Cmd, tap Tab → the switcher shows a name at the top. An un-named desktop shows **"Desktop"** with a **Rename** button.

- [ ] **Step 3: Verify rename flow**

With the switcher open (Cmd held), click **Rename** → a text field focuses (prefilled with the current name). Release Cmd; the switcher stays open and doesn't switch apps. Type a name; press **Enter** → it saves and closes. Reopen with Cmd+Tab → the new name shows. Repeat and press **Esc** in the field → it discards and closes (name unchanged).

- [ ] **Step 4: Verify per-desktop + persistence**

Name desktop 1 "Work". Switch to desktop 2, Cmd+Tab → it shows "Desktop" (or its own name). Name it "Play". Switch back to desktop 1 → Cmd+Tab shows "Work". Quit and relaunch the app (same login session); names still show.

- [ ] **Step 5: Verify coexistence**

While **not** renaming, Cmd+Tab cycling, window previews (arrows/hover/click), and Ctrl+Down all still work as before.

- [ ] **Step 6: Final commit (if any tweaks were needed)**

```bash
git add -A
git commit -m "chore: finalize desktop naming after manual verification"
```

---

## Spec Coverage Check

- Show editable desktop name at top of switcher → Task 3 (model), Task 5 (nameRow), Task 6 step 2.
- "Desktop" default for unnamed → Task 1 (store default), Task 3 (model init), Task 5.
- Rename button → Task 5 (Button), Task 4 (beginRename).
- Rename detaches to focused field; Enter saves & closes, Esc cancels & closes → Task 4 (beginRename/finishRename), Task 5 (TextField onSubmit/onExitCommand), Task 6 step 3.
- renameMode no-op guards (nav/commit/mouse) → Task 4 (guards), Task 6 step 3 (release Cmd doesn't switch).
- Per-desktop identity via private CGS, graceful nil → Task 2 (CurrentSpace + dlsym fallback), Task 4 (open resolves, nil → "Desktop").
- Persistence in UserDefaults → Task 1 (DesktopNameStore), Task 6 step 4.
- No new permissions / reuse switcher → Tasks reuse existing components; no AppDelegate change.
```

