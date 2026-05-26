# Per-Desktop Naming in the Cmd+Tab Switcher

**Date:** 2026-05-26
**Status:** Approved design, pending implementation plan
**Project:** MyDefineShortcut (macOS menu-bar agent)

## Summary

Show a user-editable name for the current desktop (Space) at the top of the Cmd+Tab
switcher overlay, with a "rename" button. Each desktop can have its own name so the user
can tell desktops apart. Renaming detaches the overlay from the hold-Cmd interaction into a
focused text field (interaction "A"): Enter saves and closes, Esc cancels and closes.

Builds on the existing Cmd+Tab switcher.

## Interaction Model

- The switcher overlay shows the **desktop name at the top** (above the app strip), with a
  small **"rename" button** beside it. An unnamed desktop shows the default label **"Desktop"**.
- Clicking **rename** (while Cmd is held) → the controller enters `renameMode`, makes the overlay
  a key/active window, and shows a focused `TextField` prefilled with the current name.
- While `renameMode` is on, the hotkey's nav/commit callbacks (Tab/Shift+Tab/Left/Right/Cmd-release)
  are **no-ops** — so releasing Cmd neither switches nor closes the switcher.
- The user releases Cmd (to type); the event tap goes idle and passes all non-Cmd+Tab keys through
  to the focused field. **Enter** saves the name and closes; **Esc** discards and closes.

## Non-Goals (v1)

- No reliable persistence across reboots or desktop add/remove (see Identity caveat).
- No naming of desktops other than the current one (you name the desktop you're on).
- No multi-monitor per-display Space naming nuance beyond the active Space.
- No rename from the menu bar (rename happens in the switcher overlay only).

## Permissions

No new permissions. (Accessibility + Screen Recording already required by the switcher.)

## Identity & Persistence

- **Desktop identity:** macOS exposes no public, stable Space identifier. Use the private
  `CGSGetActiveSpace(CGSMainConnectionID())` (SkyLight/CoreGraphics), declared via `@_silgen_name`,
  to get the current Space's ID (`UInt64`).
- **Caveat (accepted):** this is a private/unsupported API; the Space ID can change on reboot or
  when desktops are added/removed, so names are **best-effort** and may reset. This is an inherent
  macOS limitation.
- **Persistence:** `DesktopNameStore` maps `spaceID → name` in `UserDefaults` (a `[String: String]`
  dict keyed by `String(spaceID)`). `name(for:)` returns the stored name, or the default `"Desktop"`
  when none is set.

## Architecture

### 1. CGSSpace (new, system)
- `@_silgen_name` declarations for the private symbols:
  ```swift
  typealias CGSConnectionID = UInt32
  typealias CGSSpaceID = UInt64
  @_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> CGSConnectionID
  @_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID
  ```
- `enum CurrentSpace { static func id() -> CGSSpaceID? }` — returns the active Space ID, or nil if
  the call yields 0 (defensive). Manual-verify (private API).

### 2. DesktopNameStore (new, testable)
- Backed by `UserDefaults` (default `.standard`, injectable for tests). Persists a `[String: String]`
  under a single key (e.g. `"desktopNames"`).
- `func name(for spaceID: CGSSpaceID) -> String` → stored name or `"Desktop"`.
- `func setName(_ name: String, for spaceID: CGSSpaceID)` → trims; if empty, removes the entry
  (reverts to default); otherwise stores.
- The default-resolution and set/get/remove logic is unit-tested with an injected `UserDefaults`
  (a throwaway suite).

### 3. SwitcherModel (extend)
- Add `@Published var desktopName: String` and `@Published var isRenaming: Bool` (default false).

### 4. SwitcherController (extend)
- On `open()`: resolve `desktopName = store.name(for: CurrentSpace.id())` (or "Desktop" if nil),
  set `isRenaming = false`. Hold the current `spaceID` for the session.
- `beginRename()` — set `model.isRenaming = true`, make the overlay window key + active so the
  TextField can focus.
- `finishRename(save: Bool, newName: String)` — if save, `store.setName(newName, for: spaceID)`;
  close the overlay either way.
- Guard: `advance()`, `reverse()`, `windowLeft()`, `windowRight()`, `commit()`, `clickWindow(_:)`,
  `hoverWindow(_:)` early-return when `model.isRenaming` is true.

### 5. SwitcherView (extend)
- Top row above the app strip: when not renaming, show `Text(model.desktopName)` + a "rename"
  button (calls `onBeginRename`); when `model.isRenaming`, show a focused `TextField` bound to a
  local edit string, prefilled with `desktopName`, with `onSubmit` → `onFinishRename(save: true, ...)`
  and `.onExitCommand` (Esc) → `onFinishRename(save: false, ...)`.
- New closures on `SwitcherView`: `onBeginRename: () -> Void`, `onFinishRename: (Bool, String) -> Void`.

## Data Flow

```
Cmd+Tab -> controller.open()
  -> spaceID = CurrentSpace.id(); model.desktopName = store.name(for: spaceID)  // or "Desktop"
  -> SwitcherView shows name + rename button at top
click "rename" (Cmd held) -> controller.beginRename(): model.isRenaming = true; window key+active
  -> nav/commit callbacks no-op while isRenaming
  -> user releases Cmd (tap goes idle); types into the focused TextField
  -> Enter -> onFinishRename(save: true, text) -> store.setName(text, for: spaceID); close
  -> Esc   -> onFinishRename(save: false, _)   -> close (discard)
```

## Testing Strategy

- **Unit-testable (TDD):** `DesktopNameStore` with an injected throwaway `UserDefaults` suite:
  default "Desktop" when absent; setName then name returns it; setName with empty/whitespace
  removes the entry (back to default).
- **Manual / integration (real session, private API):**
  - Switcher shows the current desktop's name (or "Desktop").
  - Click rename → field focuses; releasing Cmd doesn't close/switch; typing works; Enter saves &
    closes; reopening shows the new name; Esc discards.
  - A different desktop shows its own name (or default).
  - Name persists across app relaunch within the same login session.

## Open Risks

1. **Private CGS API** (`CGSGetActiveSpace`/`CGSMainConnectionID`) — may fail to link or break on OS
   updates; if `id()` returns nil, naming degrades gracefully (always shows/uses "Desktop", rename
   is a no-op-save). Names may reset on reboot / desktop changes.
2. **Rename-mode vs the live event tap** — mitigated by the Cmd-release→idle behavior plus
   `isRenaming` no-op guards. Fallback: add `suspend()`/`resume()` to `SwitcherHotkey` if the tap
   interferes with typing.
3. **Window focus during rename** — making the overlay key/active steals focus; not restored after
   close (acceptable for an explicit rename action).
