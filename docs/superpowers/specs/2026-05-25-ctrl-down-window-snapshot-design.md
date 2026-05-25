# MyDefineShortcut — Current-Desktop Window Snapshot

**Date:** 2026-05-25
**Status:** Approved design, pending implementation plan

## Summary

A macOS menu-bar utility that intercepts the global **Ctrl+Down** shortcut and, instead of
the system's built-in App Exposé (which shows the focused app's windows across *all* Spaces),
shows a thumbnail-grid overlay of the focused app's **visible windows on the current desktop
(Space) only**, with a count. Clicking a thumbnail raises that window. Esc / click-away dismisses.

The visual presentation mimics the native macOS App Exposé overlay (thumbnail grid with per-window
title labels), scoped to the current Space.

## Goals

- Intercept the system Ctrl+Down shortcut and suppress the default App Exposé behavior.
- Determine the frontmost (focused) application.
- Enumerate that app's **visible** windows on the **current desktop only** (exclude minimized
  windows and windows on other Spaces).
- Present them as a thumbnail grid overlay (App Exposé style) with a header showing the count.
- Click a thumbnail to raise/activate that window and dismiss the overlay.
- Dismiss with Esc, click-away, or focus loss.

## Non-Goals (v1)

- No multi-monitor fan-out: overlay appears on the screen containing the focused window only.
- No user-configurable hotkey (fixed to Ctrl+Down).
- No minimized-window handling (minimized windows are excluded).
- No preferences window beyond the menu-bar menu.
- No notarized public distribution (local/dev signing is sufficient).

## Environment

- macOS 26.3.1 (Tahoe), Apple Silicon (arm64).
- Swift 6.3.2, Xcode 26.5.
- App form: `LSUIElement` menu-bar agent (no Dock icon).

## Architecture

The app is a background menu-bar agent composed of focused, independently testable units:

### 1. HotkeyTap
- Creates a `CGEventTap` at the session level (`.cgSessionEventTap`, `.headInsertEventTap`,
  `.defaultTap` — an active tap that can modify/suppress events).
- Listens for `keyDown` events; matches when keycode == `kVK_DownArrow` (125) **and** the only
  active modifier is Control (`.maskControl`, with no Shift/Option/Command).
- On match: invokes the overlay trigger and **returns `nil`** to swallow the event so the system
  App Exposé does not fire.
- Re-enables itself on `.tapDisabledByTimeout` / `.tapDisabledByUserInput`.
- **Depends on:** Accessibility permission.
- **Risk / fallback:** Ctrl+Down is a reserved Mission Control ("Application windows") shortcut.
  A session-level event tap normally intercepts and suppresses it, but if testing shows the system
  still fires App Exposé, the fallback is to also disable the system "Application windows" symbolic
  hotkey (via the `com.apple.symbolichotkeys` setting). Lead with the tap; add the fallback only if
  observed necessary.

### 2. WindowEnumerator
- Input: the frontmost app's PID (`NSWorkspace.shared.frontmostApplication.processIdentifier`).
- Queries ScreenCaptureKit `SCShareableContent` for all on-screen windows.
- Filters to: `owningApplication.processID == frontmostPID`, `windowLayer == 0` (normal app
  windows), `isOnScreen == true`, and a reasonable minimum size (drop tiny utility/HUD windows).
- **`isOnScreen == true` is the current-desktop / visible filter** — windows on other Spaces and
  minimized windows report `false`.
- Output: ordered list of `WindowInfo { windowID, title, frame, appName }` and the count.
- **Depends on:** Screen Recording permission (also needed for non-empty window titles).

### 3. ThumbnailCapturer
- For each enumerated window, captures a `CGImage` via `SCScreenshotManager.captureImage`
  using a single-window `SCContentFilter`.
- Scales/caches images for grid display.
- **Depends on:** Screen Recording permission.

