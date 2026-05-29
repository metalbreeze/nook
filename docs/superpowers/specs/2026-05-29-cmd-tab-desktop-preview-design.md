# Cmd+Tab Desktop Preview Model

**Date:** 2026-05-29
**Status:** Approved design, pending implementation plan
**Project:** Nook (macOS menu-bar agent)

## Summary

Redesign the keyboard semantics of the Cmd+Tab desktop chip row so that
keyboard nav **previews** a desktop inside the overlay (swapping the
shown apps + windows) without changing the macOS active Space. The actual
Space switch happens when the user **releases Cmd**, unless they instead
pick a window via `Cmd+<digit>` (which activates that window and incidentally
switches Space).

Adds two key aliases (`` Cmd+` `` ≡ `Cmd+[`, `` Cmd+Shift+` `` ≡ `Cmd+]`)
and a new `Cmd+Shift+<digit>` shortcut that jumps the preview to chip N.

The mouse-click path is **unchanged**: clicking a chip remains a decisive
"close + switch" action.

Builds on the existing chip-row feature
(`docs/superpowers/specs/2026-05-28-cmd-tab-desktop-list-design.md`).

## Behavior

### State concepts

| State | Meaning |
|---|---|
| **realSpaceID** | The macOS active Space at the moment the overlay opened; never changes during the session. |
| **previewedSpaceID** | The Space whose apps + windows are currently displayed in the overlay; starts equal to `realSpaceID`, mutates as the user navigates. |

When `previewedSpaceID == realSpaceID` the overlay shows the same thing it
shows today. When they differ, the apps row, the selected-app name, and the
windows row all reflect `previewedSpaceID` — the user is "looking into" a
different desktop without yet committing to it.

### Keyboard

| Keys (Cmd held throughout) | Action |
|---|---|
| `Tab` / `Shift+Tab` | Cycle the **app selection** within `previewedSpaceID`. |
| `←` / `→` | Cycle the selected app's windows within `previewedSpaceID`. |
| `1`–`9` (i.e. `Cmd+<digit>`) | Activate the n-th window of the currently selected app on `previewedSpaceID` (closes overlay; macOS auto-switches Space if the window lives elsewhere). |
| `]` (i.e. `Cmd+]`) | `previewedSpaceID` ← next chip in the row (wrap). Refresh apps + windows. |
| `[` (i.e. `Cmd+[`) | `previewedSpaceID` ← previous chip (wrap). Refresh apps + windows. |
| `` ` `` (i.e. `` Cmd+` ``) | Alias for `Cmd+[` (previous desktop preview). |
| `Shift+` `` (i.e. `` Cmd+Shift+` ``) | Alias for `Cmd+]` (next desktop preview). |
| `Shift+1`–`Shift+9` (i.e. `Cmd+Shift+<digit>`) | `previewedSpaceID` ← the chip at 1-based position N. No-op if N exceeds the number of chips. |
| `Esc` | Cancel: close overlay; do not switch Space; do not activate anything. |
| **Release `Cmd`** | Commit (see below). |

### Mouse

- **Click on a non-current chip** — unchanged: close overlay + immediately switch macOS to that Space. (Mouse is a decisive pointer; click = commit.)
- **Click on a window thumbnail** — unchanged: close overlay + activate that window. The window is on `previewedSpaceID` (which may differ from `realSpaceID`); activating it auto-switches Space.
- **Click on the current-preview chip** — no-op.

### Commit on Cmd release

Single rule, evaluated in this order:

1. **Window selected** (`selectedWindowIndex >= 0`) → activate that window. macOS auto-switches Space if needed. Close overlay.
2. **`previewedSpaceID != realSpaceID`** → call `SpaceSwitcher.switchTo(previewedSpaceID, displayUUID:)`. Close overlay. Do not activate any app.
3. **`previewedSpaceID == realSpaceID`** → activate the selected app on the current desktop (this is the existing app-level commit). Close overlay.

### Rename mode (`isRenaming == true`)

All of the above keyboard nav and chip clicks are gated off, as today.
The TextField path is unchanged.

### Chip highlighting (two-tier)

- The chip at `previewedSpaceID` renders with the existing **white-translucent solid background** (primary indicator: "this is what you are looking at").
- The chip at `realSpaceID` (the actual macOS active Space) renders with a **thin outlined border** (secondary indicator: "this is where you are right now").
- When `previewedSpaceID == realSpaceID` the same chip carries both states (visually dominated by the solid fill; the outline is still drawn for consistency).

## Non-Goals (v1)

- No inline rename of non-current desktops (Rename remains on the previewed chip; saves the name to whatever `previewedSpaceID` currently is).
- No full-screen-app Spaces, no other displays' Spaces — same scope as the existing chip-row feature.
- No switching animation.
- No persistent per-Space app/window cache; everything is recomputed on each preview change.
- No keyboard nav of *windows across* multiple desktops in one go.

## Permissions

None new. Same Accessibility + Screen Recording grants.

## Architecture

### 1. `CGSSpace.swift` (extend)

Add one more private symbol next to the three already there:

```swift
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ mask: UInt64,
    _ windowIDs: CFArray
) -> CFArray
```

The `mask` argument selects which kinds of Spaces to include in the result.
`0x7` covers all user + fullscreen + system Spaces (Yabai-style usage), which
is what we want here because we want to know "is this window on Space X?"
regardless of Space type.

### 2. `WindowsOnSpace.swift` (new)

Tiny side-effecting helper:

```swift
enum WindowsOnSpace {
    /// Window IDs that currently belong to `spaceID`. Includes windows that
    /// are not visible on screen (e.g. on a different Space). Empty on
    /// failure.
    static func windowIDs(on spaceID: CGSSpaceID) -> Set<CGWindowID>
}
```

Implementation: read `CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID)` (without `.optionOnScreenOnly` so we get all Spaces), then for each window call `CGSCopySpacesForWindows(connection, 0x7, [windowID] as CFArray)`, parse the returned `CFArray` of `NSNumber` Space IDs, include the window if `spaceID` is in the set.

### 3. `DesktopAppList.swift` (extend)

The existing pure function:

```swift
static func appPIDs(from windows: [RawAppWindow], frontmostPID: pid_t) -> [pid_t]
```

is augmented with one variant that takes a window-ID allow-set instead of
the `isOnScreen` filter:

```swift
static func appPIDs(from windows: [RawAppWindow],
                    frontmostPID: pid_t,
                    allowedWindowIDs: Set<CGWindowID>) -> [pid_t]
