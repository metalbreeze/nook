# Parked Apps, Window-Count Badges, and Minimized Windows

**Date:** 2026-05-29
**Status:** Approved design, pending implementation plan
**Project:** Nook (macOS menu-bar agent)

## Summary

Refine how the Cmd+Tab switcher represents apps and windows that aren't
"normally visible" on a desktop:

- **Parked apps** (Cmd+H-hidden apps and apps whose only windows are ghost
  utility windows) appear in the app row as small, dimmed icons that Tab
  navigation skips; a mouse click activates them. Each parked icon carries a
  **window-count badge** in its upper-right corner.
- **Minimized windows** (Cmd+M) appear in the selected app's window row as a
  smaller, gray-backed thumbnail (they can't be screenshotted, so they render
  as a labeled placeholder); selecting one un-minimizes it.

This supersedes the interim "hidden apps shown dimmed at the tail" behavior
(commit `e8e40dc`) with a more complete window-aware model.

## Window classification (per window on the desktop's Space)

| Class | Test | Rendering in window row |
|---|---|---|
| **Real** | layer 0, frame ≥ 80×80, intersects display bounds, not minimized | normal thumbnail (200×130, live capture) |
| **Minimized** | AX `kAXMinimized == true` | smaller thumbnail (≈130×85), gray background, placeholder image |
| **Ghost** | neither real nor minimized (tiny/off-screen utility window) | not shown |

"Real" is exactly the current `WindowFilter.visibleWindows` bar (80×80 min,
on-screen, layer 0, within display bounds).

## App classification (per desktop)

| Class | Test | Rendering in app row | Tab |
|---|---|---|---|
| **Active** | has ≥1 real window OR ≥1 minimized window | normal icon (64), no badge | reachable |
| **Parked** | (0 real AND 0 minimized windows on the Space — i.e. ghost-only) OR app is Cmd+H-hidden | small icon (40), faint bg, 0.55 opacity, **count badge** top-right | **skipped** |

**Decision points locked during brainstorm:**
- An app whose only windows are **minimized** is **Active** (so the user can
  Tab to it and see / restore the gray minimized thumbnail). Only ghost-only
  apps and Cmd+H apps are Parked.
- **Count badge** value: the number of the app's windows.
  - Ghost-only parked app → **0**.
  - Cmd+H parked app → the count of its (hidden) real-sized windows (counted
    from `CGWindowList` by owner PID, size ≥ 80×80, regardless of Space —
    hidden-app windows do not reliably report a Space).
- Parked-app click: activate; if the app `isHidden` (Cmd+H), `unhide()` first.

## Behavior

### App row
- Active apps first (current frontmost-first z-order), then parked apps
  appended (sorted by name for stability), exactly as today's visible-then-
  hidden split — except the trailing group is now "parked" (Cmd+H **or**
  ghost-only) rather than only Cmd+H.
- `Tab` / `Shift+Tab` skip parked apps (generalize the current
  `nextNonHiddenIndex` to `nextActiveIndex`, keyed on `isParked`).
- Clicking any app icon activates it and closes the overlay; clicking a parked
  app that `isHidden` calls `NSRunningApplication.unhide()` before `activate()`.
- A parked icon shows a small count badge (upper-right): a circle with the
  window count. Ghost-only → "0".

### Window row
- For the selected (active) app, the row shows its **real** windows (normal
  thumbnails) followed by its **minimized** windows (smaller, gray-backed
  placeholder thumbnails, labeled with the window title).
- Arrow keys / number keys / click select across both real and minimized
  windows (one contiguous list; minimized ones come last).
- Selecting (commit / number / click) a minimized window **un-minimizes** it
  (AX `kAXMinimized = false`) and raises it, instead of the plain raise used
  for real windows.

## Non-Goals (v1)
- No per-window count badge split into two icons (the earlier "2 icons" idea is
  dropped; one icon per app, parked or active).
- No live capture of minimized windows (placeholder only — macOS doesn't render
  off-screen windows for ScreenCaptureKit).
