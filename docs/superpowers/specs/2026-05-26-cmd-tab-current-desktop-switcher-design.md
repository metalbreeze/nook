# Cmd+Tab Current-Desktop App Switcher

**Date:** 2026-05-26
**Status:** Approved design, pending implementation plan
**Project:** MyDefineShortcut (macOS menu-bar agent)

## Summary

A second feature for the MyDefineShortcut menu-bar agent: intercept the global **Cmd+Tab** shortcut and replace the system app switcher with a custom one that lists **only apps with at least one window on the current desktop (Space)**, instead of all running apps across all desktops. Interaction mirrors native Cmd+Tab: hold Cmd, tap Tab to advance (Shift+Tab to reverse), release Cmd to switch.

This coexists with the existing Ctrl+Down window-snapshot feature in the same app.

## Goals

- Intercept the global Cmd+Tab shortcut and suppress the system app switcher.
- Show a horizontal icon strip of apps that have ≥1 normal window on the **current Space only**.
- Native-style interaction: hold Cmd; Tab advances the highlight; Shift+Tab reverses; Esc cancels; releasing Cmd switches to the highlighted app.
- Order apps by window z-order with the **current app highlighted first (index 0)**; the triggering Tab opens at index 0, so a quick Cmd+Tab tap-and-release stays on the current app (no switch). Subsequent Tabs move the highlight.
- Switch at the **app** level (activate the app, bringing its current-desktop window forward).

## Non-Goals (v1)

- No MRU (most-recently-used) ordering or previous-app pre-selection.
- No per-window switching (app-level only).
- No multi-monitor fan-out (single display, consistent with the existing feature).
- No configurable hotkey (fixed to Cmd+Tab).
- Minimized/hidden windows are not "on the current desktop" and are excluded.

## Environment

- macOS 26.3.1 (Tahoe), Apple Silicon (arm64), Swift 6.3.2 / Xcode 26.5.
- Built into the existing `MyDefineShortcut` app target, signed with the Developer ID identity (stable TCC).

## Permissions

- **Accessibility** — required for the keyboard event tap (already granted for the Ctrl+Down feature).
- **Screen Recording is NOT required.** App icons come from `NSRunningApplication`; the window→app mapping uses `CGWindowList` window numbers + `kCGWindowOwnerPID`, which are available without Screen Recording.

## Approach (and rejected alternatives)

A **CGEventTap** watching both `keyDown` and `flagsChanged` events.

- Rejected: Carbon `RegisterEventHotKey` — delivers key-press events but not the modifier-release (Cmd up) needed to commit the native hold-and-cycle interaction.
- Rejected: `NSEvent.addGlobalMonitorForEvents` — can observe but cannot swallow events, so it can't suppress the system switcher.

**Risk:** Cmd+Tab is among the most reserved system shortcuts. A session-level event tap can intercept and swallow it (as AltTab/Contexts do), but this is the highest-risk interception in the project. If suppression proves unreliable in testing, escalate rather than layering on fixes; there is no clean public API to disable the system Cmd+Tab.

## Architecture

### 1. DesktopAppList (pure logic — unit-tested)
- Input: an ordered list of raw window entries `{ ownerPID, layer, isOnScreen }` in front-to-back z-order (as returned by `CGWindowList`), plus the current frontmost PID.
- Output: an ordered, de-duplicated list of app PIDs that have ≥1 normal (layer 0), on-screen window, with the current app's PID first and the rest following z-order.
- No system calls; fully testable.

### 2. SwitcherIndex (pure logic — unit-tested)
- Wrap-around cycling over `count` items: `advance(from:)` → `(i+1) % count`; `reverse(from:)` → `(i-1+count) % count`.
- Testable.

### 3. DesktopAppEnumerator (system adapter)
- Calls `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`.
- Maps each entry to `{ ownerPID, layer, isOnScreen=true }` preserving z-order, plus the frontmost PID from `NSWorkspace`.
- Feeds `DesktopAppList`, then resolves each PID to `NSRunningApplication` to produce `SwitcherApp { pid, name, icon }`.

### 4. SwitcherHotkey (system — CGEventTap)
- Session-level `.defaultTap` watching `keyDown` and `flagsChanged`.
- **Idle:** on `keyDown` Tab (keycode 48) while Cmd present → notify controller to open; swallow.
- **Active:** `Tab` → advance; `Shift+Tab` → reverse; `Esc` (53) → cancel; `flagsChanged` dropping Cmd → commit. Swallow Tab/Shift+Tab/Esc and the Cmd-release; pass other events.
- Re-enables itself on `.tapDisabledByTimeout`/`.tapDisabledByUserInput`.
- Requires Accessibility.

### 5. SwitcherController (@MainActor)
- Owns the overlay window and state (`apps: [SwitcherApp]`, `selectedIndex: Int`).
- `open()` → enumerate apps; if non-empty, show overlay with `selectedIndex = 0`.
- `advance()` / `reverse()` → update `selectedIndex` via `SwitcherIndex`, refresh view.
- `commit()` → `NSRunningApplication(processIdentifier: apps[selectedIndex].pid)?.activate()`, close.
- `cancel()` → close without switching.

### 6. SwitcherView (SwiftUI)
- Horizontal centered icon strip; highlighted icon enlarged/outlined with the app name below; dimmed/blurred backdrop.
- Hosted in the existing `OverlayWindow` (keyable borderless) pattern.

### 7. AppDelegate wiring
- Instantiate and start `SwitcherHotkey` alongside the existing Ctrl+Down `HotkeyTap`.
- Add a menu item (e.g. status reflecting the switcher) — minimal.

## Data Flow

```
Cmd held + Tab keyDown
  -> SwitcherHotkey (idle): swallow, tell SwitcherController.open()
  -> DesktopAppEnumerator: CGWindowList onScreen entries -> DesktopAppList
       -> [SwitcherApp] (current app first, z-order), resolve icons
  -> SwitcherController shows SwitcherView, selectedIndex = 0
  -> (Cmd held) Tab/Shift+Tab -> SwitcherIndex advance/reverse -> refresh
  -> Esc -> cancel (close)
  -> Cmd released (flagsChanged) -> commit: activate apps[selectedIndex], close
```

## Testing Strategy

- **Unit-testable (TDD):**
  - `DesktopAppList`: given sample z-ordered window entries (mixed PIDs, layers, on-screen flags) + a frontmost PID, assert correct de-duplicated ordered PID list with current app first and non-app/off-screen/non-zero-layer entries excluded.
  - `SwitcherIndex`: advance/reverse wrap-around, including single-item and boundary cases.
- **Manual / integration (requires a real session):**
  - Cmd+Tab suppresses the system switcher and shows the custom strip.
  - Only current-desktop apps appear; an app whose windows are all on another Space is excluded.
  - Tab/Shift+Tab cycle correctly; Esc cancels; releasing Cmd switches to the highlighted app; quick tap-and-release stays on the current app.

## Open Risks

1. **Cmd+Tab suppression reliability** (see Approach) — highest-risk interception; escalate if unreliable.
2. **Event-tap state correctness** for the hold-Cmd / multi-Tab / release sequence (the stateful core).
3. **Current-Space accuracy** depends on `CGWindowList(.optionOnScreenOnly)`, the same mechanism validated in the Ctrl+Down feature.