```

Both are pure. The new variant filters by `allowedWindowIDs.contains(window.windowID)`
instead of `isOnScreen`. Unit-tested side-by-side with the existing variant.

To carry the windowID, `RawAppWindow` gains an optional `windowID: CGWindowID?`
field (default `nil` for the existing call site, populated for the new path).

### 4. `DesktopAppEnumerator.swift` (extend)

Existing `currentDesktopApps()` is unchanged. New function:

```swift
static func appsOnSpace(_ spaceID: CGSSpaceID) -> [SwitcherApp]
```

Implementation:
1. `let allowed = WindowsOnSpace.windowIDs(on: spaceID)`
2. Read `CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID)` (all Spaces).
3. Build `[RawAppWindow]` for each entry (ownerPID, layer, isOnScreen=true placeholder, windowID).
4. Call `DesktopAppList.appPIDs(from:frontmostPID:allowedWindowIDs:)`.
5. Map PIDs to `SwitcherApp` via `NSRunningApplication`.

### 5. `WindowEnumerator.swift` (extend)

Existing `filteredSCWindows(forPID:)` enumerates current-Space windows of a
PID. New variant:

```swift
static func filteredSCWindows(forPID pid: pid_t,
                              onSpace spaceID: CGSSpaceID) async throws -> [SCWindow]
```

Implementation: same SCShareableContent fetch, but the allow-set is
`WindowsOnSpace.windowIDs(on: spaceID)` intersected with the per-PID layer-0
filter. The existing call site (current desktop) keeps the existing function.

### 6. `SwitcherModel.swift` (extend)

```swift
final class SwitcherModel: ObservableObject {
    // existing fields…
    @Published var previewedSpaceID: CGSSpaceID?
    @Published var realSpaceID: CGSSpaceID?
}

