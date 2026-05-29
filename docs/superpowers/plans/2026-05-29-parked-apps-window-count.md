# Parked Apps, Window-Count Badges, and Minimized Windows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the Cmd+Tab switcher, show Cmd+H-hidden and window-less ("ghost") apps as small dimmed "parked" icons with a window-count badge (Tab-skipped, click-to-activate), and show Cmd+M-minimized windows in the selected app's window row as smaller gray placeholders that un-minimize on select.

**Architecture:** A pure `WindowClassifier` (active vs parked) plus a pure per-PID real-window counter in `DesktopAppList` make the decisions testable. An AX-backed `MinimizedWindows` helper isolates the Accessibility calls (count, list, restore). `DesktopAppEnumerator` orchestrates: count real windows per PID, AX-probe the zero-real PIDs for minimized windows, classify, and append Cmd+H apps. The view renders parked icons (badge) and minimized thumbnails distinctly.

**Tech Stack:** Swift 5, SwiftUI, AppKit, CoreGraphics, ScreenCaptureKit; private CGS via `@_silgen_name`; Accessibility (`AXUIElement`); XCTest.

**Branch:** `feature/desktop-chip-row` (current). HEAD at `c850c20` (the spec commit). Entering test count: **47**.

**Spec:** `docs/superpowers/specs/2026-05-29-parked-apps-window-count-design.md`.

---

## Conventions

- **Build/test:** `xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS'`. Pass = `** TEST SUCCEEDED **`.
- Run `xcodegen generate` after **creating** a file (so the target picks it up).
- The CoreSimulator out-of-date warning at xcodebuild start is harmless — ignore.
- Commit message via `/tmp/msg.txt` + `git commit -F /tmp/msg.txt` (heredoc-in-`$()` is unreliable with backticks/apostrophes in this shell).
- Co-author trailer: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

---

## Task 1: `WindowClassifier` (pure, TDD)

**Files:**
- Create: `Sources/Nook/Switcher/WindowClassifier.swift`
- Create: `Tests/NookTests/WindowClassifierTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/NookTests/WindowClassifierTests.swift`:

```swift
import XCTest
@testable import Nook

final class WindowClassifierTests: XCTestCase {
    private func input(real: Int, minimized: Int, hidden: Bool) -> WindowClassifier.ClassifierInput {
        WindowClassifier.ClassifierInput(pid: 42,
                                         realWindowCount: real,
                                         minimizedWindowCount: minimized,
                                         isHidden: hidden)
    }

    func test_hidden_isParkedWithItsWindowCount() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 3, minimized: 0, hidden: true)),
                       .parked(windowCount: 3))
    }

    func test_hidden_withZeroWindows_isParkedZero() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 0, minimized: 0, hidden: true)),
                       .parked(windowCount: 0))
    }

    func test_hasRealWindows_isActive() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 2, minimized: 0, hidden: false)),
                       .active)
    }

    func test_onlyMinimizedWindows_isActive() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 0, minimized: 1, hidden: false)),
                       .active)
    }

    func test_noRealNoMinimizedNotHidden_isParkedZero() {
        XCTAssertEqual(WindowClassifier.classify(input(real: 0, minimized: 0, hidden: false)),
                       .parked(windowCount: 0))
    }
}
```

- [ ] **Step 2: Run tests to confirm the compile failure**

```sh
xcodegen generate
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "error:|cannot find" | tail -5
```

Expected: `cannot find 'WindowClassifier' in scope`.

- [ ] **Step 3: Create `WindowClassifier.swift`**

```swift
import Foundation

/// Pure decision: is an app "active" (Tab-navigable, normal icon) or "parked"
/// (Cmd+H-hidden or window-less; small dimmed icon with a count badge)?
enum WindowClassifier {
    struct ClassifierInput: Equatable {
        let pid: pid_t
        let realWindowCount: Int       // windows passing the real-window bar
        let minimizedWindowCount: Int  // from AX kAXMinimized
        let isHidden: Bool             // Cmd+H (NSRunningApplication.isHidden)
    }

    enum AppClass: Equatable {
        case active
        case parked(windowCount: Int)
    }

    static func classify(_ input: ClassifierInput) -> AppClass {
        if input.isHidden {
            return .parked(windowCount: input.realWindowCount)
        }
        if input.realWindowCount > 0 || input.minimizedWindowCount > 0 {
            return .active
        }
        return .parked(windowCount: 0)
    }
}
```

