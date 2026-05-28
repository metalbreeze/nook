# Cmd+Tab Desktop Chip Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a horizontal row of "desktop chips" to the Cmd+Tab overlay that lists the current screen's user-space desktops and lets the user mouse-click — or press `Cmd+]` / `Cmd+[` — to switch desktops.

**Architecture:** Three new tiny units (`DesktopLabel`, `DesktopEnumerator`, `SpaceSwitcher`) plus two private-CGS symbol bindings added to `CGSSpace.swift`. The existing `SwitcherModel` / `SwitcherView` / `SwitcherController` / `SwitcherHotkey` / `AppDelegate` get small extensions to display the row, route clicks, and route the bracket-key shortcuts.

**Tech Stack:** Swift 5, SwiftUI, AppKit, CoreGraphics; private CGS / SkyLight via `@_silgen_name`; XCTest.

**Branch:** `feature/desktop-chip-row` (already cut from `main` and currently checked out; the spec at `docs/superpowers/specs/2026-05-28-cmd-tab-desktop-list-design.md` is the first commit on it).

---

## Conventions used in this plan

- **XcodeGen regeneration:** the Xcode project is generated from `project.yml`. Whenever a task **creates** a new source or test file under `Sources/Nook` or `Tests/NookTests`, run `xcodegen generate` so the new file is added to the right target. Existing files do not need a regen for content-only edits.
- **Build/test command:** `xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS'`. Tests pass when the output contains `** TEST SUCCEEDED **` and the previously-passing 37 tests remain green.
- **Commits:** keep them small and feature-named. The trailer `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` is used by this repo.

---

## Task 1: `DesktopLabel` (pure, TDD)

**Files:**
- Create: `Sources/Nook/Switcher/DesktopLabel.swift`
- Create: `Tests/NookTests/DesktopLabelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/NookTests/DesktopLabelTests.swift`:

```swift
import XCTest
@testable import Nook

final class DesktopLabelTests: XCTestCase {
    func test_namedDesktopUsesStoredName() {
        XCTAssertEqual(DesktopLabel.label(index: 1, storedName: "Work"), "1  Work")
    }

    func test_unnamedDesktopFallsBackToDesktopN() {
        XCTAssertEqual(DesktopLabel.label(index: 3, storedName: nil), "3  Desktop 3")
    }

    func test_indexIsPreservedAtSmallAndLargeValues() {
        XCTAssertEqual(DesktopLabel.label(index: 1, storedName: nil), "1  Desktop 1")
        XCTAssertEqual(DesktopLabel.label(index: 9, storedName: "Mail"), "9  Mail")
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project and run tests to see the compile failure**

```sh
xcodegen generate
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: build failure with `cannot find 'DesktopLabel' in scope` (the type does not exist yet).

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/Nook/Switcher/DesktopLabel.swift`:

```swift
import Foundation

/// Pure formatter for the desktop chip label shown in the Cmd+Tab overlay.
///
/// `index` is the 1-based position in the current screen's user-space
/// desktop list (fullscreen-app Spaces are skipped in numbering).
/// `storedName` is the user-given name from `DesktopNameStore.storedName`
/// (nil when the desktop has never been named).
enum DesktopLabel {
    static func label(index: Int, storedName: String?) -> String {
        let name = storedName ?? "Desktop \(index)"
        return "\(index)  \(name)"
    }
}
```

- [ ] **Step 4: Regenerate and run the tests, expecting them to pass**

```sh
xcodegen generate
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: `Test Suite 'All tests' passed` reporting **40 tests** executed (37 prior + 3 new), and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```sh
git add Sources/Nook/Switcher/DesktopLabel.swift Tests/NookTests/DesktopLabelTests.swift
git commit -m "$(cat <<'EOF'
feat: add DesktopLabel formatter (TDD)

Produces chip labels like "1  Work" or "3  Desktop 3" from a 1-based index
and the optional stored name. Pure, unit-tested.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Private CGS bindings + `SpaceSwitcher`

**Files:**
- Modify: `Sources/Nook/Switcher/CGSSpace.swift` (add 2 more `@_silgen_name` symbols at the top)
- Create: `Sources/Nook/Switcher/SpaceSwitcher.swift`

No unit tests: both symbols are side-effecting calls into the WindowServer.

- [ ] **Step 1: Add the two new private CGS bindings to `CGSSpace.swift`**

Open `Sources/Nook/Switcher/CGSSpace.swift`. After the existing `CGSGetActiveSpace` declaration (around line 11), append:

```swift
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(
    _ cid: CGSConnectionID,
    _ displayUUID: CFString,
    _ spaceID: CGSSpaceID
)
```

The full file should now contain — at the top, before the `enum CurrentSpace` declaration — four `@_silgen_name`-imported symbols: `CGSMainConnectionID`, `CGSGetActiveSpace`, `CGSCopyManagedDisplaySpaces`, `CGSManagedDisplaySetCurrentSpace`.

- [ ] **Step 2: Create `SpaceSwitcher.swift`**

Create `Sources/Nook/Switcher/SpaceSwitcher.swift`:

```swift
import CoreGraphics

