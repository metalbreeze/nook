# Current Desktop Name in the Menu Bar

**Date:** 2026-05-27
**Status:** Approved design, pending implementation plan
**Project:** MyDefineShortcut (macOS menu-bar agent)

## Summary

Show the current desktop's user-assigned name next to the menu-bar icon, but only for desktops
that have actually been named (un-named desktops show the icon alone). A menu-item toggle
(default ON) controls whether names are shown at all. The title updates live on Space switch and
when the current desktop is renamed.

Builds on the existing desktop-naming feature (`DesktopNameStore`, `CurrentSpace`).

## Behavior

- The status-item button shows the current desktop's **custom name** next to the icon when:
  the toggle is ON **and** the current Space has a stored (custom) name. Otherwise the button shows
  the **icon only** (empty title).
- Un-named desktops (still the default "Desktop") show icon only — even with the toggle ON.
- **Toggle:** a status-menu item "Show Desktop Name in Menu Bar" with a checkmark, **default ON**.
  Toggling it flips the preference (persisted), updates the menu bar immediately.
- **Live updates:** the title refreshes when the active Space changes
  (`NSWorkspace.activeSpaceDidChangeNotification`) and when the current desktop is renamed.

Title rule: `title = (showName && storedName != nil) ? storedName : ""` (empty → icon only).

## Non-Goals (v1)

- No truncation/width cap on long names (the status item is variable-length; the name shows as-is).
- No per-desktop "show/hide" — the toggle is global.
- Same private-CGS Space-identity caveats as the naming feature (names may reset on reboot).

## Permissions

None new.

## Architecture

### 1. DesktopNameStore (extend)
- Add `func storedName(for spaceID: UInt64) -> String?` — returns the raw stored name, or `nil` when
  the Space has no entry.
- Refactor `name(for:)` to `storedName(for:) ?? Self.defaultName` (behavior unchanged for existing
  callers). `setName` unchanged.

### 2. MenuBarPreferences (new, testable)
- UserDefaults-backed (injectable for tests), key e.g. `"showDesktopNameInMenuBar"`.
- `var showDesktopName: Bool { get set }` — **defaults to true** when unset
  (`object(forKey:) == nil ? true : bool(forKey:)`); the setter persists.

### 3. SwitcherController (extend)
- Add `var onDesktopRenamed: (() -> Void)?`. In `finishRename(save:newName:)`, when `save` is true
  (after `nameStore.setName(...)`), call `onDesktopRenamed?()`.

### 4. AppDelegate (extend)
- Own `private let nameStore = DesktopNameStore()` and `private var menuBarPrefs = MenuBarPreferences()`.
- `updateMenuBarTitle()`:
  ```swift
  let name: String? = menuBarPrefs.showDesktopName
      ? CurrentSpace.id().flatMap { nameStore.storedName(for: $0) }
      : nil
  statusItem?.button?.title = name ?? ""
  ```
  Set `statusItem?.button?.imagePosition = .imageLeading` when creating the button.
- In `setupMenuBar()`: add a menu item "Show Desktop Name in Menu Bar" targeting `self`, action
  `toggleDesktopName`, with `state = menuBarPrefs.showDesktopName ? .on : .off`.
- `@objc func toggleDesktopName(_ sender: NSMenuItem)`: `menuBarPrefs.showDesktopName.toggle()`;
  `sender.state = menuBarPrefs.showDesktopName ? .on : .off`; `updateMenuBarTitle()`.
- In `applicationDidFinishLaunching`: after `setupMenuBar()`, call `updateMenuBarTitle()`, register a
  `NSWorkspace.shared.notificationCenter` observer for `activeSpaceDidChangeNotification` →
  `updateMenuBarTitle()`.
- In `startSwitcher()`: set `switcher.onDesktopRenamed = { [weak self] in self?.updateMenuBarTitle() }`.

## Data Flow

```
launch -> setupMenuBar (adds toggle item) -> updateMenuBarTitle()
          + observe activeSpaceDidChangeNotification
Space change -> updateMenuBarTitle(): title = (showName && storedName(curSpace) != nil) ? name : ""
rename saved -> SwitcherController.finishRename -> onDesktopRenamed -> updateMenuBarTitle()
toggle clicked -> menuBarPrefs.showDesktopName flips -> item.state updated -> updateMenuBarTitle()
```

## Testing Strategy

- **Unit-testable (TDD):**
  - `DesktopNameStore.storedName(for:)`: nil when unset; returns the stored value when set; and
    `name(for:)` still returns the default when unset (regression).
  - `MenuBarPreferences` (injected throwaway suite): defaults to true; set false then get false;
    set true then get true.
- **Manual / integration:**
  - Name a desktop → its name appears by the menu-bar icon; an un-named desktop shows icon only.
  - Switch desktops → the menu-bar name updates to the active desktop's name (or icon only).
  - Rename the current desktop → menu bar updates immediately.
  - Toggle off → icon only everywhere; toggle on → names reappear; the choice persists across relaunch.

## Open Risks

1. Private-CGS Space identity (unchanged from the naming feature) — names may reset on reboot.
2. `activeSpaceDidChangeNotification` timing — the menu-bar title is cosmetic, so brief staleness
   right at a Space transition is harmless (unlike the Ctrl+Down snapshot, no window action depends
   on it).