- [ ] **Step 4: Regenerate + run tests, expect pass**

```sh
xcodegen generate
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: **52 tests** (47 + 5 new), `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

`/tmp/msg.txt`:
```
feat: add WindowClassifier (active vs parked, TDD)

Pure decision used by the switcher app row: Cmd+H apps and window-less
apps become parked (small dimmed icon + window-count badge, Tab-skipped);
apps with any real or minimized window stay active. Window count for a
parked Cmd+H app is the caller-supplied real-window count; ghost-only
parked apps report 0.
```
```sh
git add Sources/Nook/Switcher/WindowClassifier.swift Tests/NookTests/WindowClassifierTests.swift
git commit -F /tmp/msg.txt
```

---

## Task 2: `RawAppWindow.frame` + `DesktopAppList.realWindowCounts` (pure, TDD)

**Files:**
- Modify: `Sources/Nook/Switcher/DesktopAppList.swift`
- Modify: `Tests/NookTests/DesktopAppListTests.swift`

- [ ] **Step 1: Add the failing tests**

Open `Tests/NookTests/DesktopAppListTests.swift`. Update the `win` helper to accept a frame, and append the new tests. The helper becomes:

```swift
    private func win(_ pid: pid_t,
                     layer: Int = 0,
                     onScreen: Bool = true,
                     windowID: CGWindowID? = nil,
                     frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)) -> RawAppWindow {
        RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen, windowID: windowID, frame: frame)
    }
```

Append these tests inside the class:

```swift
    // --- realWindowCounts ---

    func test_realWindowCounts_countsLayer0InAllowedSetMeetingMinSize() {
        let bounds = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        let input = [
            win(10, windowID: 101, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
            win(10, windowID: 102, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
            win(20, windowID: 201, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
        ]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101, 102, 201],
                                                     visibleBounds: bounds,
                                                     minSize: CGSize(width: 80, height: 80))
        XCTAssertEqual(counts[10], 2)
        XCTAssertEqual(counts[20], 1)
    }

    func test_realWindowCounts_excludesTinyOffscreenNonZeroLayerOutOfSet() {
        let bounds = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        let input = [
            win(10, windowID: 101, frame: CGRect(x: 0, y: 0, width: 10, height: 10)),     // too small
            win(10, windowID: 102, frame: CGRect(x: 9000, y: 9000, width: 200, height: 200)), // off bounds
            win(10, layer: 3, windowID: 103, frame: CGRect(x: 0, y: 0, width: 200, height: 200)), // non-zero layer
            win(10, windowID: 104, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),    // not in allowed set
            win(10, windowID: 105, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),    // OK
        ]
        let counts = DesktopAppList.realWindowCounts(from: input,
                                                     allowedWindowIDs: [101, 102, 103, 105],
                                                     visibleBounds: bounds,
                                                     minSize: CGSize(width: 80, height: 80))
        XCTAssertEqual(counts[10], 1) // only windowID 105 qualifies
    }

    func test_realWindowCounts_emptyWhenNothingQualifies() {
        let counts = DesktopAppList.realWindowCounts(from: [win(10, windowID: 101, frame: CGRect(x: 0, y: 0, width: 5, height: 5))],
                                                     allowedWindowIDs: [101],
                                                     visibleBounds: CGRect(x: 0, y: 0, width: 2000, height: 2000),
                                                     minSize: CGSize(width: 80, height: 80))
        XCTAssertTrue(counts.isEmpty)
    }
```

- [ ] **Step 2: Run tests to confirm the compile failure**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "error:|cannot find" | tail -5
```

Expected: errors about the `frame:` argument and `realWindowCounts`.

- [ ] **Step 3: Update `DesktopAppList.swift`**

Add `frame` to `RawAppWindow` (default `.zero` so existing non-test call sites keep compiling) and add `realWindowCounts`. The full file:

```swift
import CoreGraphics
import Foundation

struct RawAppWindow: Equatable {
    let ownerPID: pid_t
    let layer: Int
    let isOnScreen: Bool
    let windowID: CGWindowID?
    let frame: CGRect

    init(ownerPID: pid_t,
         layer: Int,
         isOnScreen: Bool,
         windowID: CGWindowID? = nil,
         frame: CGRect = .zero) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.windowID = windowID
        self.frame = frame
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

    /// Same shape, but filters to windows whose ID is in `allowedWindowIDs`.
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

