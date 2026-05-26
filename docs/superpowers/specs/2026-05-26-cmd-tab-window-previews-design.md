# Cmd+Tab Window Previews + Window-Level Switching

**Date:** 2026-05-26
**Status:** Approved design, pending implementation plan
**Project:** MyDefineShortcut (macOS menu-bar agent)

## Summary

Enhance the existing Cmd+Tab current-desktop app switcher so that, for the highlighted app,
it previews that app's current-desktop windows as thumbnails and lets the user switch to a
specific window — via Left/Right arrows or the mouse. App-level switching remains the default;
window selection is opt-in within a session.

This builds on the existing Cmd+Tab switcher and reuses the Ctrl+Down feature's window
enumeration, thumbnail capture, and window-raise machinery.

## Interaction Model

With Cmd held:
- **Cmd+Tab** opens the switcher; the current app is highlighted (app index 0), **app-level**
  (no specific window selected, `selectedWindowIndex = -1`). The highlighted app's current-desktop
  window thumbnails appear below the app strip, loading asynchronously.
- **Tab / Shift+Tab** → next/prev app (wrap-around). The window-preview row updates to the new
  app's windows; window selection resets to -1 (app-level).
- **Left / Right arrow** → select prev/next window of the highlighted app (wrap-around). The first
  arrow press (from -1) selects the first window.
- **Mouse hover** over a window thumbnail → highlights it (sets `selectedWindowIndex`).
- **Mouse click** on a window thumbnail → raises that window immediately and closes the switcher.
- **Release Cmd** → if `selectedWindowIndex >= 0`, raise that window; otherwise activate the
  highlighted app.
- **Esc** → cancel (close, no switch).

## Non-Goals (v1)

- No MRU ordering (apps still ordered by window z-order, current app first — unchanged).
- No multi-monitor fan-out (single display, consistent with existing features).
- No reordering/closing windows from the switcher.
- Eager capture of every app's windows up front (capture is lazy, highlighted app only).

## Permissions

- **Accessibility** — already required (event tap + window raise).
- **Screen Recording** — now also required for the window thumbnails (already granted for Ctrl+Down).
  If denied, windows render as icon placeholders (count + titles still work); app-level switching
  and arrow/click selection still function.

## Approach

