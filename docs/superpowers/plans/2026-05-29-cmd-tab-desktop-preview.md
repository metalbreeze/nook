# Cmd+Tab Desktop Preview Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn keyboard nav of the Cmd+Tab desktop chip row into a **preview** action that swaps the overlay's apps + windows to the target desktop without changing the macOS active Space. Add two key aliases (`` Cmd+` ``, `` Cmd+Shift+` ``) and a `Cmd+Shift+<digit>` shortcut. Releasing Cmd commits the Space switch (unless a window has been picked, which wins). Mouse-clicking a chip stays decisive (close + switch).

**Architecture:** Add one more private CGS binding (`CGSCopySpacesForWindows`) and a thin `WindowsOnSpace` helper that returns the windowID set for a given Space. Extend `DesktopAppEnumerator` and `WindowEnumerator` with per-Space variants. Replace `SwitcherCommit`'s `.noop` + `didNavigateDesktop` mechanism with a `.switchSpace` case driven by `previewedSpaceID != realSpaceID`. `DesktopVM` swaps its single `isCurrent` flag for two — `isPreviewed` (drives the existing solid fill) and `isReal` (drives a new outlined border) — so the chip row can show both at once. New controller `previewDesktop(at:)` / `previewDesktop(byNumber:)` re-flag the desktops, refresh apps + windows for the previewed Space, and never call `SpaceSwitcher` (the actual switch happens on Cmd release).

**Tech Stack:** Swift 5, SwiftUI, AppKit, CoreGraphics, ScreenCaptureKit; private CGS / SkyLight via `@_silgen_name`; XCTest.

**Branch:** `feature/desktop-chip-row` (already checked out; HEAD at `3dc1fec docs: add design spec for Cmd+Tab desktop preview model`).

**Spec:** `docs/superpowers/specs/2026-05-29-cmd-tab-desktop-preview-design.md`.

---

## Conventions used in this plan

- **XcodeGen regeneration:** Run `xcodegen generate` whenever you add a new source or test file. Existing-file edits don't need a regen.
- **Build/test command:** `xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS'`. Existing test count entering this plan is **43**.
- **CoreSimulator out-of-date warning** at xcodebuild start is harmless — ignore.
- **Commit messages:** if heredoc-in-`$(cat <<'EOF' ... EOF)` trips your shell (apostrophes / backticks), write the same plain text to `/tmp/msg.txt` and use `git commit -F /tmp/msg.txt`.
- **Co-author trailer:** `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

---

## Task 1: `DesktopAppList` windowID variant (TDD)

**Files:**
- Modify: `Sources/Nook/Switcher/DesktopAppList.swift`
- Modify: `Sources/Nook/Switcher/DesktopAppEnumerator.swift` (one-line `RawAppWindow` constructor update — non-functional)
- Modify: `Tests/NookTests/DesktopAppListTests.swift` (extend with 3 new tests)

- [ ] **Step 1: Write the failing tests**

Open `Tests/NookTests/DesktopAppListTests.swift`. Replace the current `private func win` helper and add 3 new tests; the final file looks like this:

```swift
import XCTest
@testable import Nook

final class DesktopAppListTests: XCTestCase {
    private func win(_ pid: pid_t,
                     layer: Int = 0,
                     onScreen: Bool = true,
                     windowID: CGWindowID? = nil) -> RawAppWindow {
        RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen, windowID: windowID)
    }

    func test_dedupsAndPreservesZOrder() {
        let input = [win(10), win(20), win(10), win(30)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10, 20, 30])
    }

    func test_excludesNonZeroLayerAndOffScreen() {
        let input = [win(10), win(20, layer: 25), win(30, onScreen: false)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10])
    }

    func test_movesFrontmostToFront() {
        let input = [win(20), win(30), win(10)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 10), [10, 20, 30])
    }

    func test_frontmostNotInListLeavesOrderUnchanged() {
        let input = [win(20), win(30)]
        XCTAssertEqual(DesktopAppList.appPIDs(from: input, frontmostPID: 99), [20, 30])
    }

    // --- new variant: filter by allowed windowID set ---

    func test_allowedWindowIDsFiltersOutMissing() {
        let input = [
            win(10, windowID: 101),
            win(20, windowID: 202),
            win(30, windowID: 303),
        ]
        XCTAssertEqual(
            DesktopAppList.appPIDs(from: input,
                                   frontmostPID: 0,
                                   allowedWindowIDs: [101, 303]),
            [10, 30]
        )
    }

    func test_allowedWindowIDsKeepsOnePIDEvenIfMultipleWindowsAllowed() {
        let input = [
            win(10, windowID: 101),
            win(10, windowID: 102),
            win(20, windowID: 202),
        ]
        XCTAssertEqual(
            DesktopAppList.appPIDs(from: input,
                                   frontmostPID: 20,
                                   allowedWindowIDs: [101, 102, 202]),
            [20, 10]
        )
    }

    func test_allowedWindowIDsSkipsNilWindowIDEvenIfPIDMatches() {
        // RawAppWindow with no windowID (legacy default) is excluded from the
        // allowed-set variant — the variant requires the window to be known.
        let input = [
            win(10),                     // windowID nil
            win(20, windowID: 202),
        ]
        XCTAssertEqual(
            DesktopAppList.appPIDs(from: input,
                                   frontmostPID: 0,
                                   allowedWindowIDs: [202]),
            [20]
        )
    }
}
```

- [ ] **Step 2: Run tests to confirm compile failure**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "error:|cannot find" | tail -5
```

Expected: `cannot find ... in scope` errors mentioning `RawAppWindow`'s `windowID` argument and `allowedWindowIDs:`.

- [ ] **Step 3: Update `DesktopAppList.swift`**

Replace the entire file with:

