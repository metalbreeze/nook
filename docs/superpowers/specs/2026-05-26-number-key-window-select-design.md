# Number-Key Window Selection in the Cmd+Tab Switcher

**Date:** 2026-05-26
**Status:** Approved design, pending implementation plan
**Project:** MyDefineShortcut (macOS menu-bar agent)

## Summary

While the Cmd+Tab switcher is open (Cmd held, Tab released), pressing a number key **1-9**
immediately raises the highlighted app's Nth current-desktop window and closes the switcher —
a one-keystroke jump, in addition to the existing arrow-key/mouse window selection. Each window's
title label shows its number (e.g. "1  Inbox").

Small extension to the existing Cmd+Tab window-preview switcher.

## Behavior

- With the switcher open (Cmd held): pressing **1-9** raises that app's window at index
  `number - 1` and closes the switcher (identical to clicking that thumbnail).
- Out-of-range numbers (e.g. "5" when the app has 3 current-desktop windows) do nothing; the
  switcher stays open.
- Numbers fire only while the switcher is active (Cmd held) and not while renaming.
- The window title label shows the number prefix for the first 9 windows: `"<n>  <title>"`
  (windows past 9 show the title with no number).

## Non-Goals (v1)

- Only digits 1-9 (no 0, no two-digit selection); windows past the 9th aren't number-selectable.
- Standard ANSI number-row keycodes only; non-standard keyboard layouts are out of scope.

## Permissions

None new. Reuses the existing window-raise (Accessibility) + close path.

## Architecture

### 1. SwitcherHotkey (extend)
- Add `var onWindowNumber: ((Int) -> Void)?`.
- Add a digit-keycode → number map (standard top-row keys):
  `[18:1, 19:2, 20:3, 21:4, 23:5, 22:6, 26:7, 28:8, 25:9]`.
- In the active branch of `handle`, if the keyCode maps to a digit, `fire(onWindowNumber(n))` and
  return `nil` (swallow). Placed alongside the existing Tab/arrow/Esc handling.

### 2. SwitcherController (extend)
- `func selectWindow(number: Int)`: guard `let model, !model.isRenaming`; compute
  `index = number - 1`; guard `model.windows.indices.contains(index)` (else no-op); then
  `let win = model.windows[index]; close(); WindowActivator.activate(win.info, pid: win.pid)`
  (the same raise+close path as `clickWindow`).

### 3. AppDelegate (extend)
- In `startSwitcher()`, wire `hotkey.onWindowNumber = { [weak self] n in self?.switcher.selectWindow(number: n) }`.

### 4. SwitcherView (extend)
- In `windowThumb(_:selected:index:)`, prefix the title with the number for `index < 9`:
  the label text becomes `index < 9 ? "\(index + 1)  \(title)" : title`, where `title` is the
  existing `win.title.isEmpty ? "Untitled" : win.title`.

## Data Flow

```
(switcher open, Cmd held) digit keyDown
  -> SwitcherHotkey: map keyCode -> n; fire onWindowNumber(n); swallow
  -> AppDelegate closure -> SwitcherController.selectWindow(number: n)
  -> guard !isRenaming; index = n-1; if in range: WindowActivator.activate(windows[index]) + close
     else: no-op (switcher stays open)
```

## Testing Strategy

- **Manual / integration:** with a multi-window app highlighted, the title labels read "1 …",
  "2 …"; pressing 2 raises the 2nd window and closes; pressing an out-of-range number does nothing;
  numbers don't fire while renaming; arrow/hover/click selection still works.
- (The raise+close path itself is already exercised by `clickWindow`; the digit→number mapping is a
  static lookup that can get a tiny unit check if it earns its keep, but is otherwise covered manually.)

## Open Risks

1. **Keyboard-layout dependence** of the digit keycodes (standard ANSI number row assumed).
2. Reuses the existing Cmd+Tab interception (unchanged); no new risk surface beyond the digit keys.