/// One-shot helper that asks WindowServer to make `spaceID` the active Space
/// on the display identified by `displayUUID`. Uses the same private CGS /
/// SkyLight surface as `CurrentSpace` — unsupported by Apple but stable
/// across macOS releases for many years. No-ops if the target is already
/// the active Space.
enum SpaceSwitcher {
    static func switchTo(spaceID: CGSSpaceID, displayUUID: String) {
        guard spaceID != CurrentSpace.id() else { return }
        CGSManagedDisplaySetCurrentSpace(
            CGSMainConnectionID(),
            displayUUID as CFString,
            spaceID
        )
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project and build**

```sh
xcodegen generate
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`, no errors.

- [ ] **Step 4: Run the existing tests to confirm no regression**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 40 tests pass, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```sh
git add Sources/Nook/Switcher/CGSSpace.swift Sources/Nook/Switcher/SpaceSwitcher.swift
git commit -m "$(cat <<'EOF'
feat: add private CGS bindings and SpaceSwitcher for cross-Space switching

Binds CGSCopyManagedDisplaySpaces (enumerate per-display Space stacks) and
CGSManagedDisplaySetCurrentSpace (switch a display to a given Space) via
@_silgen_name, consistent with the existing CGSGetActiveSpace usage.
SpaceSwitcher.switchTo is a single side-effecting call with a guard that
no-ops if the target already is the active Space.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `DesktopEnumerator`

**Files:**
- Create: `Sources/Nook/Switcher/DesktopEnumerator.swift`

No unit tests: the call traverses private CGS data on the live WindowServer. Verification happens in the end-to-end manual run (Task 8).

- [ ] **Step 1: Create the new file**

Create `Sources/Nook/Switcher/DesktopEnumerator.swift`:

```swift
import AppKit
import CoreGraphics

/// One row in the Cmd+Tab desktop chip strip.
struct DesktopEntry: Equatable {
    let spaceID: CGSSpaceID
    let displayUUID: String
    /// 1-based position within the screen's user-space desktops (contiguous,
    /// fullscreen-app Spaces are skipped in numbering).
    let indexInDisplay: Int
}

/// Reads the active per-display Space layout via the private
/// CGSCopyManagedDisplaySpaces API and returns the user-space desktops on
/// the given screen in Mission Control order.
enum DesktopEnumerator {
    static func desktopsForCurrentScreen(_ screen: NSScreen) -> [DesktopEntry] {
        guard let uuidString = displayUUIDString(for: screen) else { return [] }
        let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as NSArray
        for case let displayDict as [String: Any] in raw {
            let displayID =
                displayDict["Display Identifier"] as? String
                ?? displayDict["DisplayIdentifier"] as? String
            guard displayID == uuidString else { continue }
            guard let spaces = displayDict["Spaces"] as? [[String: Any]] else { return [] }
            var result: [DesktopEntry] = []
            var index = 1
            for space in spaces {
                let type = (space["type"] as? NSNumber)?.intValue ?? -1
                guard type == 0 else { continue } // 0 = user desktop
                guard let sid = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
                else { continue }
                result.append(DesktopEntry(spaceID: sid,
                                           displayUUID: uuidString,
                                           indexInDisplay: index))
                index += 1
            }
            return result
        }
        return []
    }

    private static func displayUUIDString(for screen: NSScreen) -> String? {
        guard let number =
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuidRef) as String
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project and build**

```sh
xcodegen generate
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the existing tests to confirm no regression**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 40 tests pass.

- [ ] **Step 4: Commit**

```sh
git add Sources/Nook/Switcher/DesktopEnumerator.swift
git commit -m "$(cat <<'EOF'
feat: enumerate user-space desktops on a given screen

DesktopEnumerator reads CGSCopyManagedDisplaySpaces, matches the screen
via CGDisplayCreateUUIDFromDisplayID, filters to user-space type, and
returns ordered (spaceID, displayUUID, 1-based index) entries. Empty
array on failure for graceful degradation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Extend `SwitcherModel` with `DesktopVM` + `desktops` field

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherModels.swift`

No new tests: the change is a data-only extension with no logic.

- [ ] **Step 1: Edit `SwitcherModels.swift` to add `DesktopVM` and the new field**

Open `Sources/Nook/Switcher/SwitcherModels.swift`. Replace the entire file contents with:

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

/// View model for one desktop chip in the Cmd+Tab overlay.
struct DesktopVM: Identifiable, Equatable {
    let id: CGSSpaceID            // also the Space ID
    let label: String             // e.g. "1  Work" or "3  Desktop 3"
    let displayUUID: String
    let isCurrent: Bool
}

final class SwitcherModel: ObservableObject {
    @Published var apps: [SwitcherApp]
    @Published var selectedAppIndex: Int
    @Published var windows: [SwitcherWindow]
    @Published var selectedWindowIndex: Int   // -1 = app-level (no window selected)
    @Published var desktopName: String
    @Published var isRenaming: Bool
    @Published var desktops: [DesktopVM]

    init(apps: [SwitcherApp], selectedAppIndex: Int, desktops: [DesktopVM] = []) {
        self.apps = apps
        self.selectedAppIndex = selectedAppIndex
        self.windows = []
        self.selectedWindowIndex = -1
        self.desktopName = DesktopNameStore.defaultName
        self.isRenaming = false
        self.desktops = desktops
    }
}
```

- [ ] **Step 2: Build to confirm the data model still compiles for existing call sites**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. Existing `SwitcherModel(apps:selectedAppIndex:)` call sites work because the new `desktops:` parameter has a default value of `[]`.

- [ ] **Step 3: Run the full test suite to confirm no regression**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 40 tests pass.

- [ ] **Step 4: Commit**

```sh
git add Sources/Nook/Switcher/SwitcherModels.swift
git commit -m "$(cat <<'EOF'
feat: add DesktopVM and desktops field to SwitcherModel

DesktopVM carries (spaceID, label, displayUUID, isCurrent) for one chip in
the new Cmd+Tab desktop row. The new desktops field is a published array;
the init parameter defaults to [] so existing call sites stay green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Extend `SwitcherController` — populate desktops, click and prev/next

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherController.swift`

No new tests: the controller wraps private CGS calls. Manual end-to-end verification in Task 8 covers it.

- [ ] **Step 1: Update `open()` to enumerate desktops and build view models**

Open `Sources/Nook/Switcher/SwitcherController.swift`. Replace the existing `open()` body with:

```swift
    func open() {
        let apps = DesktopAppEnumerator.currentDesktopApps()
        guard !apps.isEmpty else { return }
        let currentSpaceID = CurrentSpace.id()
        spaceID = currentSpaceID
        let screen = NSScreen.main ?? NSScreen.screens.first
        let entries = screen.map { DesktopEnumerator.desktopsForCurrentScreen($0) } ?? []
        let desktopVMs: [DesktopVM] = entries.map { entry in
            DesktopVM(
                id: entry.spaceID,
                label: DesktopLabel.label(
                    index: entry.indexInDisplay,
                    storedName: nameStore.storedName(for: entry.spaceID)
                ),
                displayUUID: entry.displayUUID,
                isCurrent: entry.spaceID == currentSpaceID
            )
        }
        let model = SwitcherModel(apps: apps,
                                  selectedAppIndex: 0,
                                  desktops: desktopVMs)
        if let currentSpaceID {
            model.desktopName = nameStore.name(for: currentSpaceID)
        }
        self.model = model
        showWindow(model: model)
        loadWindows(forAppIndex: 0)
    }
```

- [ ] **Step 2: Add the three new controller methods**

Still in `Sources/Nook/Switcher/SwitcherController.swift`, immediately after the existing `selectWindow(number:)` method, insert:

```swift
    func clickDesktop(_ index: Int) {
        guard let model, !model.isRenaming else { return }
        guard model.desktops.indices.contains(index) else { return }
        let target = model.desktops[index]
        if target.isCurrent { return }      // no-op on the current chip
        close()
        SpaceSwitcher.switchTo(spaceID: target.id, displayUUID: target.displayUUID)
    }

    func desktopNext() {
        guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
        let currentIdx = model.desktops.firstIndex(where: { $0.isCurrent }) ?? 0
        let next = SwitcherIndex.advance(currentIdx, count: model.desktops.count)
        clickDesktop(next)
    }

    func desktopPrev() {
        guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
        let currentIdx = model.desktops.firstIndex(where: { $0.isCurrent }) ?? 0
        let prev = SwitcherIndex.reverse(currentIdx, count: model.desktops.count)
        clickDesktop(prev)
    }
```

- [ ] **Step 3: Build to verify the controller still compiles**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. The `SwitcherView` initializer in `showWindow` is unchanged at this stage (still six closures, no `onClickDesktop` yet) — Task 7 wires the seventh closure.

- [ ] **Step 4: Run the full test suite**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 40 tests pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/Nook/Switcher/SwitcherController.swift
git commit -m "$(cat <<'EOF'
feat: populate desktops and add click/prev/next in SwitcherController

open() enumerates the current screen's user-space desktops, marks the
current one, and stores them as DesktopVMs in the model. clickDesktop
closes the overlay and switches via SpaceSwitcher (no-op on current);
desktopPrev/Next compute the wrapped neighbor and call clickDesktop.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Extend `SwitcherHotkey` — bracket-key handling

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherHotkey.swift`

No new unit tests: the file is a `CGEventTap` integration. End-to-end verification in Task 8.

- [ ] **Step 1: Add the two new keycodes and callbacks**

Open `Sources/Nook/Switcher/SwitcherHotkey.swift`. In the property declarations near the top of the class, after the `onWindowNumber` line, add:

```swift
    var onDesktopPrev: (() -> Void)?
    var onDesktopNext: (() -> Void)?
```

Then in the keycode constants section, after the `digitKeyCodes` dictionary, add:

```swift
    private static let leftBracketKeyCode: Int64 = 33   // [
    private static let rightBracketKeyCode: Int64 = 30  // ]
```

- [ ] **Step 2: Handle the bracket keys in the active state**

In the same file, find the `// active` comment in `handle(type:event:)`. Below the existing right-arrow check (the block that ends with `fire(\.onWindowRight); return nil`), and above the Esc check, insert:

```swift
        if keyCode == Self.rightBracketKeyCode {
            fire(\.onDesktopNext)
            return nil
        }
        if keyCode == Self.leftBracketKeyCode {
            fire(\.onDesktopPrev)
            return nil
        }
```

Both bracket keys are swallowed (return `nil`). They only fire while the switcher state machine is active (i.e. user is holding Cmd after pressing Cmd+Tab), so no need to check `cmdHeld` separately — the active branch is only reached with Cmd held.

- [ ] **Step 3: Build to verify the tap still compiles**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 40 tests pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/Nook/Switcher/SwitcherHotkey.swift
git commit -m "$(cat <<'EOF'
feat: handle Cmd+[ / Cmd+] in switcher hotkey for desktop nav

Adds left/right bracket keycodes (33 / 30 on US layout) and the matching
onDesktopPrev / onDesktopNext callbacks. Both keys are swallowed while the
switcher is active. No effect outside the active state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Extend `SwitcherView` + wire `onClickDesktop` in `showWindow`

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherView.swift`
- Modify: `Sources/Nook/Switcher/SwitcherController.swift` (only the `showWindow` callback list)

No new unit tests: the project does not unit-test SwiftUI views. End-to-end verification in Task 8.

- [ ] **Step 1: Replace `SwitcherView.swift` with the chip-row version**

Open `Sources/Nook/Switcher/SwitcherView.swift`. Replace the entire file contents with:

```swift
import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onHoverWindow: (Int) -> Void
    let onClickWindow: (Int) -> Void
    let onBeginRename: () -> Void
    let onFinishRename: (Bool, String) -> Void
    let onClickDesktop: (Int) -> Void

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
                desktopRow

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
    private var desktopRow: some View {
        if model.isRenaming {
            renameField
        } else if model.desktops.count >= 2 {
            HStack(spacing: 10) {
                ForEach(Array(model.desktops.enumerated()), id: \.element.id) { idx, desktop in
                    desktopChip(desktop, onClick: { onClickDesktop(idx) })
                    if desktop.isCurrent {
                        Button("Rename") { onBeginRename() }
                            .buttonStyle(.bordered)
                    }
                }
            }
        } else {
            legacyNameRow
        }
    }

    @ViewBuilder
    private var legacyNameRow: some View {
        HStack(spacing: 10) {
            Text(model.desktopName)
                .font(.headline)
                .foregroundStyle(.white)
            Button("Rename") { onBeginRename() }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var renameField: some View {
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
    }

    @ViewBuilder
    private func desktopChip(_ desktop: DesktopVM, onClick: @escaping () -> Void) -> some View {
        Text(desktop.label)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(desktop.isCurrent ? Color.white.opacity(0.25) : Color.clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onHover { hovering in
                // The current chip stays at its highlight; non-current chips
                // get no hover affordance to keep the row visually calm
                // (window thumbs already provide hover feedback elsewhere).
                _ = hovering
            }
            .onTapGesture { if !desktop.isCurrent { onClick() } }
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

    private func numberedTitle(_ win: SwitcherWindow, index: Int) -> String {
        let base = win.title.isEmpty ? "Untitled" : win.title
        return index < 9 ? "\(index + 1)  \(base)" : base
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
            Text(numberedTitle(win, index: index))
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

- [ ] **Step 2: Wire the new closure in `SwitcherController.showWindow`**

Open `Sources/Nook/Switcher/SwitcherController.swift`. Inside `showWindow(model:)`, replace the `SwitcherView(...)` literal with:

```swift
        let root = SwitcherView(
            model: model,
            onHoverWindow: { [weak self] index in self?.hoverWindow(index) },
            onClickWindow: { [weak self] index in self?.clickWindow(index) },
            onBeginRename: { [weak self] in self?.beginRename() },
            onFinishRename: { [weak self] save, name in self?.finishRename(save: save, newName: name) },
            onClickDesktop: { [weak self] index in self?.clickDesktop(index) }
        )
```

- [ ] **Step 3: Build to verify the view + controller still compile**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 40 tests pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/Nook/Switcher/SwitcherView.swift Sources/Nook/Switcher/SwitcherController.swift
git commit -m "$(cat <<'EOF'
feat: chip row in SwitcherView with rename on current and legacy fallback

Adds a horizontal row of clickable desktop chips above the app icon row.
The current chip is highlighted and the Rename button renders immediately
to its right (same semantics as before). When fewer than two desktops are
available, the row falls back to the existing single name + Rename layout
(no behavior regression for single-desktop users). The rename TextField
path is unchanged. Plumbs the new onClickDesktop closure from
SwitcherController.showWindow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Wire `AppDelegate` + end-to-end verification

**Files:**
- Modify: `Sources/Nook/App/AppDelegate.swift`

- [ ] **Step 1: Wire the two new hotkey callbacks**

Open `Sources/Nook/App/AppDelegate.swift`. Inside `startSwitcher()`, immediately after the line `hotkey.onWindowNumber = { [weak self] number in self?.switcher.selectWindow(number: number) }`, add:

```swift
        hotkey.onDesktopPrev = { [weak self] in self?.switcher.desktopPrev() }
        hotkey.onDesktopNext = { [weak self] in self?.switcher.desktopNext() }
```

- [ ] **Step 2: Build the Debug configuration**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full test suite**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 40 tests pass.

- [ ] **Step 4: Build, install and launch a fresh notarized Release**

The app is currently running from `/Applications/Nook.app`. To smoke the new feature, quit it, rebuild Release, install the build into `/Applications`, and relaunch:

```sh
killall Nook 2>/dev/null || true
rm -rf build/dev
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Release \
    -derivedDataPath build/dev -destination 'platform=macOS' \
    CODE_SIGN_STYLE=Manual 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
rm -rf /Applications/Nook.app
ditto build/dev/Build/Products/Release/Nook.app /Applications/Nook.app
open /Applications/Nook.app
```

Expected: `** BUILD SUCCEEDED **` and the new Nook icon appears in the menu bar within a few seconds.

The Release build keeps the existing Hardened Runtime, Developer-ID signing, secure timestamp, and absence of `get-task-allow`, so existing TCC grants (Accessibility + Screen Recording) for `com.metalbreeze.Nook` are preserved — no re-prompt needed.

- [ ] **Step 5: Manual end-to-end verification checklist**

Run through each of these and note PASS/FAIL:

1. With **two or more desktops** on the current screen, press **⌘Tab** and **hold ⌘**. The chip row appears at the top of the overlay; the current desktop's chip is highlighted; chips are numbered `1 …`, `2 …`, etc. in Mission Control order. **Rename** is rendered next to the highlighted chip.
2. **Click a non-current chip** with the mouse. The overlay closes and macOS switches to that desktop. The menu-bar title (which already tracks the active Space) updates to the new desktop's name.
3. With the overlay open, press **⌘+]** once. The next desktop in the row becomes active and the overlay closes; wrap-around works from the last chip to the first.
4. With the overlay open, press **⌘+[** once. The previous desktop becomes active; wrap-around works from the first chip to the last.
5. **Click the current chip** with the mouse. Nothing happens — overlay stays open.
6. With the overlay open, press the **Rename** button. The chip row is replaced with the rename TextField; ⌘+[ and ⌘+] do nothing while renaming.
7. With **a single desktop** on the current screen, press ⌘Tab. The chip row is hidden and the overlay shows the original single name + Rename row (existing behavior, unchanged).
8. Existing flows still work: Tab cycles apps, ←/→ cycles the highlighted app's windows, 1–9 jumps to a numbered window, Esc cancels, ⌘ release activates the selected window/app.

- [ ] **Step 6: Commit**

```sh
git add Sources/Nook/App/AppDelegate.swift
git commit -m "$(cat <<'EOF'
feat: wire Cmd+[/Cmd+] in AppDelegate to drive desktop nav

Connects SwitcherHotkey.onDesktopPrev/onDesktopNext to
SwitcherController.desktopPrev/desktopNext. Completes the feature: chip
row + mouse click + bracket keys + private-CGS switch all work end to end.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Plan self-review

**1. Spec coverage** — every spec section maps to a task:

| Spec section | Implemented in |
|---|---|
| Behavior: chip row at top, labels `<index> <name>`, current highlighted, Rename next to current | Tasks 1, 5, 7 |
| Mouse click switches | Tasks 2, 5, 7 |
| Cmd+] / Cmd+[ switches | Tasks 5, 6, 8 |
| Rename-mode gates bracket keys & chip clicks | Tasks 5, 7 |
| Only current screen's user-space Spaces | Task 3 |
| Single-desktop fallback to legacy row | Task 7 |
| New private CGS symbols | Task 2 |
| `SpaceSwitcher.switchTo` (CGS direct switch, no-op if current) | Task 2 |
| Testing: unit (DesktopLabel) + manual end-to-end | Task 1 + Task 8 |

**2. Placeholder scan** — no `TBD`/`TODO`/"handle edge cases" instructions; every code block is complete; every command has a concrete expected output.

**3. Type consistency** — `DesktopEntry` (Task 3) → `DesktopVM` (Task 4) → consumed in Task 5 (`open()`) → rendered in Task 7 (`desktopChip`); `clickDesktop` / `desktopPrev` / `desktopNext` defined in Task 5, called from Task 7 (view) and Task 8 (delegate via hotkey). `onClickDesktop` closure: declared in Task 7 view, supplied in Task 7 controller wiring. `onDesktopPrev` / `onDesktopNext`: declared in Task 6 hotkey, wired in Task 8 delegate. Bracket keycodes `33` / `30` referenced in Task 6 only. All consistent.