```swift
import CoreGraphics
import Foundation

struct RawAppWindow: Equatable {
    let ownerPID: pid_t
    let layer: Int
    let isOnScreen: Bool
    let windowID: CGWindowID?

    init(ownerPID: pid_t,
         layer: Int,
         isOnScreen: Bool,
         windowID: CGWindowID? = nil) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.windowID = windowID
    }
}

enum DesktopAppList {
    /// De-duplicated app PIDs that have at least one normal (layer 0), on-screen
    /// window, in first-appearance (z-order) order, with the current app first.
    static func appPIDs(from windows: [RawAppWindow], frontmostPID: pid_t) -> [pid_t] {
        var seen = Set<pid_t>()
        var ordered: [pid_t] = []
        for window in windows where window.layer == 0 && window.isOnScreen {
            if seen.insert(window.ownerPID).inserted {
                ordered.append(window.ownerPID)
            }
        }
        return reorderFrontmost(ordered, frontmostPID: frontmostPID)
    }

    /// Same shape, but filters to windows whose ID is in `allowedWindowIDs`
    /// (used to enumerate the apps on a non-current Space, where the windowID
    /// allow-set comes from `WindowsOnSpace`). `isOnScreen` is not consulted —
    /// the allow-set is the authoritative membership signal for non-current
    /// Spaces. Windows whose `windowID` is `nil` are skipped (caller forgot to
    /// populate them).
    static func appPIDs(from windows: [RawAppWindow],
                        frontmostPID: pid_t,
                        allowedWindowIDs: Set<CGWindowID>) -> [pid_t] {
        var seen = Set<pid_t>()
        var ordered: [pid_t] = []
        for window in windows where window.layer == 0 {
            guard let id = window.windowID, allowedWindowIDs.contains(id) else { continue }
            if seen.insert(window.ownerPID).inserted {
                ordered.append(window.ownerPID)
            }
        }
        return reorderFrontmost(ordered, frontmostPID: frontmostPID)
    }

    private static func reorderFrontmost(_ ordered: [pid_t], frontmostPID: pid_t) -> [pid_t] {
        var result = ordered
        if let index = result.firstIndex(of: frontmostPID), index != 0 {
            result.remove(at: index)
            result.insert(frontmostPID, at: 0)
        }
        return result
    }
}
```

- [ ] **Step 4: Update `DesktopAppEnumerator.swift` to pass `windowID`**

Open `Sources/Nook/Switcher/DesktopAppEnumerator.swift`. In `onScreenWindows()`, change the trailing `return RawAppWindow(...)` to include the windowID:

OLD (line 38):
```swift
            return RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen)
```

NEW:
```swift
            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
                .map(CGWindowID.init)
            return RawAppWindow(ownerPID: pid,
                                layer: layer,
                                isOnScreen: onScreen,
                                windowID: windowID)
```

(The existing `currentDesktopApps()` flow does not use `windowID` — populating it is harmless and keeps the struct consistent for future enumerators that do filter on it.)

- [ ] **Step 5: Run tests to confirm they pass**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: `Test Suite 'All tests' passed`, **46 tests** executed, 0 failures.

(Math: 43 prior tests + 3 new tests in `DesktopAppListTests` = 46.)

- [ ] **Step 6: Commit**

```sh
git add Sources/Nook/Switcher/DesktopAppList.swift \
        Sources/Nook/Switcher/DesktopAppEnumerator.swift \
        Tests/NookTests/DesktopAppListTests.swift
git commit -F /tmp/msg.txt   # or heredoc -m if your shell tolerates it
```

Commit message body (write to `/tmp/msg.txt` first):

```
feat: add allowed-windowID variant to DesktopAppList

The existing current-Space path uses `isOnScreen` as the membership signal.
For the upcoming preview-on-other-desktops feature we will need to filter
by an explicit windowID allow-set obtained from CGSCopySpacesForWindows.
Extend RawAppWindow with an optional windowID (default nil for backwards
compat) and add a second appPIDs variant that filters by allowed IDs.

DesktopAppEnumerator.onScreenWindows() now populates windowID too; the
current-Space path keeps using the isOnScreen variant.

3 new unit tests cover the new path; the 4 existing tests for the old
variant are preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 2: `CGSCopySpacesForWindows` binding + `WindowsOnSpace`

**Files:**
- Modify: `Sources/Nook/Switcher/CGSSpace.swift`
- Create: `Sources/Nook/Switcher/WindowsOnSpace.swift`

No unit tests (private CGS, integration-only).

- [ ] **Step 1: Add the binding to `CGSSpace.swift`**

Open `Sources/Nook/Switcher/CGSSpace.swift`. After the existing `CGSManagedDisplaySetCurrentSpace` declaration (before `enum CurrentSpace`), append:

```swift
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ mask: UInt64,
    _ windowIDs: CFArray
) -> CFArray
```

Five `@_silgen_name` symbols total now: `CGSMainConnectionID`, `CGSGetActiveSpace`, `CGSCopyManagedDisplaySpaces`, `CGSManagedDisplaySetCurrentSpace`, `CGSCopySpacesForWindows`.

- [ ] **Step 2: Create `WindowsOnSpace.swift`**

Create `Sources/Nook/Switcher/WindowsOnSpace.swift`:

```swift
import CoreGraphics
import Foundation

/// Window IDs currently belonging to a given Space, including off-screen ones
/// (i.e. windows on other desktops). Uses the private CGSCopySpacesForWindows
/// API to ask, per window, "which Spaces is this on?", then keeps the windows
/// whose Space set contains the target.
///
/// Returns an empty set if CGS returns garbage. Best-effort, unsupported.
enum WindowsOnSpace {
    /// Mask passed to CGSCopySpacesForWindows. 0x7 includes user, fullscreen,
    /// and system Spaces — the union "all Spaces" used by Yabai and friends.
    private static let allSpacesMask: UInt64 = 0x7

    static func windowIDs(on spaceID: CGSSpaceID) -> Set<CGWindowID> {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }
        let connection = CGSMainConnectionID()
        var result: Set<CGWindowID> = []
        for info in infoList {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            let windowID = CGWindowID(number)
            let cfIDs = [NSNumber(value: windowID)] as CFArray
            let spaces = CGSCopySpacesForWindows(connection, allSpacesMask, cfIDs) as NSArray
            for case let n as NSNumber in spaces where n.uint64Value == spaceID {
                result.insert(windowID)
                break
            }
        }
        return result
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project and build**

```sh
xcodegen generate
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 46 tests pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/Nook/Switcher/CGSSpace.swift Sources/Nook/Switcher/WindowsOnSpace.swift
git commit -F /tmp/msg.txt
```

Commit message:

```
feat: add CGSCopySpacesForWindows binding and WindowsOnSpace helper

Adds the fifth private CGS @_silgen_name symbol. WindowsOnSpace.windowIDs(on:)
asks the WindowServer for each window's Space membership (all-Spaces mask
0x7), and returns the IDs of windows that belong to a target spaceID. Used
by the upcoming per-Space app/window enumeration paths; on its own this
helper has no callers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 3: `DesktopAppEnumerator.appsOnSpace`

**Files:**
- Modify: `Sources/Nook/Switcher/DesktopAppEnumerator.swift`

No unit tests (private CGS).

- [ ] **Step 1: Add `appsOnSpace(_:)` to `DesktopAppEnumerator`**

Open `Sources/Nook/Switcher/DesktopAppEnumerator.swift`. Add a new static function (and a new private helper that returns `RawAppWindow`s irrespective of `.optionOnScreenOnly`). Place these right after `currentDesktopApps()`. The full file after the edit:

```swift
import AppKit
import CoreGraphics

enum DesktopAppEnumerator {
    /// Apps with at least one normal window on the current desktop, current app
    /// first, in window z-order. Excludes this process. No Screen Recording needed.
    static func currentDesktopApps() -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = onScreenWindows()
        let pids = DesktopAppList.appPIDs(from: raw, frontmostPID: frontmostPID)
        return pids.compactMap(makeApp(pid:))
    }