struct DesktopVM: Identifiable, Equatable {
    let id: CGSSpaceID
    let label: String
    let displayUUID: String
    let isPreviewed: Bool      // ← replaces isCurrent
    let isReal: Bool           // ← new
}
```

`isCurrent` is replaced by the two new flags. `isPreviewed` drives the
white-solid background. `isReal` drives the outlined border.

### 7. `SwitcherCommit.swift` (extend)

```swift
enum SwitcherCommit {
    enum Intent: Equatable {
        case app
        case window(Int)
        case switchSpace(CGSSpaceID, displayUUID: String)
        case noop
    }

    /// Order of precedence: window > switchSpace > app.
    static func resolve(
        selectedWindowIndex: Int,
        windowCount: Int,
        previewedSpaceID: CGSSpaceID?,
        realSpaceID: CGSSpaceID?,
        previewedDisplayUUID: String?
    ) -> Intent {
        if selectedWindowIndex >= 0 && selectedWindowIndex < windowCount {
            return .window(selectedWindowIndex)
        }
        if let preview = previewedSpaceID,
           let real = realSpaceID,
           let uuid = previewedDisplayUUID,
           preview != real {
            return .switchSpace(preview, displayUUID: uuid)
        }
        return .app
    }
}
```

The old `didNavigateDesktop`-based path (added in the v1.0.1 fix) is
**removed**. Existing tests in `SwitcherCommitTests` are updated to call the
new signature; behavior for the `.window` / `.app` paths is unchanged when
preview == real.

### 8. `SwitcherController.swift` (extend)

Replace the `didNavigateDesktop` field and `advanceToDesktop(at:)` helper
with a single `previewDesktop(at:)` method. Key changes:

- On `open()`, populate both `realSpaceID` and `previewedSpaceID` to the
  current Space; build `desktopVMs` with the two-tier flags.
- New `previewDesktop(at index: Int)`:
  - Set `model.previewedSpaceID = target.spaceID`.
  - Rebuild `model.desktops` with updated `isPreviewed` / `isReal`.
  - Replace `model.apps` with `DesktopAppEnumerator.appsOnSpace(target.spaceID)`.
  - Reset `model.selectedAppIndex = 0`, `selectedWindowIndex = -1`.
  - Call `loadWindowsOnPreviewedSpace(forAppIndex: 0)` (a variant of
    `loadWindows` that uses `WindowEnumerator.filteredSCWindows(forPID:onSpace:)`).
- New `previewDesktop(byNumber n: Int)`: lookup `model.desktops[n-1]`, no-op
  if out of range; else call `previewDesktop(at: n-1)`.
- `desktopNext()` / `desktopPrev()` compute neighbor index and call
  `previewDesktop(at:)`.
- `commit()` uses the new `SwitcherCommit.resolve` and handles the new
  `.switchSpace` branch: `SpaceSwitcher.switchTo(spaceID, displayUUID)`,
  then `close()`.
- `clickDesktop(_:)` (mouse path) is unchanged: still close + switch.

### 9. `SwitcherHotkey.swift` (extend)

- Add backtick keycode: `private static let backtickKeyCode: Int64 = 50`.
- Add callback `var onDesktopNumber: ((Int) -> Void)?`.
- In the active branch of `handle(type:event:)`:
  - When Shift is held: digits `1`-`9` fire `onDesktopNumber(n)` (intercept before the existing digit-fires-`onWindowNumber` branch).
  - Backtick + Shift → `fire(\.onDesktopNext)`.
  - Backtick alone → `fire(\.onDesktopPrev)`.
- The existing Tab/Esc/arrow/digit/bracket paths are unchanged.

### 10. `AppDelegate.swift` (extend)

Wire one more line:

```swift
hotkey.onDesktopNumber = { [weak self] n in self?.switcher.previewDesktop(byNumber: n) }
```

### 11. `SwitcherView.swift` (touch)

`desktopChip` reads `isPreviewed` and `isReal` from the new `DesktopVM`:
- `isPreviewed` → `.background(Color.white.opacity(0.25))`
- `isReal` → `.overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1.5))`

Both are applied; visual stacking handles the case where both are true.

## Data Flow

```
Open Cmd+Tab
  → SwitcherController.open()
  → realSpaceID = previewedSpaceID = CurrentSpace.id()
  → desktopVMs built with isPreviewed = isReal = (id == previewedSpaceID)
  → apps = DesktopAppEnumerator.appsOnSpace(previewedSpaceID)
  → SwitcherView renders chip row (both flags collide on current chip)

