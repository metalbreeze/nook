# Cmd+Tab Desktop Chip Row

**Date:** 2026-05-28
**Status:** Approved design, pending implementation plan
**Project:** Nook (macOS menu-bar agent)

## Summary

In the Cmd+Tab overlay, show a horizontal strip of "desktop chips" representing
the current screen's user-space desktops, in Mission Control order. Clicking
a chip — or pressing `Cmd+]` / `Cmd+[` — switches to that desktop and closes
the overlay. The current desktop's chip is highlighted, and the existing
**Rename** button sits next to it.

Builds on the existing Cmd+Tab switcher (`SwitcherController`, `SwitcherView`,
`SwitcherHotkey`), the `DesktopNameStore`, and the private-CGS active-Space
detection (`CurrentSpace`).

## Behavior

### Layout
- The chip row replaces the existing single "desktop name + Rename" row at the
  top of the overlay (layout option **A** in brainstorm).
- Order matches the current screen's Mission Control Space stack.
- Each chip's label is `"<index>  <name>"`:
  - `<index>` is the 1-based position within the current screen's stack.
  - `<name>` is the user-stored name when present, else `"Desktop <index>"`.
  - Examples: `1  Work`, `3  Desktop 3`.
- The **current desktop's chip is highlighted** (white-ish background, matching
  the existing selected-app and selected-window highlight). The **Rename**
  button is rendered immediately to its right, with the same semantics as
  today (renames only the current desktop).
- Non-current chips render with no background; hover shows a subtle highlight
  (same affordance as window thumbnails).

### Interaction
- **Mouse click** on a non-current chip → close the overlay → `SpaceSwitcher`
  switches to that desktop.
- **Mouse click** on the current chip → no-op (it is already current).
- **`Cmd+]`** while Cmd is held in switcher mode → switch to the next desktop
  in the row (wrap-around), close the overlay.
- **`Cmd+[`** → previous desktop (wrap-around), close the overlay.
- **Rename mode (`isRenaming == true`)** → bracket keys and chip clicks are
  ignored, consistent with how Tab/arrows/digits are gated today.

### Scope
- **Only the current screen's user-space desktops** are listed. Other
  displays' Spaces and full-screen-app Spaces are excluded from v1.
- **Single-desktop case** (< 2 desktops on the current screen): the chip row
  is hidden entirely and the overlay falls back to the existing single name
  + Rename row. No behavior regression for single-desktop users.

## Non-Goals (v1)

- No inline rename for non-current desktops (only the current can be renamed,
  same as today).
- No full-screen-app Spaces in the row.
- No multi-display: only the screen currently showing the overlay is listed.
- No reorder / create / delete desktops.
- No switching animation, no per-chip thumbnail.

## Permissions

None new. Same Accessibility and Screen Recording grants the app already uses.

## Architecture

### 1. `CGSSpace.swift` (extend)

Add two more private CGS symbols, with the same `@_silgen_name` pattern used
for `CGSGetActiveSpace`:

```swift
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(
    _ cid: CGSConnectionID,
    _ displayUUID: CFString,
    _ spaceID: CGSSpaceID
)
```

`CGSCopyManagedDisplaySpaces` returns an `NSArray` of per-display dicts:

```
[
  { "Display Identifier": "<displayUUID>",
    "Spaces": [
      { "ManagedSpaceID": <UInt64>, "type": <Int>, ... },
      ...
    ]
  },
  ...
]
```

- `type == 0` (`kCGSSpaceUser`) → user desktop. We include only these.
- `type == 4` (fullscreen-app Space) and `type == 2` (system) → excluded in v1.

### 2. `DesktopEnumerator.swift` (new, pure-ish)

```swift
struct DesktopEntry {
    let spaceID: CGSSpaceID
    let displayUUID: String
    let indexInDisplay: Int     // 1-based
}

enum DesktopEnumerator {
    /// User-space desktops on the screen showing the overlay,
    /// in Mission Control order (1-based index).
    static func desktopsForCurrentScreen(screen: NSScreen) -> [DesktopEntry]
}
```