    /// Apps with at least one normal window on `spaceID`, in window z-order,
    /// with the current frontmost app first if it has a window there. Uses
    /// `WindowsOnSpace` (private CGS) to compute the allow-set; the frontmost
    /// signal is the same as for `currentDesktopApps()` and is only useful when
    /// `spaceID` is the active Space (otherwise the frontmost is unlikely to
    /// own a window there, so the call falls through to z-order).
    static func appsOnSpace(_ spaceID: CGSSpaceID) -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = allSpacesWindows()
        let allowed = WindowsOnSpace.windowIDs(on: spaceID)
        let pids = DesktopAppList.appPIDs(from: raw,
                                          frontmostPID: frontmostPID,
                                          allowedWindowIDs: allowed)
        return pids.compactMap(makeApp(pid:))
    }

    /// On-screen (current Space) windows, with off-screen mid-Space-switch
    /// windows filtered out via the visible-bounds intersection.
    private static func onScreenWindows() -> [RawAppWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let visibleBounds = DisplayBounds.union()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != selfPID else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let onScreen: Bool
            if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
               let frame = CGRect(dictionaryRepresentation: boundsDict) {
                onScreen = frame.intersects(visibleBounds)
            } else {
                onScreen = true
            }
            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
                .map(CGWindowID.init)
            return RawAppWindow(ownerPID: pid,
                                layer: layer,
                                isOnScreen: onScreen,
                                windowID: windowID)
        }
    }

    /// All windows across all Spaces. `isOnScreen` is set to `true` so callers
    /// using the `allowedWindowIDs` variant don't accidentally reject by the
    /// legacy filter. This process is excluded.
    private static func allSpacesWindows() -> [RawAppWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != selfPID else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
                .map(CGWindowID.init)
            return RawAppWindow(ownerPID: pid,
                                layer: layer,
                                isOnScreen: true,
                                windowID: windowID)
        }
    }

    private static func makeApp(pid: pid_t) -> SwitcherApp? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return SwitcherApp(pid: pid, name: app.localizedName ?? "", icon: app.icon)
    }
}
```

- [ ] **Step 2: Build**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full test suite**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 46 tests pass.

- [ ] **Step 4: Commit**

```sh
git add Sources/Nook/Switcher/DesktopAppEnumerator.swift
git commit -F /tmp/msg.txt
```

Message:

```
feat: enumerate apps on a specific Space via WindowsOnSpace

DesktopAppEnumerator.appsOnSpace(_ spaceID:) reads all windows (no
.optionOnScreenOnly), filters them to those WindowsOnSpace claims belong
to the target Space, and delegates to the new DesktopAppList variant for
PID de-duplication and frontmost reorder. currentDesktopApps() is
unchanged (still uses the on-screen path).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 4: `WindowEnumerator.filteredSCWindows(forPID:onSpace:)`

**Files:**
- Modify: `Sources/Nook/Windows/WindowEnumerator.swift`

No unit tests.

- [ ] **Step 1: Add the new variant**

Open `Sources/Nook/Windows/WindowEnumerator.swift`. Add a new static function right below the existing `filteredSCWindows(forPID:)`. The relevant section (insert between `filteredSCWindows(forPID:)` and `info(from:)`):

```swift
    /// Same as `filteredSCWindows(forPID:)` but the on-Space filter is the
    /// explicit `spaceID` rather than the active Space. Used by the preview
    /// path in the Cmd+Tab switcher.
    static func filteredSCWindows(forPID pid: pid_t,
                                  onSpace spaceID: CGSSpaceID) async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let allowed = WindowsOnSpace.windowIDs(on: spaceID)
        let visibleBounds = DisplayBounds.union()
        let raw = content.windows.map { rawWindow(from: $0, onSpaceIDs: allowed) }
        let allowedIDs = Set(WindowFilter.visibleWindows(from: raw,
                                                          frontmostPID: pid,
                                                          visibleBounds: visibleBounds).map(\.windowID))
        return content.windows.filter { allowedIDs.contains($0.windowID) }
    }

    private static func rawWindow(from window: SCWindow, onSpaceIDs: Set<CGWindowID>) -> RawWindow {
        RawWindow(windowID: window.windowID,
                  ownerPID: pid_t(window.owningApplication?.processID ?? 0),
                  layer: window.windowLayer,
                  isOnScreen: onSpaceIDs.contains(window.windowID),
                  title: window.title ?? "",
                  appName: window.owningApplication?.applicationName ?? "",
                  frame: window.frame)
    }
```

Notes on the differences from the existing variant:
- `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)` — `onScreenWindowsOnly: false` so SC returns windows on other Spaces too.
- The allow-set comes from `WindowsOnSpace`, not from `currentSpaceWindowIDs()`.
- The visible-bounds intersection check (still applied by `WindowFilter.visibleWindows`) will eliminate any window whose frame is outside the active display set — that's still correct for previewed Spaces because windows on those Spaces also live within the display rects.

The existing `filteredSCWindows(forPID:)` and `currentSpaceWindowIDs()` are unchanged (they remain the path used by the Ctrl+Down snapshot).

- [ ] **Step 2: Build**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Tests**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 46 tests pass.

- [ ] **Step 4: Commit**

```sh
git add Sources/Nook/Windows/WindowEnumerator.swift
git commit -F /tmp/msg.txt
```

Message:

```
feat: add per-Space variant to WindowEnumerator.filteredSCWindows

filteredSCWindows(forPID:onSpace:) returns the SCWindows for `pid` whose
ID is in WindowsOnSpace.windowIDs(on: spaceID). Uses onScreenWindowsOnly:
false so SC returns off-Space windows too. The existing forPID:-only
variant (still consumed by the Ctrl+Down snapshot) is unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 5: Two-tier highlight refactor (model + view + controller readers)

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherModels.swift`
- Modify: `Sources/Nook/Switcher/SwitcherController.swift`
- Modify: `Sources/Nook/Switcher/SwitcherView.swift`

