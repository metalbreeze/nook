# Number-Key Window Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While the Cmd+Tab switcher is open (Cmd held), pressing 1-9 immediately raises the highlighted app's Nth current-desktop window and closes the switcher; numbers are shown in the window title labels.

**Architecture:** The event tap maps digit keycodes to a number and fires a new `onWindowNumber` callback (swallowing the key); the controller's `selectWindow(number:)` reuses the existing raise+close path (guarded by `!isRenaming`); the view prefixes the number to each window's title.

**Tech Stack:** Swift 5 language mode (Swift 6.3 compiler), AppKit + SwiftUI, CoreGraphics event tap. Project via XcodeGen, Developer ID signing. Tests in XCTest.

---

## File Structure (all modifications)

```
Sources/MyDefineShortcut/Switcher/SwitcherHotkey.swift     # MODIFY: onWindowNumber + digit map + handling
Sources/MyDefineShortcut/Switcher/SwitcherController.swift # MODIFY: selectWindow(number:)
Sources/MyDefineShortcut/App/AppDelegate.swift             # MODIFY: wire onWindowNumber
Sources/MyDefineShortcut/Switcher/SwitcherView.swift       # MODIFY: number prefix in window title
```

No new files; reuses `WindowActivator`, the model, and the overlay. No automated tests added (the raise+close path is already covered; the digit→number map is a static lookup verified manually) — the existing suite must stay green.

**Standard commands:**
- Build: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
- Test: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`

---

## Task 1: SwitcherHotkey — digit-key handling

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherHotkey.swift`

- [ ] **Step 1: Add the callback + digit keycode map**

Read the file. Alongside the existing callbacks (`onOpen`/`onAdvance`/`onReverse`/`onWindowLeft`/`onWindowRight`/`onCancel`/`onCommit`), add:
```swift
    var onWindowNumber: ((Int) -> Void)?
```
Alongside the existing static keycode constants (`tabKeyCode`, `escKeyCode`, `leftKeyCode`, `rightKeyCode`), add the standard ANSI number-row map:
```swift
    private static let digitKeyCodes: [Int64: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]
```

- [ ] **Step 2: Handle digits in the active branch**

In `handle(type:event:)`, inside the active section (after the `keyCode == Self.escKeyCode` block, before the final `return Unmanaged.passUnretained(event)`), add:
```swift
        if let number = Self.digitKeyCodes[keyCode] {
            let callback = onWindowNumber
            DispatchQueue.main.async { callback?(number) }
            return nil
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. Report warnings.

- [ ] **Step 4: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherHotkey.swift
git commit -m "feat: map number-row keys to window-number selection in hotkey"
```

---

## Task 2: SwitcherController.selectWindow + AppDelegate wiring

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherController.swift`
- Modify: `Sources/MyDefineShortcut/App/AppDelegate.swift`

- [ ] **Step 1: Add `selectWindow(number:)` to the controller**

Read `SwitcherController.swift`. Add this method (e.g. right after `clickWindow(_:)`):
```swift
    func selectWindow(number: Int) {
        guard let model, !model.isRenaming else { return }
        let index = number - 1
        guard model.windows.indices.contains(index) else { return }
        let win = model.windows[index]
        close()
        WindowActivator.activate(win.info, pid: win.pid)
    }
```

- [ ] **Step 2: Wire the callback in AppDelegate**

Read `AppDelegate.swift`. In `startSwitcher()`, after the existing `hotkey.onWindowRight = ...` line, add:
```swift
        hotkey.onWindowNumber = { [weak self] number in self?.switcher.selectWindow(number: number) }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. Report warnings.

- [ ] **Step 4: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherController.swift Sources/MyDefineShortcut/App/AppDelegate.swift
git commit -m "feat: select window by number in switcher controller"
```

---

## Task 3: SwitcherView — number prefix in window title

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherView.swift`

- [ ] **Step 1: Add a numbered-title helper and use it**

Read the file. Add this private helper (e.g. right before `windowThumb`):
```swift
    private func numberedTitle(_ win: SwitcherWindow, index: Int) -> String {
        let base = win.title.isEmpty ? "Untitled" : win.title
        return index < 9 ? "\(index + 1)  \(base)" : base
    }
```
Then, inside `windowThumb(_:selected:index:)`, replace the title Text line:
```swift
            Text(win.title.isEmpty ? "Untitled" : win.title)
```
with:
```swift
            Text(numberedTitle(win, index: index))
```
(The rest of `windowThumb` — frame, font, lineLimit, hover/tap — is unchanged.)

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. Report warnings.

- [ ] **Step 3: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherView.swift
git commit -m "feat: show window numbers in switcher title labels"
```

---

## Task 4: End-to-end manual verification

**Files:** none (verification + final launch).

- [ ] **Step 1: Build and launch**

```bash
xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build
open ./build/Build/Products/Debug/MyDefineShortcut.app
```

- [ ] **Step 2: Verify number labels + selection**

Hold Cmd, tap Tab, land on an app with 2+ current-desktop windows. The window title labels read `"1  …"`, `"2  …"`, etc. Press **2** → the 2nd window is raised and the switcher closes. Repeat with **1** and **3** → correct windows.

- [ ] **Step 3: Verify out-of-range + coexistence**

- With an app that has 3 windows, press **5** → nothing happens, switcher stays open.
- Arrow keys / hover / click window selection still work.
- Release Cmd without pressing a number → still activates the app (or the arrow/hover-selected window).
- Enter rename, type a name containing digits → the digits type into the field (number-select does NOT fire while renaming); Enter saves.
- Ctrl+Down still works.

- [ ] **Step 4: Final commit (if any tweaks were needed)**

```bash
git add -A
git commit -m "chore: finalize number-key window selection after manual verification"
```

---

## Spec Coverage Check

- Press 1-9 → immediately raise Nth window + close → Task 1 (digit map + fire), Task 2 (selectWindow raise+close), Task 4 step 2.
- Out-of-range numbers do nothing → Task 2 (`indices.contains` guard), Task 4 step 3.
- Numbers fire only while active and not renaming → Task 1 (active branch only), Task 2 (`!isRenaming` guard), Task 4 step 3.
- Number shown in title label (1-9) → Task 3 (numberedTitle), Task 4 step 2.
- Standard ANSI digit keycodes → Task 1 (digitKeyCodes map).
- Reuse raise+close path, no new permissions → Task 2 (WindowActivator + close).
```