**Lazy per-app thumbnail capture.** Capture thumbnails only for the *highlighted* app's windows,
asynchronously, and cache them. When the user Tabs to an app, its window outlines/placeholders show
immediately and thumbnails fill in shortly after. A **generation token** guards against stale async
results when the user Tabs quickly (only the latest app-selection's results are applied).

Rejected: eager capture of all apps' windows on open (too slow — could be dozens of captures).

**Reuses existing units:**
- `DesktopAppEnumerator.currentDesktopApps()` — the app strip (icons/names/pids).
- `WindowEnumerator.filteredSCWindows(forPID:)` — the highlighted app's current-desktop windows,
  including the off-screen-during-Space-switch fix.
- `ThumbnailCapturer.capture(_:)` — per-window thumbnails.
- `WindowActivator.activate(_:pid:)` — raise a specific window via Accessibility.
- `SwitcherIndex.advance/reverse` — wrap-around cycling for both apps and windows.

## Architecture

### 1. SwitcherModels (extend)
- New `SwitcherWindow: Identifiable { let windowID: CGWindowID; let title: String; let info: WindowInfo; let pid: pid_t; var image: CGImage? }` (`id = windowID`). `image` is filled in asynchronously.
- `SwitcherModel` (ObservableObject) gains:
  - `@Published var selectedAppIndex: Int` (rename of the existing `selectedIndex`)
  - `@Published var windows: [SwitcherWindow]` (highlighted app's current-desktop windows)
  - `@Published var selectedWindowIndex: Int` (-1 = app-level)
  - keeps `@Published var apps: [SwitcherApp]`

### 2. SwitcherController (@MainActor)
- `open()` — enumerate apps; show overlay; `selectedAppIndex = 0`, `selectedWindowIndex = -1`;
  kick off `loadWindows(for: 0)`.
- `advance()/reverse()` — change `selectedAppIndex` (via `SwitcherIndex`), reset
  `selectedWindowIndex = -1`, call `loadWindows(for:)`.
- `windowLeft()/windowRight()` — if `windows` non-empty: move `selectedWindowIndex` (from -1, first
  press selects 0) via `SwitcherIndex`.
- `hoverWindow(_ index:)` — set `selectedWindowIndex = index`.
- `clickWindow(_ index:)` — raise `windows[index]` via `WindowActivator`, close.
- `commit()` — if `selectedWindowIndex >= 0`, raise `windows[selectedWindowIndex]`; else activate
  `apps[selectedAppIndex]`; close.
- `cancel()` — close.
- `loadWindows(for appIndex:)` — increments a `generation` token; async fetch
  `WindowEnumerator.filteredSCWindows(forPID:)`, map to `SwitcherWindow` (no images), set
  `model.windows` only if `generation` still current; then capture each thumbnail async, updating
  the matching `SwitcherWindow.image` (guarded by the same generation).

### 3. SwitcherHotkey (extend)
- Add Left (keycode 123) and Right (124) handling while active → `onWindowLeft` / `onWindowRight`
  callbacks; swallow them. Keep Tab(48)/Shift+Tab/Esc(53)/Cmd-release behavior.

### 4. SwitcherView (extend)
- Keep the app-icon strip (Tab-driven, `selectedAppIndex` highlighted).
- Add below it a row of window thumbnails for the highlighted app: each is hoverable
  (`onHover` → controller `hoverWindow`) and clickable (`onTapGesture`/Button → controller
  `clickWindow`). The window at `selectedWindowIndex` is highlighted. Each cell shows the thumbnail
  image, or an icon placeholder until it loads (or if Screen Recording is denied).

### 5. OverlayWindow / SwitcherController window setup (change)
- The switcher overlay must now **accept mouse**: `ignoresMouseEvents = false`.
- Clicks must register even though our app isn't frontmost: host the SwiftUI content in a hosting
  view that returns `acceptsFirstMouse(for:) == true` (a small `NSHostingView` subclass).
- Keep `orderFrontRegardless()` (no focus theft) if first-mouse works. **Fallback:** if clicks don't
  register reliably without activation, activate our app on show and restore focus to the original
  app on cancel (the pattern already used by the Ctrl+Down `OverlayController`).

## Data Flow

```
Cmd+Tab -> SwitcherHotkey.onOpen -> controller.open()
  -> DesktopAppEnumerator.currentDesktopApps() -> app strip, selectedAppIndex=0, selectedWindowIndex=-1
  -> loadWindows(for: 0): WindowEnumerator.filteredSCWindows(forPID) -> [SwitcherWindow] (no images)
       -> async ThumbnailCapturer.capture per window -> fill images (guarded by generation token)
Tab/Shift+Tab -> advance/reverse -> new selectedAppIndex, selectedWindowIndex=-1, loadWindows(...)
Left/Right    -> windowLeft/windowRight -> selectedWindowIndex cycles
hover         -> hoverWindow(i) -> selectedWindowIndex = i
click         -> clickWindow(i) -> WindowActivator.activate(windows[i].info, pid) + close
release Cmd   -> commit(): selectedWindowIndex>=0 ? raise that window : activate app ; close
Esc           -> cancel(): close
```

## Testing Strategy

- **Unit-testable (TDD):**
  - `SwitcherIndex` already covers wrap-around cycling for windows (reused).
  - A small pure helper `SwitcherCommit.target(selectedWindowIndex:windowCount:)` (or equivalent)
    that resolves commit intent: returns `.window(index)` when `selectedWindowIndex >= 0` and in
    range, else `.app`. Tested for boundaries (-1, valid index, empty windows).
- **Manual / integration (real session):**
  - Tab cycles apps; window-preview row updates per app; thumbnails load asynchronously.
  - Left/Right select windows; the first press selects the first window.
  - Hover highlights a window; click raises exactly that window and closes.
  - Release Cmd raises the selected window, or activates the app when none selected.
  - Tabbing quickly doesn't show a previous app's thumbnails (generation token).
  - Screen Recording denied → icon placeholders; selection/switching still works.

## Open Risks

1. **Mouse clicks on a non-active overlay** — `acceptsFirstMouse`; focus-restore fallback if needed.
2. **Async capture races** on fast Tabbing — generation token.
3. **Capture latency** per app (a few windows) — acceptable; shown async with placeholders.
4. Cmd+Tab interception reliability (unchanged from the existing switcher).