No tests change in this task — it is a structural refactor, not a behavior change. After this task all 46 existing tests still pass; the chip row visually picks up a thin outline on the current chip but stays functionally identical.

- [ ] **Step 1: Update `SwitcherModels.swift`**

Open `Sources/Nook/Switcher/SwitcherModels.swift`. Replace the file with:

```swift
import AppKit
import Combine
import CoreGraphics

struct SwitcherApp: Identifiable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    var id: pid_t { pid }
}

struct SwitcherWindow: Identifiable {
    let windowID: CGWindowID
    let title: String
    let info: WindowInfo
    let pid: pid_t
    var image: CGImage?
    var id: CGWindowID { windowID }
}

/// View model for one desktop chip in the Cmd+Tab overlay.
///
/// Two flags so the chip row can convey both "what the user is looking at"
/// (isPreviewed → solid fill) and "where macOS actually is right now"
/// (isReal → outlined border). They coincide on overlay open.
struct DesktopVM: Identifiable, Equatable {
    let id: CGSSpaceID            // also the Space ID
    let label: String             // e.g. "1  Work" or "3  Desktop 3"
    let displayUUID: String
    let isPreviewed: Bool
    let isReal: Bool
}

final class SwitcherModel: ObservableObject {
    @Published var apps: [SwitcherApp]
    @Published var selectedAppIndex: Int
    @Published var windows: [SwitcherWindow]
    @Published var selectedWindowIndex: Int   // -1 = app-level (no window selected)
    @Published var desktopName: String
    @Published var isRenaming: Bool
    @Published var desktops: [DesktopVM]
    @Published var previewedSpaceID: CGSSpaceID?
    @Published var realSpaceID: CGSSpaceID?

    init(apps: [SwitcherApp], selectedAppIndex: Int, desktops: [DesktopVM] = []) {
        self.apps = apps
        self.selectedAppIndex = selectedAppIndex
        self.windows = []
        self.selectedWindowIndex = -1
        self.desktopName = DesktopNameStore.defaultName
        self.isRenaming = false
        self.desktops = desktops
        self.previewedSpaceID = nil
        self.realSpaceID = nil
    }
}
```

- [ ] **Step 2: Update `SwitcherController.swift` field reads and writes**

Open `Sources/Nook/Switcher/SwitcherController.swift`. Make the following targeted edits — leave every other method untouched.

(2a) In `open()`, replace the `desktopVMs` building block and add population of the two model space-IDs. The full `open()` becomes:

```swift
    func open() {
        didNavigateDesktop = false
        let apps = DesktopAppEnumerator.currentDesktopApps()
        guard !apps.isEmpty else { return }
        let currentSpaceID = CurrentSpace.id()
        spaceID = currentSpaceID
        let screen = NSScreen.main ?? NSScreen.screens.first
        let entries = screen.map { DesktopEnumerator.desktopsForCurrentScreen($0) } ?? []
        let desktopVMs: [DesktopVM] = entries.map { entry in
            let isCurrent = entry.spaceID == currentSpaceID
            return DesktopVM(
                id: entry.spaceID,
                label: DesktopLabel.label(
                    index: entry.indexInDisplay,
                    storedName: nameStore.storedName(for: entry.spaceID)
                ),
                displayUUID: entry.displayUUID,
                isPreviewed: isCurrent,
                isReal: isCurrent
            )
        }
        let model = SwitcherModel(apps: apps,
                                  selectedAppIndex: 0,
                                  desktops: desktopVMs)
        model.previewedSpaceID = currentSpaceID
        model.realSpaceID = currentSpaceID
        if let currentSpaceID {
            model.desktopName = nameStore.name(for: currentSpaceID)
        }
        self.model = model
        showWindow(model: model)
        loadWindows(forAppIndex: 0)
    }
```

(2b) In `clickDesktop(_:)`, change the no-op guard from `target.isCurrent` to `target.isReal`:

OLD:
```swift
        if target.isCurrent { return }      // no-op on the current chip
```

NEW:
```swift
        if target.isReal { return }      // already on this desktop
```

(2c) In `advanceToDesktop(at:)`, change:
- The early-return `if target.isCurrent` → `if target.isPreviewed`.
- The `map { vm in DesktopVM(... isCurrent: ...) }` → produces `isPreviewed: vm.id == target.id, isReal: vm.isReal` (the immediate-switch path still updates the macOS Space, so `isReal` should also move; but since we also set `model.realSpaceID = target.id` below, the easiest is to update both: `isPreviewed: vm.id == target.id, isReal: vm.id == target.id`).
- Add two lines to keep the model's space IDs in sync.

The full method becomes:

```swift
    private func advanceToDesktop(at index: Int) {
        guard let model else { return }
        guard model.desktops.indices.contains(index) else { return }
        let target = model.desktops[index]
        if target.isPreviewed { return }
        didNavigateDesktop = true
        spaceID = target.id
        model.previewedSpaceID = target.id
        model.realSpaceID = target.id
        model.desktopName = nameStore.name(for: target.id)
        model.desktops = model.desktops.map { vm in
            let isCurrent = vm.id == target.id
            return DesktopVM(id: vm.id,
                             label: vm.label,
                             displayUUID: vm.displayUUID,
                             isPreviewed: isCurrent,
                             isReal: isCurrent)
        }
        SpaceSwitcher.switchTo(spaceID: target.id, displayUUID: target.displayUUID)
    }
```

(2d) `desktopNext()` and `desktopPrev()` — change `$0.isCurrent` to `$0.isPreviewed`:

```swift
    func desktopNext() {
        guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
        let currentIdx = model.desktops.firstIndex(where: { $0.isPreviewed }) ?? 0
        let next = SwitcherIndex.advance(currentIdx, count: model.desktops.count)
        advanceToDesktop(at: next)
    }

    func desktopPrev() {
        guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
        let currentIdx = model.desktops.firstIndex(where: { $0.isPreviewed }) ?? 0
        let prev = SwitcherIndex.reverse(currentIdx, count: model.desktops.count)
        advanceToDesktop(at: prev)
    }
```

- [ ] **Step 3: Update `SwitcherView.swift`'s `desktopChip` and `desktopRow`**

Open `Sources/Nook/Switcher/SwitcherView.swift`. Two changes:

(3a) The `desktopRow` body currently iterates `model.desktops` and renders the Rename button when `desktop.isCurrent`. Change that condition to `desktop.isPreviewed`:

OLD (inside the ForEach in `desktopRow`):
```swift
                    if desktop.isCurrent {
                        Button("Rename") { onBeginRename() }
                            .buttonStyle(.bordered)
                    }
```