- No change to the desktop chip row, the Ctrl+Down snapshot, or the menu bar.

## Permissions
None new — Accessibility (already granted) covers `kAXMinimized` reads and
un-minimize writes; Screen Recording (already granted) covers real-window
thumbnails.

## Architecture

### 1. `MinimizedWindows.swift` (new)
Accessibility helper, isolated so the AX calls live in one place.

```swift
enum MinimizedWindows {
    /// Number of minimized (kAXMinimized == true) windows owned by `pid`.
    static func count(forPID pid: pid_t) -> Int

    /// AX info for each minimized window of `pid` — title + frame, used to
    /// build placeholder SwitcherWindows and later to un-minimize + raise.
    static func minimizedWindows(forPID pid: pid_t) -> [AXMinimizedWindow]

    /// Set kAXMinimized = false on the AX window matching `info`, then raise it.
    static func restore(_ info: WindowInfo, pid: pid_t)
}

struct AXMinimizedWindow {  // title + frame, no CGWindowID
    let title: String
    let frame: CGRect
}
```

Implementation uses `AXUIElementCreateApplication(pid)`,
`kAXWindowsAttribute`, and per-window `kAXMinimizedAttribute`. `restore`
reuses the matching idea from the existing `WindowMatcher` to pick the AX
window by frame/title, sets `kAXMinimizedAttribute = false`, then performs
`kAXRaiseAction`.

### 2. `WindowClassifier.swift` (new, pure — TDD)
The classification rules as a pure function so they're unit-testable without
CGS/AX.

```swift
struct ClassifierInput {
    let pid: pid_t
    let realWindowCount: Int       // windows passing the real-window bar
    let minimizedWindowCount: Int  // from AX
    let isHidden: Bool             // Cmd+H (NSRunningApplication.isHidden)
}

enum AppClass: Equatable { case active; case parked(windowCount: Int) }

enum WindowClassifier {
    static func classify(_ input: ClassifierInput) -> AppClass
}
```

Rules (pure):
- `isHidden` → `.parked(windowCount: realWindowCount)` (the Cmd+H window count
  is supplied by the caller from a PID-wide CGWindowList count).
- else `realWindowCount > 0 || minimizedWindowCount > 0` → `.active`.
- else → `.parked(windowCount: 0)` (ghost-only).

Unit tests cover each branch and the boundary (0/0 not hidden → parked 0;
0 real + 1 minimized → active; 1 real → active; hidden with 3 → parked 3).

### 3. `SwitcherModels.swift` (extend)
```swift
struct SwitcherApp: Identifiable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    let isHidden: Bool        // Cmd+H — still needed for unhide-on-click
    let isParked: Bool        // drives small/dim/badge/Tab-skip
    let windowCount: Int      // badge value (parked only; 0 otherwise)
    var id: pid_t { pid }
}

struct SwitcherWindow: Identifiable {
    let windowID: CGWindowID
    let title: String
    let info: WindowInfo
    let pid: pid_t
    var image: CGImage?
    var isMinimized: Bool      // smaller + gray + un-minimize on select
    var id: CGWindowID { windowID }
}
```

### 4. `DesktopAppEnumerator.swift` (extend)
`appsOnSpace(_:)` and `currentDesktopApps()` produce active apps then parked
apps with counts:

1. Read `CGWindowList` for the Space (existing `allSpacesWindows` +
   `WindowsOnSpace`), tagging each window's frame so a "real window" count
   per PID can be computed (layer 0, ≥80×80, intersects display bounds).
2. For each PID, compute `realWindowCount`. For PIDs with 0 real windows,
   query `MinimizedWindows.count(forPID:)`.
3. Build `ClassifierInput` per PID; `WindowClassifier.classify` →
   active vs parked(count).
4. Active apps keep the frontmost-first z-order. Parked ghost-only apps plus
   all Cmd+H apps (`NSWorkspace.runningApplications` where `isHidden`) form the
   trailing parked group, sorted by name; their `windowCount` from the
   classifier / a PID-wide CGWindowList count.