### 4. WindowActivator
- On thumbnail click: matches the chosen `WindowInfo` to the owning app's Accessibility window
  element. Build `AXUIElementCreateApplication(pid)`, read `kAXWindowsAttribute`, and match the
  target window by `frame` (position + size) and/or `kAXTitle`.
- Performs `kAXRaiseAction` on the matched AX window and activates the app
  (`NSRunningApplication.activate`).
- **Depends on:** Accessibility permission.

### 5. OverlayController + SwiftUI grid
- A borderless, transparent, full-screen `NSWindow` (or `NSPanel`) at a high window level
  (e.g. `.screenSaver` or above the menu bar), with a dimmed/blurred backdrop
  (`NSVisualEffectView`).
- SwiftUI content: a responsive grid of aspect-ratio-preserving thumbnails, each with a title
  label below; a header reading `"<AppName> — N windows"`.
- Animated fade/scale in and out to feel native.
- Dismiss on: Esc (local key monitor), click on the backdrop (not a thumbnail), or app focus loss.
- Shown on the screen containing the focused window (v1 single display).

### 6. MenuBarAgent (AppDelegate)
- `LSUIElement` app: a status-bar item with a menu showing permission status (Accessibility,
  Screen Recording), enable/disable toggle, and Quit.
- On launch: checks both permissions; if missing, surfaces guidance and links to the relevant
  System Settings panes
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` and
  `...?Privacy_ScreenCapture`).

## Data Flow

```
Ctrl+Down pressed
  -> HotkeyTap matches, returns nil (system App Exposé suppressed)
  -> read frontmost app PID (NSWorkspace)
  -> WindowEnumerator: SCShareableContent filtered to current-Space visible windows of that PID
  -> ThumbnailCapturer: capture a CGImage per window
  -> OverlayController: present SwiftUI thumbnail grid ("AppName — N windows")
  -> user clicks a thumbnail
  -> WindowActivator: AX-raise that window + activate app
  -> overlay dismisses
(Esc / click-away / focus loss also dismiss)
```

## Permissions

| Permission       | Why                                              | If denied                                    |
|------------------|--------------------------------------------------|----------------------------------------------|
| Accessibility    | Keyboard event tap + raising windows via AX      | App cannot function; prompt + Settings link  |
| Screen Recording | Window thumbnails + non-empty window titles      | Graceful fallback to title-only cards        |

**Graceful fallback:** If Screen Recording is denied, the overlay still shows the count and a card
per window with the title obtained via Accessibility, instead of thumbnails.

## Build & Packaging

- **Xcode project** (`.xcodeproj`) with a macOS App target.
- `Info.plist`: `LSUIElement = YES`, bundle id `com.metalbreeze.MyDefineShortcut`,
  `NSScreenCaptureUsageDescription` and any required usage strings.
- Signed with a **stable identity** ("Sign to run locally" or the user's Apple Development team)
  so TCC permission grants persist across rebuilds.
- Buildable from Xcode (Run) or CLI (`xcodebuild`).

## Testing Strategy

- **Unit-testable units:** WindowEnumerator filtering logic (given a list of window metadata,
  assert the correct subset/count), WindowActivator matching logic (match by frame/title), hotkey
  match predicate (keycode + modifier combination).
- **Manual / integration verification (requires a real session with granted permissions):**
  - Ctrl+Down suppresses native App Exposé and shows the custom overlay.
  - With a multi-Space setup, only current-desktop windows of the focused app appear and the count
    is correct.
  - Clicking a thumbnail raises the correct window and dismisses the overlay.
  - Esc / click-away / focus loss all dismiss.
  - Screen Recording denied → title-card fallback renders.

## Open Risks

1. **Hotkey suppression reliability** for the reserved Ctrl+Down shortcut (see HotkeyTap fallback).
2. **AX-to-SCWindow matching** when an app has multiple same-titled windows — disambiguate by frame;
   accept best-effort match if frames also collide.
3. **TCC permission persistence** depends on a stable signing identity across rebuilds.