Implementation:
1. Read `CGSCopyManagedDisplaySpaces(CGSMainConnectionID())`.
2. Find the entry whose `Display Identifier` matches the screen's UUID
   (`CGDisplayCreateUUIDFromDisplayID(displayID)` formatted).
3. Filter `Spaces` to `type == 0`.
4. Number them 1..N in array order.

If the lookup fails (display not found, empty result), return `[]`.

### 3. `DesktopLabel.swift` (new, pure)

```swift
enum DesktopLabel {
    static func label(index: Int, storedName: String?) -> String {
        let name = storedName ?? "Desktop \(index)"
        return "\(index)  \(name)"
    }
}
```

Pure; unit-tested.

### 4. `SpaceSwitcher.swift` (new)

```swift
enum SpaceSwitcher {
    static func switchTo(spaceID: CGSSpaceID, displayUUID: String) {
        guard spaceID != CurrentSpace.id() else { return }   // already there
        CGSManagedDisplaySetCurrentSpace(
            CGSMainConnectionID(),
            displayUUID as CFString,
            spaceID
        )
    }
}
```

Single side-effecting call. Documented as private/unsupported.

### 5. `SwitcherModel` (extend)

```swift
struct DesktopVM: Identifiable {
    let id: CGSSpaceID        // spaceID
    let label: String
    let displayUUID: String
    let isCurrent: Bool
}

final class SwitcherModel: ObservableObject {
    // existing fields...
    @Published var desktops: [DesktopVM]

    init(apps: ..., selectedAppIndex: ..., desktops: [DesktopVM] = []) {
        self.desktops = desktops
        // existing init...
    }
}
```

### 6. `SwitcherController` (extend)

On `open()`:
1. Enumerate via `DesktopEnumerator.desktopsForCurrentScreen(screen:)`.
2. Resolve the current Space ID via `CurrentSpace.id()`.
3. Build `desktops: [DesktopVM]` with `label = DesktopLabel.label(index, name)`,
   `isCurrent = (id == currentSpaceID)`.
4. Assign to `model.desktops`.

New controller methods:

```swift
func clickDesktop(_ index: Int) {
    guard let model, !model.isRenaming else { return }
    guard model.desktops.indices.contains(index) else { return }
    let target = model.desktops[index]
    if target.isCurrent { return }                            // no-op
    close()
    SpaceSwitcher.switchTo(spaceID: target.id,
                           displayUUID: target.displayUUID)
}

func desktopNext() {
    guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
    let currentIdx = model.desktops.firstIndex { $0.isCurrent } ?? 0
    let next = SwitcherIndex.advance(currentIdx, count: model.desktops.count)
    clickDesktop(next)
}

func desktopPrev() {
    guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
    let currentIdx = model.desktops.firstIndex { $0.isCurrent } ?? 0
    let prev = SwitcherIndex.reverse(currentIdx, count: model.desktops.count)
    clickDesktop(prev)
}
```

### 7. `SwitcherView` (extend)

Replace `nameRow` with `desktopRow`:

```swift
@ViewBuilder
private var desktopRow: some View {
    if model.isRenaming {
        renameField                                           // unchanged
    } else if model.desktops.count >= 2 {
        HStack(spacing: 10) {
            ForEach(Array(model.desktops.enumerated()), id: \.element.id) { idx, d in
                desktopChip(d, isCurrent: d.isCurrent, onClick: { onClickDesktop(idx) })
                if d.isCurrent {
                    Button("Rename") { onBeginRename() }
                        .buttonStyle(.bordered)
                }
            }
        }
    } else {
        // Fallback: single name + Rename (existing behavior).
        legacyNameRow
    }
}
```

`desktopChip` is a clickable view (`Text(d.label).padding(...).background(...)
.onTapGesture { onClick() }`) with the current-chip highlight.