A small per-PID "real window" counter helper (pure, fed `[RawAppWindow]` with
frames) is added to `DesktopAppList` and unit-tested alongside the existing
`appPIDs` variants.

### 5. `WindowEnumerator.swift` (extend)
`filteredSCWindows(forPID:onSpace:)` stays as-is for real windows. The
controller separately asks `MinimizedWindows.minimizedWindows(forPID:)` and
appends placeholder `SwitcherWindow`s (`isMinimized = true`, `image = nil`).

### 6. `SwitcherController.swift` (extend)
- `loadWindows` builds real `SwitcherWindow`s (as today) and appends minimized
  ones from `MinimizedWindows`.
- Tab skip: generalize `nextNonHiddenIndex` → `nextActiveIndex` (skip
  `isParked`).
- `clickApp`: unchanged except it reads `isHidden` for the unhide step (already
  does).
- Window commit/click/number: if the selected `SwitcherWindow.isMinimized`,
  call `MinimizedWindows.restore(info, pid:)` instead of
  `WindowActivator.activate`.

### 7. `SwitcherView.swift` (extend)
- App icon: `isParked` → 40px, faint bg, 0.55 opacity, **count badge** overlay
  top-right (a small dark circle with the count). Active → 64px as today.
- Window thumb: `isMinimized` → ≈130×85 frame, gray background, title label;
  otherwise the current 200×130.

## Data flow

```
open() / previewDesktop()
  → appsOnSpace(space):
      CGWindowList → per-PID realWindowCount
      0-real PIDs → MinimizedWindows.count  → WindowClassifier
      + Cmd+H apps from NSWorkspace
      → [SwitcherApp] active-first, parked(count) trailing
Tab / Shift+Tab → nextActiveIndex (skip isParked)
select app → loadWindows:
      real SCWindows (thumbnails) + MinimizedWindows placeholders
      → [SwitcherWindow] real-first, minimized trailing
commit / number / click on a window:
      isMinimized ? MinimizedWindows.restore : WindowActivator.activate
click on app icon: activate (+ unhide if isHidden)
```

## Testing strategy

### Unit (TDD)
- **`WindowClassifier.classify`**: hidden→parked(n); 0/0→parked(0);
  0 real + ≥1 minimized→active; ≥1 real→active.
- **`DesktopAppList` real-window counter**: per-PID count honoring layer/size/
  bounds; parallels existing `appPIDs` tests.

### Integration / manual (live CGS + AX)
- `MinimizedWindows` (AX) and the enumerator wiring are verified end-to-end:
  1. Acrobat with no document → appears as a parked icon with badge "0",
     Tab skips it, click launches/activates it.
  2. Cmd+H an app with 2 windows → parked icon, badge "2", click un-hides.
  3. Cmd+M one window of an app that also has a visible window → app stays
     active (Tab-reachable); window row shows the visible thumbnail plus a
     smaller gray minimized thumbnail; selecting the minimized one restores it.
  4. App with only a minimized window → still Tab-reachable; its single gray
     thumbnail restores on select.

## Risks / open concerns
1. **AX latency**: minimized detection is an AX round-trip per relevant PID.
   Bounded by only querying 0-real-window PIDs upfront and the selected app on
   `loadWindows`. Expected < a few ms.
2. **AX reliability**: `kAXMinimized` and the AX window list are well-trodden
   (used by window managers); the existing app already holds the Accessibility
   grant. If AX returns nothing for an app, it degrades to "no minimized
   windows" (app may then classify as parked), which is acceptable.
3. **Minimized thumbnails are placeholders**: ScreenCaptureKit cannot capture
   off-screen windows, so minimized entries always show the gray placeholder.
   This is intended (matches the requested gray treatment).
4. **Matching AX windows to restore**: `restore` matches by frame/title via the
   existing `WindowMatcher` approach; ambiguous matches (two identical
   untitled windows) fall back to the first match — acceptable for v1.