    /// Per-PID count of "real" windows: layer 0, windowID in `allowedWindowIDs`,
    /// frame at least `minSize`, and intersecting `visibleBounds`. PIDs with no
    /// qualifying window are absent from the result (no zero entries).
    static func realWindowCounts(from windows: [RawAppWindow],
                                 allowedWindowIDs: Set<CGWindowID>,
                                 visibleBounds: CGRect,
                                 minSize: CGSize) -> [pid_t: Int] {
        var counts: [pid_t: Int] = [:]
        for window in windows where window.layer == 0 {
            guard let id = window.windowID, allowedWindowIDs.contains(id) else { continue }
            guard window.frame.width >= minSize.width,
                  window.frame.height >= minSize.height,
                  window.frame.intersects(visibleBounds) else { continue }
            counts[window.ownerPID, default: 0] += 1
        }
        return counts
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

- [ ] **Step 4: Run tests, expect pass**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -5
```

Expected: **55 tests** (52 + 3 new), `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

`/tmp/msg.txt`:
```
feat: add frame to RawAppWindow and DesktopAppList.realWindowCounts

realWindowCounts computes the per-PID count of windows that pass the same
real-window bar as the window row (layer 0, in the Space's allowed set,
>= 80x80, intersecting the displays). Used to classify apps as active vs
parked, and to size the parked window-count badge. RawAppWindow gains a
frame (default .zero) so the counter has geometry to filter on; the
existing appPIDs variants and their tests are unchanged.
```
```sh
git add Sources/Nook/Switcher/DesktopAppList.swift Tests/NookTests/DesktopAppListTests.swift
git commit -F /tmp/msg.txt
```

---

## Task 3: `MinimizedWindows` (AX helper)

**Files:**
- Create: `Sources/Nook/Switcher/MinimizedWindows.swift`

No unit tests (AX/CGS, integration-only).

- [ ] **Step 1: Create the file**

```swift
import AppKit
import ApplicationServices
import CoreGraphics

/// One minimized (Cmd+M) window of an app, resolved to a CGWindowID by
/// matching the AX window against the CGWindowList entry for the same PID.
struct MinimizedWindow: Equatable {
    let windowID: CGWindowID   // 0 if no CGWindowList match was found
    let title: String
    let frame: CGRect
    let appName: String
}

/// Accessibility-backed queries about an app's minimized windows. All calls
/// are synchronous and rely on the Accessibility grant the app already holds.
enum MinimizedWindows {
    /// Fast count of windows with kAXMinimized == true for `pid`.
    static func count(forPID pid: pid_t) -> Int {
        axWindows(forPID: pid).filter { isMinimized($0) }.count
    }

    /// Minimized windows of `pid`, each resolved (best-effort) to a CGWindowID
    /// via frame/title matching against CGWindowList.
    static func windows(forPID pid: pid_t) -> [MinimizedWindow] {
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
        let cgWindows = cgWindowList(forPID: pid)
        return axWindows(forPID: pid)
            .filter { isMinimized($0) }
            .map { axWin in
                let title = axTitle(axWin)
                let frame = axFrame(axWin)
                let windowID = matchWindowID(title: title, frame: frame, in: cgWindows)
                return MinimizedWindow(windowID: windowID ?? 0,
                                       title: title,
                                       frame: frame,
                                       appName: appName)
            }
    }

    /// Un-minimize the AX window matching `info` (kAXMinimized = false), then
    /// raise it and activate the app.
    static func restore(_ info: WindowInfo, pid: pid_t) {
        let candidates = axWindows(forPID: pid)
        // Prefer an exact title match, else nearest origin.
        let target = candidates.first(where: { axTitle($0) == info.title && !info.title.isEmpty })
            ?? candidates.min(by: {
                originDistance(axFrame($0), info.frame) < originDistance(axFrame($1), info.frame)
            })
        if let target {
            AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    // MARK: - AX plumbing

    private static func axWindows(forPID pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success,
              let number = value as? Bool else { return false }
        return number
    }

    private static func axTitle(_ window: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String else { return "" }
        return title
    }

    private static func axFrame(_ window: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
           let posValue, CFGetTypeID(posValue) == AXValueGetTypeID() {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
        }
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - CGWindowList match

    private struct CGWin { let id: CGWindowID; let title: String; let frame: CGRect }

    private static func cgWindowList(forPID pid: pid_t) -> [CGWin] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let p = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid_t(p) == pid,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
            let title = (info[kCGWindowName as String] as? String) ?? ""
            let frame: CGRect = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            return CGWin(id: CGWindowID(number), title: title, frame: frame)
        }
    }

    private static func matchWindowID(title: String, frame: CGRect, in cgWindows: [CGWin]) -> CGWindowID? {
        if let byFrame = cgWindows.first(where: { framesEqual($0.frame, frame) }) { return byFrame.id }
        if !title.isEmpty, let byTitle = cgWindows.first(where: { $0.title == title }) { return byTitle.id }
        return cgWindows.first?.id
    }

    private static func framesEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance && abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.size.width - b.size.width) <= tolerance && abs(a.size.height - b.size.height) <= tolerance
    }

    private static func originDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.origin.x - b.origin.x, dy = a.origin.y - b.origin.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
```

- [ ] **Step 2: Regenerate + build**

```sh
xcodegen generate
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Tests (no regression)**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -3
```

Expected: 55 tests pass.

- [ ] **Step 4: Commit**

`/tmp/msg.txt`:
```
feat: add MinimizedWindows AX helper

count(forPID:) reports kAXMinimized window count; windows(forPID:) returns
each minimized window resolved (best-effort) to a CGWindowID via CGWindowList
frame/title matching; restore(_:pid:) clears kAXMinimized on the matched AX
window, raises it, and activates the app. Isolates all the Accessibility
calls for the parked-apps / minimized-windows feature.
```
```sh
git add Sources/Nook/Switcher/MinimizedWindows.swift
git commit -F /tmp/msg.txt
```

---

## Task 4: Model fields (`SwitcherApp`, `SwitcherWindow`)

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherModels.swift`

No tests. The new fields default so existing constructor call sites keep compiling.

- [ ] **Step 1: Edit `SwitcherModels.swift`**

Change `SwitcherApp` and `SwitcherWindow` to:

```swift
struct SwitcherApp: Identifiable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    let isHidden: Bool          // Cmd+H — still needed for unhide-on-click
    var isParked: Bool = false  // small dimmed icon + badge + Tab-skip
    var windowCount: Int = 0    // badge value (parked only)
    var id: pid_t { pid }
}

struct SwitcherWindow: Identifiable {
    let windowID: CGWindowID
    let title: String
    let info: WindowInfo
    let pid: pid_t
    var image: CGImage?
    var isMinimized: Bool = false   // smaller + gray + un-minimize on select
    var id: CGWindowID { windowID }
}
```

Leave `DesktopVM` and `SwitcherModel` unchanged.

- [ ] **Step 2: Build (existing call sites still compile via defaults)**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. `SwitcherApp(pid:name:icon:isHidden:)` and `SwitcherWindow(windowID:title:info:pid:image:)` continue to work because the new fields have defaults.

- [ ] **Step 3: Tests**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -3
```

Expected: 55 tests pass.

- [ ] **Step 4: Commit**

`/tmp/msg.txt`:
```
feat: add isParked/windowCount to SwitcherApp and isMinimized to SwitcherWindow

Defaulted fields so existing constructors keep compiling; populated by the
enumerator (parked apps) and the window loader (minimized windows) in the
following tasks.
```
```sh
git add Sources/Nook/Switcher/SwitcherModels.swift
git commit -F /tmp/msg.txt
```

---

## Task 5: `DesktopAppEnumerator` — classify active vs parked

**Files:**
- Modify: `Sources/Nook/Switcher/DesktopAppEnumerator.swift`

No unit tests (live CGS/AX). The pure pieces it composes are already tested (Tasks 1, 2).

- [ ] **Step 1: Rewrite `appsOnSpace`, the fallback in `currentDesktopApps`, `allSpacesWindows` (add frame), and `hiddenRunningApps` (carry parked flags)**

Replace the whole file with:

```swift
import AppKit
import CoreGraphics

enum DesktopAppEnumerator {
    private static let minWindowSize = CGSize(width: 80, height: 80)

    /// Apps on the current desktop: active apps (z-order, frontmost first) then
    /// parked apps (Cmd+H or window-less), each parked icon carrying a window
    /// count. Excludes this process.
    static func currentDesktopApps() -> [SwitcherApp] {
        if let currentSpaceID = CurrentSpace.id() {
            return appsOnSpace(currentSpaceID)
        }
        // Fallback when CGS can't tell us the current Space: on-screen apps as
        // active, Cmd+H apps as parked. (No ghost detection on this rare path.)
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = onScreenWindows()
        let pids = DesktopAppList.appPIDs(from: raw, frontmostPID: frontmostPID)
        let active = pids.compactMap { activeApp(pid: $0) }
        return active + parkedHiddenApps()
    }

    /// Apps on `spaceID`: active apps first, parked apps appended.
    static func appsOnSpace(_ spaceID: CGSSpaceID) -> [SwitcherApp] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let raw = allSpacesWindows()
        let allowed = WindowsOnSpace.windowIDs(on: spaceID)
        let visibleBounds = DisplayBounds.union()
        let orderedPIDs = DesktopAppList.appPIDs(from: raw,
                                                 frontmostPID: frontmostPID,
                                                 allowedWindowIDs: allowed)
        let realCounts = DesktopAppList.realWindowCounts(from: raw,
                                                         allowedWindowIDs: allowed,
                                                         visibleBounds: visibleBounds,
                                                         minSize: minWindowSize)

        var active: [SwitcherApp] = []
        var parked: [SwitcherApp] = []
        for pid in orderedPIDs {
            let realCount = realCounts[pid] ?? 0
            let minimizedCount = realCount > 0 ? 0 : MinimizedWindows.count(forPID: pid)
            let input = WindowClassifier.ClassifierInput(pid: pid,
                                                         realWindowCount: realCount,
                                                         minimizedWindowCount: minimizedCount,
                                                         isHidden: false)
            switch WindowClassifier.classify(input) {
            case .active:
                if let app = activeApp(pid: pid) { active.append(app) }
            case .parked(let count):
                if let app = parkedApp(pid: pid, windowCount: count, isHidden: false) {
                    parked.append(app)
                }
            }
        }

        // Cmd+H apps (sourced from NSWorkspace — their windows don't reliably
        // report a Space). De-dup against anything already added.
        let already = Set((active + parked).map(\.pid))
        let hidden = parkedHiddenApps().filter { !already.contains($0.pid) }

        return active + (parked + hidden).sorted { $0.name < $1.name }
    }

    // MARK: - App builders

    private static func activeApp(pid: pid_t) -> SwitcherApp? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return SwitcherApp(pid: pid, name: app.localizedName ?? "", icon: app.icon,
                           isHidden: app.isHidden, isParked: false, windowCount: 0)
    }

    private static func parkedApp(pid: pid_t, windowCount: Int, isHidden: Bool) -> SwitcherApp? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return SwitcherApp(pid: pid, name: app.localizedName ?? "", icon: app.icon,
                           isHidden: isHidden, isParked: true, windowCount: windowCount)
    }

    /// Cmd+H-hidden regular apps as parked apps, badge = their real-sized window
    /// count (PID-wide CGWindowList, since hidden windows don't report a Space).
    private static func parkedHiddenApps() -> [SwitcherApp] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter {
                $0.isHidden && $0.activationPolicy == .regular &&
                $0.processIdentifier > 0 && $0.processIdentifier != selfPID
            }
            .compactMap { app -> SwitcherApp? in
                let count = realSizedWindowCount(forPID: app.processIdentifier)
                return SwitcherApp(pid: app.processIdentifier, name: app.localizedName ?? "",
                                   icon: app.icon, isHidden: true, isParked: true, windowCount: count)
            }
    }

    /// Count of an app's layer-0 windows that meet the min-size bar, regardless
    /// of Space or on-screen state (used for the Cmd+H badge).
    private static func realSizedWindowCount(forPID pid: pid_t) -> Int {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        var count = 0
        for info in infoList {
            guard let p = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid_t(p) == pid else { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            guard layer == 0 else { continue }
            let frame: CGRect = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            if frame.width >= minWindowSize.width && frame.height >= minWindowSize.height { count += 1 }
        }
        return count
    }

    // MARK: - Window enumeration

    private static func onScreenWindows() -> [RawAppWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let visibleBounds = DisplayBounds.union()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != selfPID else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let frame: CGRect = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            let onScreen = frame == .zero ? true : frame.intersects(visibleBounds)
            let windowID: CGWindowID? = (info[kCGWindowNumber as String] as? NSNumber)
                .map { CGWindowID($0.uint32Value) }
            return RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: onScreen,
                                windowID: windowID, frame: frame)
        }
    }

    private static func allSpacesWindows() -> [RawAppWindow] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infoList.compactMap { info in
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != selfPID else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let frame: CGRect = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            let windowID: CGWindowID? = (info[kCGWindowNumber as String] as? NSNumber)
                .map { CGWindowID($0.uint32Value) }
            return RawAppWindow(ownerPID: pid, layer: layer, isOnScreen: true,
                                windowID: windowID, frame: frame)
        }
    }
}
```

- [ ] **Step 2: Regenerate + build**

```sh
xcodegen generate
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Tests**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -3
```

Expected: 55 tests pass.

- [ ] **Step 4: Commit**

`/tmp/msg.txt`:
```
feat: classify desktop apps into active and parked groups

appsOnSpace now counts real windows per PID (DesktopAppList.realWindowCounts),
AX-probes the zero-real PIDs for minimized windows, and runs WindowClassifier
to split apps into active (z-order, frontmost first) and parked (Cmd+H or
window-less, with a window-count badge value). Cmd+H apps are appended from
NSWorkspace with a PID-wide real-sized window count. allSpacesWindows /
onScreenWindows now carry window frames for the real-window filter.
```
```sh
git add Sources/Nook/Switcher/DesktopAppEnumerator.swift
git commit -F /tmp/msg.txt
```

---

## Task 6: `SwitcherController` — minimized windows + parked navigation

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherController.swift`

No unit tests.

- [ ] **Step 1: Generalize Tab-skip from `isHidden` to `isParked`**

Rename `nextNonHiddenIndex(in:from:forward:)` to `nextActiveIndex(in:from:forward:)` and key it on `isParked`. Replace the method and its two callers (`advance`, `reverse`) so the body reads `if !apps[idx].isParked { return idx }`. The method:

```swift
    /// Tab navigation skips parked apps. Falls back to a normal wrap-step if
    /// every app in the list is parked.
    private func nextActiveIndex(in apps: [SwitcherApp],
                                 from currentIndex: Int,
                                 forward: Bool) -> Int {
        guard !apps.isEmpty else { return currentIndex }
        var idx = currentIndex
        for _ in 0..<apps.count {
            idx = forward
                ? SwitcherIndex.advance(idx, count: apps.count)
                : SwitcherIndex.reverse(idx, count: apps.count)
            if !apps[idx].isParked { return idx }
        }
        return forward
            ? SwitcherIndex.advance(currentIndex, count: apps.count)
            : SwitcherIndex.reverse(currentIndex, count: apps.count)
    }
```

In `advance()` and `reverse()`, change the call from `nextNonHiddenIndex(...)` to `nextActiveIndex(...)` (same arguments).

- [ ] **Step 2: `clickApp` un-hide guard reads `isHidden` (already does — no change needed). Verify only.**

`clickApp(_:)` already calls `running.unhide()` when `app.isHidden`. Leave as-is. (Parked ghost apps aren't hidden, so they just `activate()`.)

- [ ] **Step 3: Append minimized windows in `loadWindows`**

Replace `loadWindows(forAppIndex:onSpace:)` with a version that fetches the selected app's minimized windows (sync AX) and keeps them appended after the real windows through the async thumbnail updates:

```swift
    private func loadWindows(forAppIndex appIndex: Int, onSpace spaceID: CGSSpaceID) {
        guard let model, model.apps.indices.contains(appIndex) else { return }
        generation += 1
        let token = generation
        let pid = model.apps[appIndex].pid

        // Minimized windows are synchronous (AX) and render as gray placeholders.
        let minimized = MinimizedWindows.windows(forPID: pid).map { m in
            SwitcherWindow(windowID: m.windowID, title: m.title,
                           info: WindowInfo(windowID: m.windowID, title: m.title,
                                            frame: m.frame, appName: m.appName),
                           pid: pid, image: nil, isMinimized: true)
        }
        // Show minimized immediately so the row reflects the app even before
        // the SC fetch lands; keep prior real windows visible until it does.
        model.windows = model.windows.filter { !$0.isMinimized } + minimized

        Task { [weak self] in
            let scWindows = (try? await WindowEnumerator.filteredSCWindows(forPID: pid,
                                                                          onSpace: spaceID)) ?? []
            guard let self, self.generation == token, let model = self.model else { return }
            var built: [SwitcherWindow] = scWindows.map { scWindow in
                let info = WindowEnumerator.info(from: scWindow)
                return SwitcherWindow(windowID: scWindow.windowID, title: info.title,
                                      info: info, pid: pid, image: nil, isMinimized: false)
            }
            model.windows = built + minimized
            for (index, scWindow) in scWindows.enumerated() {
                let image = try? await ThumbnailCapturer.capture(scWindow)
                guard self.generation == token, let model = self.model,
                      built.indices.contains(index) else { return }
                built[index].image = image
                model.windows = built + minimized
            }
        }
    }
```

- [ ] **Step 4: Restore minimized windows on select**

Add a small helper and route the three window-activation sites (`clickWindow`, `selectWindow(number:)`, and the `.window` case in `commit`) through it:

```swift
    /// Activate the chosen window: un-minimize if it's a minimized entry,
    /// otherwise AX-raise it normally.
    private func activateChosenWindow(_ win: SwitcherWindow) {
        if win.isMinimized {
            MinimizedWindows.restore(win.info, pid: win.pid)
        } else {
            WindowActivator.activate(win.info, pid: win.pid)
        }
    }
```

Then:
- In `clickWindow(_:)`: replace `WindowActivator.activate(win.info, pid: win.pid)` with `activateChosenWindow(win)`.
- In `selectWindow(number:)`: same replacement.
- In `commit()` `.window(let index)` case: replace with `activateChosenWindow(win)` (after `close()`, as today).

- [ ] **Step 5: Build**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Tests**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -3
```

Expected: 55 tests pass.

- [ ] **Step 7: Commit**

`/tmp/msg.txt`:
```
feat: show minimized windows and skip parked apps in the controller

loadWindows appends the selected app's minimized windows (MinimizedWindows,
gray placeholders) after its real windows. Tab navigation skips parked apps
(nextActiveIndex on isParked, generalizing the old hidden-only skip).
Selecting a window routes through activateChosenWindow: minimized entries
un-minimize via MinimizedWindows.restore, real windows AX-raise as before.
```
```sh
git add Sources/Nook/Switcher/SwitcherController.swift
git commit -F /tmp/msg.txt
```

---

## Task 7: `SwitcherView` — parked badge + minimized thumbnail

**Files:**
- Modify: `Sources/Nook/Switcher/SwitcherView.swift`

No unit tests.

- [ ] **Step 1: Parked icon + count badge in `appIcon`**

Replace `appIcon(_:selected:onClick:)` with a version keyed on `isParked` (was `isHidden`) that adds a count badge:

```swift
    @ViewBuilder
    private func appIcon(_ app: SwitcherApp, selected: Bool, onClick: @escaping () -> Void) -> some View {
        // Parked apps (Cmd+H or window-less) render one size smaller, faint bg,
        // lower opacity, with a window-count badge — they read as "parked,
        // click to restore" and Tab skips them.
        let iconSize: CGFloat = app.isParked ? 40 : 64
        let pad: CGFloat = app.isParked ? 8 : 10
        let background: Color = app.isParked
            ? Color.white.opacity(0.08)
            : (selected ? Color.white.opacity(0.25) : Color.clear)
        Group {
            if let image = app.icon {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.white)
            }
        }
        .frame(width: iconSize, height: iconSize)
        .padding(pad)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(app.isParked ? 0.55 : 1.0)
        .overlay(alignment: .topTrailing) {
            if app.isParked {
                Text("\(app.windowCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Circle().fill(Color.black.opacity(0.8)))
                    .offset(x: 6, y: -6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
    }
```

- [ ] **Step 2: Minimized thumbnail styling in `windowThumb`**

Replace `windowThumb(_:selected:index:)` so minimized windows render smaller with a gray background:

```swift
    @ViewBuilder
    private func windowThumb(_ win: SwitcherWindow, selected: Bool, index: Int) -> some View {
        let thumbW: CGFloat = win.isMinimized ? 130 : 200
        let thumbH: CGFloat = win.isMinimized ? 85 : 130
        VStack(spacing: 6) {
            Group {
                if let image = win.image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.gray.opacity(win.isMinimized ? 0.5 : 0.3))
                        .overlay(Image(systemName: win.isMinimized ? "macwindow.badge.minus" : "macwindow")
                            .foregroundStyle(.white))
                }
            }
            .frame(width: thumbW, height: thumbH)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(numberedTitle(win, index: index))
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: thumbW)
        }
        .padding(8)
        .background(selected ? Color.white.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovering in if hovering { onHoverWindow(index) } }
        .onTapGesture { onClickWindow(index) }
    }
```

- [ ] **Step 3: Build**

```sh
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Debug -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Tests**

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|TEST SUCCEEDED|FAILED" | tail -3
```

Expected: 55 tests pass.

- [ ] **Step 5: Commit**

`/tmp/msg.txt`:
```
feat: parked-app count badge and minimized-window thumbnail styling

appIcon keys on isParked (40px, faint bg, 0.55 opacity) and overlays a small
dark count badge (top-right) showing windowCount. windowThumb renders
minimized windows at 130x85 with a darker gray placeholder and a
macwindow.badge.minus glyph to distinguish them from real windows.
```
```sh
git add Sources/Nook/Switcher/SwitcherView.swift
git commit -F /tmp/msg.txt
```

---

## Task 8: End-to-end install + manual verification

**Files:** none (build / install / verify).

- [ ] **Step 1: Build Release + install + launch**

```sh
killall Nook 2>/dev/null || true
rm -rf build/dev
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Release \
    -derivedDataPath build/dev -destination 'platform=macOS' \
    CODE_SIGN_STYLE=Manual 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | grep -v Simulator | tail -3
rm -rf /Applications/Nook.app
ditto build/dev/Build/Products/Release/Nook.app /Applications/Nook.app
open /Applications/Nook.app
pgrep -lf "/Applications/Nook.app" | head -1
```

Expected: `** BUILD SUCCEEDED **` and a running pid.

- [ ] **Step 2: Manual checklist (DO NOT execute — hand to the user)**

> 1. Acrobat with no document open → appears as a small dimmed parked icon with a "0" badge; Tab skips it; clicking it activates Acrobat.
> 2. Cmd+H an app that has 2 windows → it appears parked with a "2" badge; clicking un-hides it.
> 3. Cmd+M one window of an app that also has a visible window → the app stays active and Tab-reachable; its window row shows the normal thumbnail plus a smaller gray (badge-minus) minimized thumbnail; selecting the minimized one (arrow/number/click) un-minimizes and raises it.
> 4. An app whose only window is minimized → still Tab-reachable; its single gray minimized thumbnail restores on select.
> 5. Active apps and normal windows behave exactly as before (no regression to Tab cycling, number keys, arrows, desktop chips).

- [ ] **Step 3: (after user PASS) mark complete.** No commit (feature already committed across Tasks 1–7).

---

## Self-review

**1. Spec coverage**

| Spec item | Task |
|---|---|
| Window classes real/minimized/ghost | 2 (real count), 3 (minimized), 5 (ghost = 0 real & 0 min) |
| App classes active/parked | 1 (classifier), 5 (orchestration) |
| Parked = Cmd+H or ghost-only; minimized-only = active | 1 (rules), 5 |
| Count badge (ghost 0, Cmd+H = window count) | 1 (count in AppClass), 5 (Cmd+H PID-wide count), 7 (badge view) |
| Parked: small, dimmed, Tab-skip, click-activate | 6 (Tab-skip), 7 (style), existing `clickApp` (activate/unhide) |
| Minimized windows shown smaller + gray, un-minimize on select | 6 (load + restore), 7 (style) |
| `MinimizedWindows` AX helper, reuse WindowMatcher idea | 3 |
| Model fields `isParked`/`windowCount`/`isMinimized` | 4 |
| Testing: WindowClassifier + realWindowCounts unit; rest manual | 1, 2, 8 |

No gaps.

**2. Placeholder scan** — no TBD/TODO; every code step shows complete code; every command has an expected result.

**3. Type consistency** — `WindowClassifier.ClassifierInput(pid:realWindowCount:minimizedWindowCount:isHidden:)` and `AppClass.parked(windowCount:)` are used identically in Tasks 1 and 5. `DesktopAppList.realWindowCounts(from:allowedWindowIDs:visibleBounds:minSize:)` defined in Task 2, called in Task 5. `MinimizedWindows.count(forPID:)` / `.windows(forPID:)` / `.restore(_:pid:)` and `MinimizedWindow(windowID:title:frame:appName:)` defined in Task 3, consumed in Tasks 5 (count) and 6 (windows/restore). `SwitcherApp.isParked/windowCount` and `SwitcherWindow.isMinimized` defined in Task 4, populated in Task 5/6, read in Tasks 6/7. `nextActiveIndex` replaces `nextNonHiddenIndex` consistently in Task 6 (definition + both callers). `activateChosenWindow` defined and used at three sites in Task 6. All consistent.