NEW:
```swift
                    if desktop.isPreviewed {
                        Button("Rename") { onBeginRename() }
                            .buttonStyle(.bordered)
                    }
```

(3b) The `desktopChip` body uses `desktop.isCurrent` for both the background fill and the tap-gesture gate. Replace it. The full `desktopChip` method becomes:

```swift
    @ViewBuilder
    private func desktopChip(_ desktop: DesktopVM, onClick: @escaping () -> Void) -> some View {
        Text(desktop.label)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(desktop.isPreviewed ? Color.white.opacity(0.25) : Color.clear)
            .overlay(
                Capsule()
                    .stroke(desktop.isReal ? Color.white.opacity(0.6) : Color.clear,
                            lineWidth: 1.5)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onHover { hovering in
                // Intentional: chip row stays visually calm; window thumbs already
                // provide hover feedback elsewhere.
                _ = hovering
            }
            .onTapGesture { if !desktop.isReal { onClick() } }
    }
```

- [ ] **Step 4: Build**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Tests**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 46 tests pass.

- [ ] **Step 6: Commit**

```sh
git add Sources/Nook/Switcher/SwitcherModels.swift \
        Sources/Nook/Switcher/SwitcherController.swift \
        Sources/Nook/Switcher/SwitcherView.swift
git commit -F /tmp/msg.txt
```

Message:

```
refactor: split DesktopVM.isCurrent into isPreviewed + isReal

Prepares the chip-row UI for showing both "what the user is looking at"
(isPreviewed, solid fill) and "where macOS is right now" (isReal,
outlined border) at once. On overlay open both flags coincide so the
visible behavior is unchanged.

SwitcherModel gains previewedSpaceID / realSpaceID fields (populated on
open() to the current Space). SwitcherController's open(), clickDesktop,
advanceToDesktop, desktopNext, and desktopPrev are adjusted to read and
write the new flag names. SwitcherView's desktopChip applies both flags
as a stacked solid + stroke style.

The bracket-immediate-switch behavior (advanceToDesktop still calls
SpaceSwitcher.switchTo) and didNavigateDesktop are preserved here;
Task 6 removes them in the move to the preview model.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 6: SwitcherCommit refactor + SwitcherController preview-mode behavior change

**This is the user-facing behavior change.** After this task, bracket keys preview rather than switch, and commit-on-release does the actual Space switch.

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherCommit.swift`
- Modify: `Tests/NookTests/SwitcherCommitTests.swift`
- Modify: `Sources/Nook/Switcher/SwitcherController.swift`

- [ ] **Step 1: Write the new tests first (TDD)**

Replace `Tests/NookTests/SwitcherCommitTests.swift` with:

```swift
import XCTest
@testable import Nook

final class SwitcherCommitTests: XCTestCase {
    private let s1: CGSSpaceID = 1001
    private let s2: CGSSpaceID = 1002
    private let uuid = "UUID-DISPLAY-A"

    // MARK: window has precedence over everything

    func test_validWindowIndex_isWindow_evenWhenPreviewMatchesReal() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: 0, windowCount: 3,
                previewedSpaceID: s1, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .window(0)
        )
    }

    func test_validWindowIndex_isWindow_evenWhenPreviewDiffersFromReal() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: 2, windowCount: 5,
                previewedSpaceID: s2, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .window(2)
        )
    }

    // MARK: switchSpace when previewed differs from real

    func test_previewDiffersFromReal_isSwitchSpace() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 0,
                previewedSpaceID: s2, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .switchSpace(s2, displayUUID: uuid)
        )
    }

    func test_previewDiffersFromReal_isSwitchSpace_evenWithOutOfRangeWindowIndex() {
        // Out-of-range selectedWindowIndex falls through to the preview check.
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: 5, windowCount: 3,
                previewedSpaceID: s2, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .switchSpace(s2, displayUUID: uuid)
        )
    }

    // MARK: app when no window selected and preview == real

    func test_noWindowSelected_previewEqualsReal_isApp() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 3,
                previewedSpaceID: s1, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .app
        )
    }

    // MARK: app when state is degenerate (nil previewed or real)

    func test_nilPreview_isApp() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 0,
                previewedSpaceID: nil, realSpaceID: s1, previewedDisplayUUID: uuid
            ),
            .app
        )
    }

    func test_nilReal_isApp() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 0,
                previewedSpaceID: s2, realSpaceID: nil, previewedDisplayUUID: uuid
            ),
            .app
        )
    }

    func test_nilUUID_isApp() {
        XCTAssertEqual(
            SwitcherCommit.resolve(
                selectedWindowIndex: -1, windowCount: 0,
                previewedSpaceID: s2, realSpaceID: s1, previewedDisplayUUID: nil
            ),
            .app
        )
    }
}
```

- [ ] **Step 2: Run tests to see them fail to compile (Intent.switchSpace missing, new signature missing)**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "error:" | head -10
```

Expected: errors about missing `Intent` cases and mismatched argument labels on `resolve(...)`.

- [ ] **Step 3: Rewrite `SwitcherCommit.swift`**

Replace `Sources/Nook/Switcher/SwitcherCommit.swift` with:

```swift
import Foundation

/// Resolves what the Cmd+Tab switcher should do on commit (Cmd release).
///
/// Order of precedence:
///   1. A valid `selectedWindowIndex` always wins → `.window(i)`.
///   2. If `previewedSpaceID != realSpaceID` (and we have a `displayUUID`),
///      the user committed via desktop preview → `.switchSpace`.
///   3. Otherwise → `.app` (activate the selected app on the real desktop).
enum SwitcherCommit {
    enum Intent: Equatable {
        case app
        case window(Int)
        case switchSpace(CGSSpaceID, displayUUID: String)
    }