Cmd+] / Cmd+[ / Cmd+` / Cmd+Shift+` / Cmd+Shift+<digit>
  → previewDesktop(at: ...)
  → previewedSpaceID = target
  → desktops re-flagged (isPreviewed moves; isReal stays)
  → apps refreshed via appsOnSpace(target)
  → windows row reloaded via filteredSCWindows(forPID:onSpace:target)
  → overlay stays open

Cmd+<digit> (without Shift)
  → existing onWindowNumber → activate selected app's n-th window on previewedSpaceID
  → macOS auto-switches Space if needed; close overlay

Esc
  → close()  (no Space change, no activation)

Cmd release
  → commit()
  → SwitcherCommit.resolve(...) →
      .window(i)      → WindowActivator.activate(...)
      .switchSpace(s) → SpaceSwitcher.switchTo(s, displayUUID)
      .app            → NSRunningApplication(...).activate()
  → close()

Mouse click on non-current chip
  → clickDesktop(i)
  → close() + SpaceSwitcher.switchTo(target.id, target.displayUUID)
```

## Testing Strategy

### Unit (TDD)

- **`DesktopAppList.appPIDs(from:frontmostPID:allowedWindowIDs:)`**: window-ID filtering + dedupe + frontmost-first ordering, parallel to the existing tests on the `isOnScreen` variant.
- **`SwitcherCommit.resolve`** (new signature):
  - `.window` precedence: any valid `selectedWindowIndex` returns `.window` regardless of preview/real.
  - `.switchSpace` when `preview != real` and no window selected.
  - `.app` when `preview == real` and no window selected.
  - Uses `XCTAssertEqual` against the new `Intent` cases (still `Equatable`).
- **Existing `SwitcherCommitTests`**: ported to the new signature with `previewedSpaceID == realSpaceID` so old assertions still hold.

### Integration / manual

`WindowsOnSpace`, `DesktopAppEnumerator.appsOnSpace`, `filteredSCWindows(forPID:onSpace:)`, and the controller-level state machine require a live WindowServer and are covered by the end-to-end checklist:

1. Three named desktops, Cmd+Tab → chip row shows three chips; current chip has both solid + outline; preview moves with `]`/`[` (apps row and windows row swap accordingly).
2. `Cmd+Shift+2` → preview jumps to chip 2; `Cmd+Shift+5` (with 3 chips) is a no-op.
3. `` Cmd+` `` and `` Cmd+Shift+` `` behave as `Cmd+[` / `Cmd+]`.
4. Preview a desktop, release Cmd → macOS switches to that desktop, no app jump.
5. Preview a desktop, press `Cmd+3` → window 3 of selected app on previewed desktop activates; macOS auto-switches Space.
6. Mouse click on non-current chip → close + switch (unchanged decisive semantic).
7. Esc → close, no Space change.
8. Single-desktop case → chip row hidden (legacy name row), all keys reduce to existing behavior.
9. Rename mode → all new bindings ignored.

## Risks / Open Concerns

1. **Private API surface widens**: one more `@_silgen_name` (`CGSCopySpacesForWindows`). Same risk pool as the three already in use. Documented as unsupported. Failure mode is "empty apps list for non-current preview" — no crash.
2. **Performance of per-preview enumeration**: ~50 windows × ~50 µs per `CGSCopySpacesForWindows` call ≈ 2-3 ms. Acceptable for interactive use. The async generation-token pattern (already in `SwitcherController.loadWindows`) protects against fast-keystroke jitter.
3. **Thumbnails on non-current Space**: SCScreenshotManager may return empty for off-Space windows. The existing placeholder UI (`Image(systemName: "macwindow")`) covers this gracefully.
4. **`Cmd+\``** and `` Cmd+Shift+` `` **on non-US layouts**: backtick keycode `50` is US-layout-specific. Same caveat as bracket/Tab/digit codes already hard-coded.
5. **Cmd+Shift+digit collisions**: macOS / 3rd-party apps may grab some `Cmd+Shift+<digit>` chords (e.g. `Cmd+Shift+3` = screenshot). Within Nook's active branch (i.e. after Cmd+Tab opened the switcher), Nook intercepts and swallows the event before it propagates — same precedence as the existing digit handling. Outside the active switcher state, the chord is untouched.