New view callback `onClickDesktop: (Int) -> Void` plumbed in from the
controller, alongside the existing window callbacks.

### 8. `SwitcherHotkey` (extend)

Add two key codes:

```swift
private static let leftBracketKeyCode: Int64 = 33   // [
private static let rightBracketKeyCode: Int64 = 30  // ]
```

And two callbacks:

```swift
var onDesktopPrev: (() -> Void)?
var onDesktopNext: (() -> Void)?
```

In the active-state branch, before the fall-through:

```swift
if cmdHeld && keyCode == Self.rightBracketKeyCode { fire(\.onDesktopNext); return nil }
if cmdHeld && keyCode == Self.leftBracketKeyCode  { fire(\.onDesktopPrev); return nil }
```

`cmdHeld` is already always true while `active`, but checking explicitly keeps
the dispatch readable. Both keys are swallowed.

Bracket keycodes are layout-dependent; v1 uses the US-layout codes 30/33,
matching how Tab/Esc/digits are hard-coded today.

### 9. `AppDelegate` (extend)

In `startSwitcher()`, wire the two new callbacks:

```swift
hotkey.onDesktopPrev = { [weak self] in self?.switcher.desktopPrev() }
hotkey.onDesktopNext = { [weak self] in self?.switcher.desktopNext() }
```

## Data flow

```
Cmd+Tab pressed
  -> SwitcherController.open()
  -> DesktopEnumerator + CurrentSpace.id() -> [DesktopVM]
  -> SwitcherView renders chip row (current highlighted, Rename next to it)

Mouse-click on chip i
  -> SwitcherView.onClickDesktop(i)
  -> controller.clickDesktop(i)
  -> if !isCurrent: close() then SpaceSwitcher.switchTo(...)

Cmd+] / Cmd+[
  -> SwitcherHotkey -> onDesktopNext / onDesktopPrev
  -> controller.desktopNext()/desktopPrev()
  -> clickDesktop on the wrapped target index
```

## Testing strategy

### Unit (TDD)
- **`DesktopLabel.label(index:storedName:)`**:
  - Named → `"1  Work"`.
  - Unnamed → `"3  Desktop 3"`.
  - Index `0` → still produces a label (defensive — not expected in practice).
- **`SwitcherHotkey`**: simulated keyDown for `[` and `]` with Cmd held
  triggers the right callback; without Cmd held passes through.
- Re-use existing `SwitcherIndex` tests for wrap-around (already covered).

### Integration / manual
- `DesktopEnumerator` and `SpaceSwitcher` touch private CGS — verified by
  manual smoke:
  1. With three named desktops, open Cmd+Tab → all three chips appear with
     correct numbering; the current one is highlighted.
  2. Click a non-current chip → desktop switches; the menu-bar title (which
     already tracks active Space) updates.
  3. `Cmd+]` cycles forward, wraps; `Cmd+[` cycles backward, wraps.
  4. Single-desktop scenario: chip row hidden, Rename row falls back to legacy
     behavior.

## Open risks

1. **Private CGS instability** — same as for `CGSGetActiveSpace`. New symbols
   (`CGSCopyManagedDisplaySpaces`, `CGSManagedDisplaySetCurrentSpace`) have
   been stable across macOS versions for years (used by Yabai, Spaces.app,
   etc.) but are not Apple-supported. Code is annotated as such; if any call
   ever returns garbage or no-ops, the worst case is a hidden row and an
   inert `Cmd+]`.
2. **Bracket keycodes are US-layout-specific** — keycodes for `[`/`]` differ
   on some non-US keyboard layouts. Consistent with the rest of the hotkey
   handler, which uses raw US keycodes; revisit only if a user reports it.
3. **Display-UUID resolution** — matching the NSScreen to a `Display
   Identifier` in the CGS dict relies on
   `CGDisplayCreateUUIDFromDisplayID`; if mapping fails, the row is empty
   (graceful degradation).