    static func resolve(selectedWindowIndex: Int,
                        windowCount: Int,
                        previewedSpaceID: CGSSpaceID?,
                        realSpaceID: CGSSpaceID?,
                        previewedDisplayUUID: String?) -> Intent {
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

- [ ] **Step 4: Update `SwitcherController.swift` — full preview-mode wiring**

Open `Sources/Nook/Switcher/SwitcherController.swift`. The changes are all inside the existing class; line numbers are approximate.

(4a) **Remove** the `didNavigateDesktop` field (line ~11). The class top becomes:

```swift
@MainActor
final class SwitcherController {
    private var window: OverlayWindow?
    private var model: SwitcherModel?
    private var generation = 0
    private let nameStore = DesktopNameStore()
    private var spaceID: CGSSpaceID?
    var onDesktopRenamed: (() -> Void)?
```

(4b) **Update `open()`** — remove the `didNavigateDesktop = false` line (no longer exists), keep the rest of Task 5's `open()` body. The result:

```swift
    func open() {
        let apps = DesktopAppEnumerator.currentDesktopApps()
        guard !apps.isEmpty else { return }
        let currentSpaceID = CurrentSpace.id()
        spaceID = currentSpaceID
        let screen = NSScreen.main ?? NSScreen.screens.first
        let entries = screen.map { DesktopEnumerator.desktopsForCurrentScreen($0) } ?? []
        let desktopVMs: [DesktopVM] = entries.map { entry in
            let isCurrent = entry.spaceID == currentSpaceID
            return DesktopVM(
                id: entry.spaceID,
                label: DesktopLabel.label(
                    index: entry.indexInDisplay,
                    storedName: nameStore.storedName(for: entry.spaceID)
                ),
                displayUUID: entry.displayUUID,
                isPreviewed: isCurrent,
                isReal: isCurrent
            )
        }
        let model = SwitcherModel(apps: apps,
                                  selectedAppIndex: 0,
                                  desktops: desktopVMs)
        model.previewedSpaceID = currentSpaceID
        model.realSpaceID = currentSpaceID
        if let currentSpaceID {
            model.desktopName = nameStore.name(for: currentSpaceID)
            loadWindows(forAppIndex: 0, onSpace: currentSpaceID)
        }
        self.model = model
        showWindow(model: model)
    }
```

(Note: `loadWindows` is now called inside the `if let currentSpaceID` block because the per-Space variant needs a non-nil space ID. The trailing standalone `loadWindows(...)` call disappears.)

(4c) **Replace `advanceToDesktop(at:)` with `previewDesktop(at:)`** and add `previewDesktop(byNumber:)`. The block (after `clickDesktop(_:)` and before `desktopNext()`) becomes:

```swift
    /// Bracket-driven (and Cmd+Shift+digit-driven) preview: re-flags the chip
    /// row and reloads apps + windows for `target`, but does **not** call
    /// `SpaceSwitcher.switchTo`. The actual Space switch happens on commit
    /// (Cmd release) if `previewedSpaceID` still differs from `realSpaceID`.
    private func previewDesktop(at index: Int) {
        guard let model, !model.isRenaming else { return }
        guard model.desktops.indices.contains(index) else { return }
        let target = model.desktops[index]
        if target.isPreviewed { return }            // already viewing it

        spaceID = target.id                          // rename target follows preview
        model.previewedSpaceID = target.id
        model.desktopName = nameStore.name(for: target.id)
        model.desktops = model.desktops.map { vm in
            DesktopVM(id: vm.id,
                      label: vm.label,
                      displayUUID: vm.displayUUID,
                      isPreviewed: vm.id == target.id,
                      isReal: vm.isReal)
        }
        model.apps = DesktopAppEnumerator.appsOnSpace(target.id)
        model.selectedAppIndex = 0
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: 0, onSpace: target.id)
    }

    /// 1-based; `n` is the chip position in `model.desktops`. No-op if `n`
    /// exceeds the count.
    func previewDesktop(byNumber n: Int) {
        guard n >= 1, let model, model.desktops.indices.contains(n - 1) else { return }
        previewDesktop(at: n - 1)
    }
```

(4d) **Update `desktopNext()` and `desktopPrev()`** to call `previewDesktop`:

```swift
    func desktopNext() {
        guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
        let currentIdx = model.desktops.firstIndex(where: { $0.isPreviewed }) ?? 0
        let next = SwitcherIndex.advance(currentIdx, count: model.desktops.count)
        previewDesktop(at: next)
    }

    func desktopPrev() {
        guard let model, !model.isRenaming, model.desktops.count > 1 else { return }
        let currentIdx = model.desktops.firstIndex(where: { $0.isPreviewed }) ?? 0
        let prev = SwitcherIndex.reverse(currentIdx, count: model.desktops.count)
        previewDesktop(at: prev)
    }
```

(4e) **Rewrite `commit()`** to use the new `SwitcherCommit.resolve` signature and handle `.switchSpace`:

```swift
    func commit() {
        guard let model, !model.isRenaming else { return }
        let previewedUUID = model.desktops.first(where: { $0.isPreviewed })?.displayUUID
        let intent = SwitcherCommit.resolve(
            selectedWindowIndex: model.selectedWindowIndex,
            windowCount: model.windows.count,
            previewedSpaceID: model.previewedSpaceID,
            realSpaceID: model.realSpaceID,
            previewedDisplayUUID: previewedUUID
        )
        switch intent {
        case .window(let index):
            let win = model.windows[index]
            close()
            WindowActivator.activate(win.info, pid: win.pid)
        case .switchSpace(let target, let uuid):
            close()
            SpaceSwitcher.switchTo(spaceID: target, displayUUID: uuid)
        case .app:
            guard model.apps.indices.contains(model.selectedAppIndex) else { close(); return }
            let pid = model.apps[model.selectedAppIndex].pid
            close()
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }
```

(4f) **Rewrite `loadWindows(forAppIndex:)`** to take an explicit `onSpace:`:

```swift
    /// Loads the highlighted app's windows on `spaceID`, then captures thumbnails
    /// asynchronously. A generation token discards stale results when the user Tabs fast.
    private func loadWindows(forAppIndex appIndex: Int, onSpace spaceID: CGSSpaceID) {
        guard let model, model.apps.indices.contains(appIndex) else { return }
        generation += 1
        let token = generation
        let pid = model.apps[appIndex].pid
        model.windows = []
        Task { [weak self] in
            let scWindows = (try? await WindowEnumerator.filteredSCWindows(forPID: pid,
                                                                          onSpace: spaceID)) ?? []
            guard let self, self.generation == token, let model = self.model else { return }
            var built: [SwitcherWindow] = scWindows.map { scWindow in
                let info = WindowEnumerator.info(from: scWindow)
                return SwitcherWindow(windowID: scWindow.windowID, title: info.title,
                                      info: info, pid: pid, image: nil)
            }
            model.windows = built
            for (index, scWindow) in scWindows.enumerated() {
                let image = try? await ThumbnailCapturer.capture(scWindow)
                guard self.generation == token, let model = self.model,
                      built.indices.contains(index) else { return }
                built[index].image = image
                model.windows = built
            }
        }
    }
```

(4g) **Update `advance()` and `reverse()`** to pass `onSpace:`:

```swift
    func advance() {
        guard let model, !model.isRenaming, !model.apps.isEmpty,
              let spaceID = model.previewedSpaceID else { return }
        model.selectedAppIndex = SwitcherIndex.advance(model.selectedAppIndex, count: model.apps.count)
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: model.selectedAppIndex, onSpace: spaceID)
    }

    func reverse() {
        guard let model, !model.isRenaming, !model.apps.isEmpty,
              let spaceID = model.previewedSpaceID else { return }
        model.selectedAppIndex = SwitcherIndex.reverse(model.selectedAppIndex, count: model.apps.count)
        model.selectedWindowIndex = -1
        loadWindows(forAppIndex: model.selectedAppIndex, onSpace: spaceID)
    }
```

(4h) **No changes** to `windowLeft`, `windowRight`, `hoverWindow`, `clickWindow`, `selectWindow(number:)`, `clickDesktop` (already uses `isReal` from Task 5), `cancel`, `beginRename`, `finishRename`, `showWindow`, `close`. Re-read those after the edit to confirm.

- [ ] **Step 5: Build**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run tests**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: **47 tests** pass. (Pre-task count was 46; 7 existing `SwitcherCommit` tests removed, 8 new ones added → net +1. So 46 + 1 = 47.)

- [ ] **Step 7: Commit**

```sh
git add Sources/Nook/Switcher/SwitcherCommit.swift \
        Sources/Nook/Switcher/SwitcherController.swift \
        Tests/NookTests/SwitcherCommitTests.swift
git commit -F /tmp/msg.txt
```

Message:

```
feat: preview-on-bracket model for Cmd+Tab desktops

Bracket keys (and Cmd+Shift+digit, wired in Task 7) now PREVIEW a desktop
inside the overlay instead of immediately switching Space. The previewed
desktop's apps and windows are loaded via DesktopAppEnumerator.appsOnSpace
and WindowEnumerator.filteredSCWindows(forPID:onSpace:); the chip row
re-flags isPreviewed (solid fill) while isReal (outlined border) stays on
the macOS active Space.

On Cmd release, SwitcherCommit.resolve picks an Intent in order:
selected window > preview-differs-from-real > app. The .switchSpace case
calls SpaceSwitcher.switchTo with the previewed Space and its display.
The old .noop case and the didNavigateDesktop flag are gone.

Mouse click on a chip still closes + switches immediately. Esc / rename
behavior unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 7: `SwitcherHotkey` backtick + `Cmd+Shift+<digit>`

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherHotkey.swift`

No unit tests (CGEventTap integration).

- [ ] **Step 1: Add the new keycode + callback declarations**

Open `Sources/Nook/Switcher/SwitcherHotkey.swift`. Add a new callback property after `onDesktopNext` (around line 23):

```swift
    var onDesktopNumber: ((Int) -> Void)?
```

Add the backtick keycode constant after `rightBracketKeyCode` (around line 33):

```swift
    private static let backtickKeyCode: Int64 = 50   // `
```

- [ ] **Step 2: Handle backtick + Cmd+Shift+digit in `handle(...)`**

In the active branch of `handle(type:event:)`, add the new key paths. Place them appropriately:

(2a) **Right after** the existing right-bracket block (which ends with `fire(\.onDesktopNext); return nil`), add the backtick handling:

```swift
        if keyCode == Self.backtickKeyCode {
            if flags.contains(.maskShift) {
                fire(\.onDesktopNext)
            } else {
                fire(\.onDesktopPrev)
            }
            return nil
        }
```

(2b) **Right before** the existing digit block (`if let number = Self.digitKeyCodes[keyCode]`), add the Shift+digit intercept:

```swift
        if let number = Self.digitKeyCodes[keyCode], flags.contains(.maskShift) {
            let callback = onDesktopNumber
            DispatchQueue.main.async { callback?(number) }
            return nil
        }
```

The existing `if let number = Self.digitKeyCodes[keyCode]` block immediately below handles the bare-digit (Cmd-only) case for window selection. Order matters: the Shift+digit check must come first so it intercepts before the window-number path.

The full `handle()` method after these inserts looks like:

```swift
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let cmdHeld = flags.contains(.maskCommand)

        if type == .flagsChanged {
            if active && !cmdHeld {
                active = false
                fire(\.onCommit)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if !active {
            if keyCode == Self.tabKeyCode && cmdHeld {
                active = true
                fire(\.onOpen)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if keyCode == Self.tabKeyCode {
            if flags.contains(.maskShift) {
                fire(\.onReverse)
            } else {
                fire(\.onAdvance)
            }
            return nil
        }
        if keyCode == Self.leftKeyCode { fire(\.onWindowLeft); return nil }
        if keyCode == Self.rightKeyCode { fire(\.onWindowRight); return nil }
        if keyCode == Self.rightBracketKeyCode { fire(\.onDesktopNext); return nil }
        if keyCode == Self.leftBracketKeyCode { fire(\.onDesktopPrev); return nil }
        if keyCode == Self.backtickKeyCode {
            if flags.contains(.maskShift) {
                fire(\.onDesktopNext)
            } else {
                fire(\.onDesktopPrev)
            }
            return nil
        }
        if keyCode == Self.escKeyCode {
            active = false
            fire(\.onCancel)
            return nil
        }
        if let number = Self.digitKeyCodes[keyCode], flags.contains(.maskShift) {
            let callback = onDesktopNumber
            DispatchQueue.main.async { callback?(number) }
            return nil
        }
        if let number = Self.digitKeyCodes[keyCode] {
            let callback = onWindowNumber
            DispatchQueue.main.async { callback?(number) }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
```

- [ ] **Step 3: Build**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Tests**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: 47 tests pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/Nook/Switcher/SwitcherHotkey.swift
git commit -F /tmp/msg.txt
```

Message:

```
feat: backtick + Cmd+Shift+digit hotkeys for desktop preview

Adds keycode 50 (` on US layout): bare backtick is aliased to Cmd+[
(desktop prev), shifted backtick to Cmd+] (desktop next). Adds Shift+digit
1-9 (Cmd+Shift+<digit>) firing a new onDesktopNumber callback, ordered
before the existing Cmd+<digit> branch so Shift intercepts cleanly. All
new keys are swallowed in the active state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 8: AppDelegate wire `onDesktopNumber`

**Files:**
- Modify: `Sources/Nook/App/AppDelegate.swift`

- [ ] **Step 1: Add the new wiring line**

Open `Sources/Nook/App/AppDelegate.swift`. Inside `startSwitcher()`, after the line `hotkey.onDesktopNext = { [weak self] in self?.switcher.desktopNext() }`, add:

```swift
        hotkey.onDesktopNumber = { [weak self] n in self?.switcher.previewDesktop(byNumber: n) }
```

- [ ] **Step 2: Build + tests**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: `** BUILD SUCCEEDED **`, 47 tests pass.

- [ ] **Step 3: Commit**

```sh
git add Sources/Nook/App/AppDelegate.swift
git commit -F /tmp/msg.txt
```

Message:

```
feat: wire Cmd+Shift+<digit> to previewDesktop(byNumber:)

Connects SwitcherHotkey.onDesktopNumber to
SwitcherController.previewDesktop(byNumber:). Closes the wiring for the
desktop-preview feature; bracket keys, backtick, and shift+digit all route
to the same preview path in the controller.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 9: End-to-end install + manual verification

**Files:** none (build / install / verify only).

- [ ] **Step 1: Build a fresh Release and install to `/Applications`**

```sh
killall Nook 2>/dev/null || true
rm -rf build/dev
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Release \
    -derivedDataPath build/dev -destination 'platform=macOS' \
    CODE_SIGN_STYLE=Manual 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
rm -rf /Applications/Nook.app
ditto build/dev/Build/Products/Release/Nook.app /Applications/Nook.app
open /Applications/Nook.app
pgrep -lf "/Applications/Nook.app" | head -3
```

Expected: `** BUILD SUCCEEDED **`, then pgrep shows `/Applications/Nook.app/Contents/MacOS/Nook` is running.

- [ ] **Step 2: Manual E2E checklist (DO NOT run programmatically — hand to the user)**

The checklist is for the human user; report it back as a deliverable and wait for their PASS/FAIL.

> 1. Cmd+Tab on a 3+ desktop machine → chip row shows N chips with two-tier highlight (solid fill + outline on the current chip; they coincide on open).
> 2. Press `Cmd+]` → preview moves to next chip (solid fill follows, outline stays on the real-current chip). Apps row and windows row swap to that desktop's contents. **macOS Space does not switch.**
> 3. Press `Cmd+]` again → preview keeps walking. End wraps to chip 1.
> 4. Press `Cmd+[` → preview walks back; wraps the other way.
> 5. `` Cmd+` `` ≡ `Cmd+[`. `` Cmd+Shift+` `` ≡ `Cmd+]`.
> 6. `Cmd+Shift+2` → preview jumps to chip 2; `Cmd+Shift+5` on a 3-chip row is a no-op.
> 7. Preview a different desktop, **release Cmd** → macOS switches to that desktop (the outline catches up on next open). No app activation.
> 8. Preview a different desktop, then press `Cmd+3` → window 3 of the selected app on the previewed desktop activates; macOS auto-switches Space because the window lives there.
> 9. Mouse click a non-current chip → close + switch (unchanged decisive behavior).
> 10. `Esc` cancels: no Space switch, no app activation.
> 11. Single-desktop machine → chip row hidden, legacy name+Rename row renders; all new bindings are no-ops in that mode.
> 12. Rename mode → all new keys ignored.

- [ ] **Step 3: (After the user confirms PASS) Mark this task complete.**

No commit in this task — the feature is already on `feature/desktop-chip-row` ready to be merged into `main` by the regular `superpowers:finishing-a-development-branch` flow.

---

## Self-review

**1. Spec coverage**

| Spec section | Implemented in |
|---|---|
| Behavior: keyboard preview (Cmd+[, Cmd+], Cmd+\`, Cmd+Shift+\`) | Tasks 6, 7 |
| Behavior: Cmd+Shift+<digit> previews chip N (no-op when N exceeds count) | Tasks 6, 7, 8 |
| Behavior: Cmd+<digit> activates n-th window on previewed desktop | Task 6 (already existed; now uses preview's windows because `loadWindows` is per-Space) |
| Behavior: Commit on Cmd release with priority window > switchSpace > app | Task 6 (SwitcherCommit + commit()) |
| Behavior: Mouse click chip stays decisive | Task 5 (clickDesktop guard switched to isReal) |
| Layout: two-tier chip highlight (solid = previewed, outline = real) | Task 5 (View) |
| Single-desktop fallback unchanged | Task 5 (legacy branch untouched in View) |
| `CGSCopySpacesForWindows` binding | Task 2 |
| `WindowsOnSpace` helper | Task 2 |
| `DesktopAppList` windowID-set variant | Task 1 |
| `DesktopAppEnumerator.appsOnSpace` | Task 3 |
| `WindowEnumerator.filteredSCWindows(forPID:onSpace:)` | Task 4 |
| `SwitcherModel.previewedSpaceID / realSpaceID` + `DesktopVM` rename | Task 5 |
| `SwitcherCommit.Intent.switchSpace` + new resolve | Task 6 |
| `SwitcherController.previewDesktop(at:)` and `(byNumber:)` | Task 6 |
| `SwitcherHotkey` backtick + Shift+digit + `onDesktopNumber` | Task 7 |
| `AppDelegate` wiring | Task 8 |
| Testing: TDD on `DesktopAppList` variant | Task 1 |
| Testing: TDD on `SwitcherCommit.resolve` | Task 6 |
| Testing: manual E2E | Task 9 |
| Non-goals (no other displays, no fullscreen Spaces, no inline rename of non-preview) | Preserved by not changing those code paths |

No spec gaps.

**2. Placeholder scan** — no `TBD`/`TODO`/"handle edge cases" patterns; every code block is complete; every command has a concrete expected output.

**3. Type consistency** —
- `DesktopVM(id:label:displayUUID:isPreviewed:isReal:)` used identically in Tasks 5 and 6.
- `SwitcherCommit.resolve(selectedWindowIndex:windowCount:previewedSpaceID:realSpaceID:previewedDisplayUUID:)` used identically in tests (Task 6 Step 1) and `commit()` (Task 6 Step 4e).
- `Intent.switchSpace(CGSSpaceID, displayUUID: String)` declared in Task 6 Step 3 and unwrapped with the same labels in Task 6 Step 4e.
- `WindowsOnSpace.windowIDs(on:)` declared in Task 2 and called in Tasks 3 and 4.
- `DesktopAppList.appPIDs(from:frontmostPID:allowedWindowIDs:)` declared in Task 1 and called in Task 3.
- `loadWindows(forAppIndex:onSpace:)` signature consistent across `open()`, `advance()`, `reverse()`, `previewDesktop(at:)` (Task 6 Steps 4b, 4c, 4f, 4g).
- `previewDesktop(byNumber:)` signature consistent across Task 6 declaration and Task 8 wiring.
- `SwitcherHotkey.onDesktopNumber: ((Int) -> Void)?` declared in Task 7 and wired in Task 8.

All consistent.
