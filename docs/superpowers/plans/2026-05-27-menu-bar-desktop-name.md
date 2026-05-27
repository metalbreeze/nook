# Current Desktop Name in the Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the current desktop's custom name next to the menu-bar icon (icon-only when un-named), with a default-on toggle to hide it, updating live on Space switch and rename.

**Architecture:** `DesktopNameStore` gains `storedName(for:)` (nil when un-named); a new `MenuBarPreferences` persists the toggle; `AppDelegate` updates the status-item title from the active Space's stored name, observes `activeSpaceDidChangeNotification`, adds the toggle menu item, and is notified of renames via a new `SwitcherController.onDesktopRenamed` callback.

**Tech Stack:** Swift 5 language mode (Swift 6.3 compiler), AppKit + SwiftUI, CoreGraphics. Project via XcodeGen, Developer ID signing. Tests in XCTest.

---

## File Structure

```
Sources/MyDefineShortcut/Switcher/DesktopNameStore.swift     # MODIFY: add storedName(for:)
Sources/MyDefineShortcut/Switcher/MenuBarPreferences.swift   # NEW (testable): show-name toggle
Sources/MyDefineShortcut/Switcher/SwitcherController.swift   # MODIFY: onDesktopRenamed callback
Sources/MyDefineShortcut/App/AppDelegate.swift               # MODIFY: title + toggle + observer + wiring
Tests/MyDefineShortcutTests/DesktopNameStoreTests.swift      # MODIFY: storedName tests
Tests/MyDefineShortcutTests/MenuBarPreferencesTests.swift    # NEW
```

Reuses `CurrentSpace` unchanged. No new permissions.

**Standard commands:**
- Build: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
- Test: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`

---

## Task 1: DesktopNameStore.storedName (TDD)

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/DesktopNameStore.swift`
- Test: `Tests/MyDefineShortcutTests/DesktopNameStoreTests.swift`

- [ ] **Step 1: Add the failing tests**

Read `DesktopNameStoreTests.swift`. Add these two test methods to the class:
```swift
    func test_storedName_nilWhenUnset() {
        let store = DesktopNameStore(defaults: defaults)
        XCTAssertNil(store.storedName(for: 1))
    }

    func test_storedName_returnsValueWhenSet() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("Work", for: 1)
        XCTAssertEqual(store.storedName(for: 1), "Work")
    }
```

- [ ] **Step 2: Run tests to verify red**

Run: `xcodegen generate && xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `value of type 'DesktopNameStore' has no member 'storedName'`.

- [ ] **Step 3: Add `storedName(for:)` and refactor `name(for:)`**

In `DesktopNameStore.swift`, replace the existing `name(for:)` method with these two methods (keep `setName` and the rest unchanged):
```swift
    func name(for spaceID: UInt64) -> String {
        storedName(for: spaceID) ?? Self.defaultName
    }

    func storedName(for spaceID: UInt64) -> String? {
        let map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return map[String(spaceID)]
    }
```

- [ ] **Step 4: Run tests to verify green**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`; the 2 new tests plus the existing `DesktopNameStore` tests (including `test_defaultWhenAbsent`) pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/DesktopNameStore.swift Tests/MyDefineShortcutTests/DesktopNameStoreTests.swift
git commit -m "feat: add DesktopNameStore.storedName (nil when un-named)"
```

---

## Task 2: MenuBarPreferences (TDD)

**Files:**
- Create: `Sources/MyDefineShortcut/Switcher/MenuBarPreferences.swift`
- Test: `Tests/MyDefineShortcutTests/MenuBarPreferencesTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MyDefineShortcut

final class MenuBarPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.menuBarPrefs"

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

    func test_defaultsToTrue() {
        let prefs = MenuBarPreferences(defaults: defaults)
        XCTAssertTrue(prefs.showDesktopName)
    }

    func test_setFalseThenGet() {
        let prefs = MenuBarPreferences(defaults: defaults)
        prefs.showDesktopName = false
        XCTAssertFalse(prefs.showDesktopName)
    }

    func test_setTrueAfterFalse() {
        let prefs = MenuBarPreferences(defaults: defaults)
        prefs.showDesktopName = false
        prefs.showDesktopName = true
        XCTAssertTrue(prefs.showDesktopName)
    }
}
```

- [ ] **Step 2: Run tests to verify red**

Run: `xcodegen generate && xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `cannot find 'MenuBarPreferences' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Persists whether the menu-bar icon shows the current desktop's name.
/// Defaults to true when unset.
struct MenuBarPreferences {
    private let defaults: UserDefaults
    private let key = "showDesktopNameInMenuBar"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showDesktopName: Bool {
        get { defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key) }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}
```

- [ ] **Step 4: Run tests to verify green**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`, 3 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/MenuBarPreferences.swift Tests/MyDefineShortcutTests/MenuBarPreferencesTests.swift
git commit -m "feat: add MenuBarPreferences (show-desktop-name toggle, default on)"
```

---

## Task 3: SwitcherController.onDesktopRenamed callback

**Files:**
- Modify: `Sources/MyDefineShortcut/Switcher/SwitcherController.swift`

- [ ] **Step 1: Add the callback property**

Read the file. Next to the other stored properties (`window`/`model`/`generation`/`nameStore`/`spaceID`), add:
```swift
    var onDesktopRenamed: (() -> Void)?
```

- [ ] **Step 2: Fire it from `finishRename`**

Replace the existing `finishRename(save:newName:)` with:
```swift
    func finishRename(save: Bool, newName: String) {
        if save, let spaceID {
            nameStore.setName(newName, for: spaceID)
            onDesktopRenamed?()
        }
        close()
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Switcher/SwitcherController.swift
git commit -m "feat: notify on desktop rename via onDesktopRenamed callback"
```

---

## Task 4: AppDelegate — menu-bar title, toggle, observer, wiring

**Files:**
- Modify: `Sources/MyDefineShortcut/App/AppDelegate.swift`

- [ ] **Step 1: Add two stored properties**

Read the file. Alongside the existing properties (`statusItem`, `hotkeyTap`, `overlay`, `switcher`, `switcherHotkey`), add:
```swift
    private let nameStore = DesktopNameStore()
    private let menuBarPrefs = MenuBarPreferences()
```

- [ ] **Step 2: Show the icon to the left of the title + add the toggle menu item**

In `setupMenuBar()`, after the line that sets `item.button?.image = ...`, add:
```swift
        item.button?.imagePosition = .imageLeading
```
Then add a toggle menu item. After the existing "Trigger Snapshot" item and its following `.separator()`, insert:
```swift
        let nameToggle = NSMenuItem(title: "Show Desktop Name in Menu Bar",
                                    action: #selector(toggleDesktopName(_:)),
                                    keyEquivalent: "")
        nameToggle.state = menuBarPrefs.showDesktopName ? .on : .off
        menu.addItem(nameToggle)
        menu.addItem(.separator())
```
(Place this block so it appears before the "Accessibility Settings…" item. The existing `for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) { menuItem.target = self }` loop will set its target.)

- [ ] **Step 3: Add the title-update + toggle action methods**

Add these methods to the class (e.g. near the other `@objc` menu actions):
```swift
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
```

- [ ] **Step 4: Observe Space changes, set the initial title, and wire the rename callback**

In `applicationDidFinishLaunching(_:)`, after the existing `startSwitcher()` call, add:
```swift
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        updateMenuBarTitle()
```
In `startSwitcher()`, after the existing callback wiring, add:
```swift
        switcher.onDesktopRenamed = { [weak self] in self?.updateMenuBarTitle() }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`. Report ALL warnings verbatim.

- [ ] **Step 6: Confirm tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Sources/MyDefineShortcut/App/AppDelegate.swift
git commit -m "feat: show current desktop name in menu bar with toggle"
```

---

## Task 5: End-to-end manual verification

**Files:** none (verification + final launch).

- [ ] **Step 1: Build and launch**

```bash
xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build
open ./build/Build/Products/Debug/MyDefineShortcut.app
```

- [ ] **Step 2: Verify name display**

On a desktop you haven't named, the menu bar shows **icon only**. Name the current desktop via Cmd+Tab → Rename → its name appears next to the menu-bar icon immediately.

- [ ] **Step 3: Verify Space-switch updates**

Name two different desktops. Switch between them → the menu-bar name updates to the active desktop's name; an un-named desktop shows icon only.

- [ ] **Step 4: Verify the toggle**

Open the menu-bar menu → "Show Desktop Name in Menu Bar" has a checkmark (on). Click it → the name disappears (icon only) and the checkmark clears. Click again → the name reappears. Quit and relaunch → the toggle state persisted.

- [ ] **Step 5: Verify coexistence**

Cmd+Tab (cycling, previews, number keys), Ctrl+Down, and rename all still work.

- [ ] **Step 6: Final commit (if any tweaks were needed)**

```bash
git add -A
git commit -m "chore: finalize menu-bar desktop name after manual verification"
```

---

## Spec Coverage Check

- Show custom name next to icon; icon-only when un-named → Task 1 (storedName nil), Task 4 (updateMenuBarTitle), Task 5 step 2.
- Default-on toggle in the status menu → Task 2 (MenuBarPreferences default true), Task 4 (menu item + toggleDesktopName), Task 5 step 4.
- Live update on Space switch → Task 4 (activeSpaceDidChange observer), Task 5 step 3.
- Live update on rename → Task 3 (onDesktopRenamed), Task 4 (wire to updateMenuBarTitle), Task 5 step 2.
- Toggle persists → Task 2 (UserDefaults), Task 5 step 4.
- Icon left of title → Task 4 (imagePosition = .imageLeading).
- No new permissions; reuses CurrentSpace/DesktopNameStore → Tasks 1/4.
```

