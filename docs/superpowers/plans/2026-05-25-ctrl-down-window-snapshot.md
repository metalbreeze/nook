# Ctrl+Down Current-Desktop Window Snapshot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar agent that intercepts Ctrl+Down, suppresses the native App Exposé, and shows a thumbnail-grid overlay of the focused app's visible windows on the current desktop only, with click-to-raise.

**Architecture:** Pure-logic units (hotkey predicate, window filter, AX window matcher) are unit-tested in isolation. System adapters (CGEventTap, ScreenCaptureKit enumeration + capture, Accessibility activation, SwiftUI/AppKit overlay) wrap those units and are verified manually. An `AppDelegate` wires them together as an `LSUIElement` agent.

**Tech Stack:** Swift 5 language mode (Swift 6.3 compiler), AppKit + SwiftUI, ScreenCaptureKit, ApplicationServices (Accessibility), CoreGraphics event taps. Project generated via XcodeGen. Tests in XCTest.

---

## File Structure

```
MyDefineShortcut/
├── project.yml                                   # XcodeGen spec (app + test target + scheme)
├── Resources/
│   └── Info.plist                                # LSUIElement, bundle metadata
├── Sources/MyDefineShortcut/
│   ├── main.swift                                # entry: NSApplication + .accessory policy
│   ├── App/AppDelegate.swift                     # menu bar + full wiring
│   ├── Hotkey/HotkeyMatcher.swift                # PURE: Ctrl+Down predicate (tested)
│   ├── Hotkey/HotkeyTap.swift                     # CGEventTap wrapper (manual)
│   ├── Windows/WindowModels.swift                # WindowInfo, RawWindow structs
│   ├── Windows/WindowFilter.swift                # PURE: current-desktop filter (tested)
│   ├── Windows/WindowEnumerator.swift            # SCShareableContent adapter (manual)
│   ├── Windows/ThumbnailCapturer.swift           # SCScreenshotManager adapter (manual)
│   ├── Activation/WindowMatcher.swift            # PURE: match WindowInfo→AX window (tested)
│   ├── Activation/WindowActivator.swift          # AX raise + activate (manual)
│   ├── Overlay/WindowThumbnail.swift             # view-model for a grid cell
│   ├── Overlay/SnapshotView.swift                # SwiftUI thumbnail grid
│   ├── Overlay/OverlayWindow.swift               # keyable borderless NSWindow subclass
│   ├── Overlay/OverlayController.swift           # NSWindow + NSHostingView management
│   └── Permissions/PermissionsManager.swift      # AX + Screen Recording checks
└── Tests/MyDefineShortcutTests/
    ├── WindowFilterTests.swift
    ├── HotkeyMatcherTests.swift
    └── WindowMatcherTests.swift
```

**Standard commands** (used throughout):

- Generate project: `xcodegen generate`
- Build: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
- Run tests: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
- Launch app: `open ./build/Build/Products/Debug/MyDefineShortcut.app`

> **Signing / permissions note:** The project signs ad-hoc (`CODE_SIGN_IDENTITY = "-"`) so it builds without an Apple Developer account. TCC permission grants (Accessibility, Screen Recording) key on the code signature, so an ad-hoc rebuild may require re-granting. To make grants persist across rebuilds, open the generated project in Xcode → target → Signing & Capabilities → select your Apple Development team, or set `DEVELOPMENT_TEAM` in `project.yml`.

---

## Task 1: Scaffold the Xcode project

**Files:**
- Create: `project.yml`
- Create: `Resources/Info.plist`
- Create: `Sources/MyDefineShortcut/main.swift`
- Create: `Sources/MyDefineShortcut/App/AppDelegate.swift`

- [ ] **Step 1: Write `project.yml`**

```yaml
name: MyDefineShortcut
options:
  bundleIdPrefix: com.metalbreeze
  createIntermediateGroups: true
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    ENABLE_HARDENED_RUNTIME: NO
    ENABLE_TESTABILITY: YES
targets:
  MyDefineShortcut:
    type: application
    platform: macOS
    sources:
      - Sources/MyDefineShortcut
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.metalbreeze.MyDefineShortcut
        INFOPLIST_FILE: Resources/Info.plist
        ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS: NO
  MyDefineShortcutTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/MyDefineShortcutTests
    dependencies:
      - target: MyDefineShortcut
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.metalbreeze.MyDefineShortcutTests
schemes:
  MyDefineShortcut:
    build:
      targets:
        MyDefineShortcut: all
        MyDefineShortcutTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - MyDefineShortcutTests
```

- [ ] **Step 2: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MyDefineShortcut</string>
    <key>CFBundleDisplayName</key>
    <string>MyDefineShortcut</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
```

- [ ] **Step 3: Write `Sources/MyDefineShortcut/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: Write a minimal `Sources/MyDefineShortcut/App/AppDelegate.swift`** (stub so the project builds; expanded in Task 12)

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                     accessibilityDescription: "Window Snapshot")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
```

- [ ] **Step 5: Generate and build**

Run: `xcodegen generate && xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Launch and confirm a menu-bar icon appears (no Dock icon)**

Run: `open ./build/Build/Products/Debug/MyDefineShortcut.app`
Expected: a window icon appears in the menu bar; clicking it shows a Quit item; no Dock icon. Then quit it from the menu.

- [ ] **Step 7: Commit**

```bash
git add project.yml Resources/Info.plist Sources/MyDefineShortcut/main.swift Sources/MyDefineShortcut/App/AppDelegate.swift
git commit -m "feat: scaffold MyDefineShortcut menu-bar app (XcodeGen)"
```

---

## Task 2: Window models + current-desktop filter (TDD)

**Files:**
- Create: `Sources/MyDefineShortcut/Windows/WindowModels.swift`
- Create: `Sources/MyDefineShortcut/Windows/WindowFilter.swift`
- Test: `Tests/MyDefineShortcutTests/WindowFilterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import MyDefineShortcut

final class WindowFilterTests: XCTestCase {
    private func raw(id: CGWindowID, pid: pid_t, layer: Int = 0, onScreen: Bool = true,
                     w: CGFloat = 800, h: CGFloat = 600, title: String = "T", app: String = "App") -> RawWindow {
        RawWindow(windowID: id, ownerPID: pid, layer: layer, isOnScreen: onScreen,
                  title: title, appName: app, frame: CGRect(x: 0, y: 0, width: w, height: h))
    }

    func test_keepsOnlyFrontmostAppWindows() {
        let input = [raw(id: 1, pid: 100), raw(id: 2, pid: 200), raw(id: 3, pid: 100)]
        let result = WindowFilter.visibleWindows(from: input, frontmostPID: 100)
        XCTAssertEqual(result.map(\.windowID), [1, 3])
    }

    func test_dropsOffScreenNonZeroLayerAndTinyWindows() {
        let input = [
            raw(id: 1, pid: 100),
            raw(id: 2, pid: 100, onScreen: false),
            raw(id: 3, pid: 100, layer: 25),
            raw(id: 4, pid: 100, w: 10, h: 10),
        ]
        let result = WindowFilter.visibleWindows(from: input, frontmostPID: 100)
        XCTAssertEqual(result.map(\.windowID), [1])
    }

    func test_countAndMetadataPreserved() {
        let input = [raw(id: 7, pid: 100, title: "Doc", app: "Safari")]
        let result = WindowFilter.visibleWindows(from: input, frontmostPID: 100)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Doc")
        XCTAssertEqual(result.first?.appName, "Safari")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `cannot find 'RawWindow' in scope` / `cannot find 'WindowFilter' in scope` (this is the red state).

- [ ] **Step 3: Write `WindowModels.swift`**

```swift
import CoreGraphics

struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let title: String
    let frame: CGRect
    let appName: String
}

struct RawWindow: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let layer: Int
    let isOnScreen: Bool
    let title: String
    let appName: String
    let frame: CGRect
}
```

- [ ] **Step 4: Write `WindowFilter.swift`**

```swift
import CoreGraphics

enum WindowFilter {
    static func visibleWindows(from windows: [RawWindow],
                               frontmostPID: pid_t,
                               minSize: CGSize = CGSize(width: 80, height: 80)) -> [WindowInfo] {
        windows
            .filter { $0.ownerPID == frontmostPID }
            .filter { $0.layer == 0 }
            .filter { $0.isOnScreen }
            .filter { $0.frame.width >= minSize.width && $0.frame.height >= minSize.height }
            .map { WindowInfo(windowID: $0.windowID, title: $0.title, frame: $0.frame, appName: $0.appName) }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`, 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyDefineShortcut/Windows/WindowModels.swift Sources/MyDefineShortcut/Windows/WindowFilter.swift Tests/MyDefineShortcutTests/WindowFilterTests.swift
git commit -m "feat: add window models and current-desktop window filter"
```

---

## Task 3: Hotkey matcher (TDD)

**Files:**
- Create: `Sources/MyDefineShortcut/Hotkey/HotkeyMatcher.swift`
- Test: `Tests/MyDefineShortcutTests/HotkeyMatcherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import MyDefineShortcut

final class HotkeyMatcherTests: XCTestCase {
    func test_matchesControlDownArrow() {
        XCTAssertTrue(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: [.maskControl]))
    }

    func test_rejectsWrongKeyCode() {
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 126, flags: [.maskControl]))
    }

    func test_rejectsControlPlusOtherModifier() {
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: [.maskControl, .maskShift]))
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: [.maskControl, .maskCommand]))
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: [.maskControl, .maskAlternate]))
    }

    func test_rejectsNoControl() {
        XCTAssertFalse(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: []))
    }

    func test_ignoresDeviceIndependentNoiseBits() {
        let flags: CGEventFlags = [.maskControl, .maskNonCoalesced]
        XCTAssertTrue(HotkeyMatcher.isCtrlDown(keyCode: 125, flags: flags))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `cannot find 'HotkeyMatcher' in scope` (red state).

- [ ] **Step 3: Write `HotkeyMatcher.swift`**

```swift
import CoreGraphics

enum HotkeyMatcher {
    static let downArrowKeyCode: Int64 = 125

    static func isCtrlDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == downArrowKeyCode else { return false }
        let hasControl = flags.contains(.maskControl)
        let hasOtherModifier = flags.contains(.maskShift)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskCommand)
        return hasControl && !hasOtherModifier
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`, all HotkeyMatcher tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Hotkey/HotkeyMatcher.swift Tests/MyDefineShortcutTests/HotkeyMatcherTests.swift
git commit -m "feat: add Ctrl+Down hotkey matcher"
```

---

## Task 4: AX window matcher (TDD)

**Files:**
- Create: `Sources/MyDefineShortcut/Activation/WindowMatcher.swift`
- Test: `Tests/MyDefineShortcutTests/WindowMatcherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import MyDefineShortcut

final class WindowMatcherTests: XCTestCase {
    private func target(title: String = "Doc", x: CGFloat = 100, y: CGFloat = 100,
                        w: CGFloat = 800, h: CGFloat = 600) -> WindowInfo {
        WindowInfo(windowID: 1, title: title, frame: CGRect(x: x, y: y, width: w, height: h), appName: "App")
    }

    func test_prefersExactFrameMatch() {
        let candidates = [
            AXWindowCandidate(index: 0, title: "Other", frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
            AXWindowCandidate(index: 1, title: "Other", frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
        ]
        XCTAssertEqual(WindowMatcher.bestMatch(for: target(), among: candidates), 1)
    }

    func test_fallsBackToTitleWhenNoFrameMatch() {
        let candidates = [
            AXWindowCandidate(index: 0, title: "Doc", frame: CGRect(x: 5, y: 5, width: 10, height: 10)),
            AXWindowCandidate(index: 1, title: "Nope", frame: CGRect(x: 9, y: 9, width: 10, height: 10)),
        ]
        XCTAssertEqual(WindowMatcher.bestMatch(for: target(title: "Doc"), among: candidates), 0)
    }

    func test_fallsBackToNearestOriginWhenNoFrameOrTitleMatch() {
        let candidates = [
            AXWindowCandidate(index: 0, title: "", frame: CGRect(x: 500, y: 500, width: 10, height: 10)),
            AXWindowCandidate(index: 1, title: "", frame: CGRect(x: 110, y: 110, width: 10, height: 10)),
        ]
        XCTAssertEqual(WindowMatcher.bestMatch(for: target(title: ""), among: candidates), 1)
    }

    func test_returnsNilForEmptyCandidates() {
        XCTAssertNil(WindowMatcher.bestMatch(for: target(), among: []))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: compile failure — `cannot find 'AXWindowCandidate' / 'WindowMatcher' in scope` (red state).

- [ ] **Step 3: Write `WindowMatcher.swift`**

```swift
import CoreGraphics

struct AXWindowCandidate: Equatable {
    let index: Int
    let title: String
    let frame: CGRect
}

enum WindowMatcher {
    static func bestMatch(for target: WindowInfo, among candidates: [AXWindowCandidate]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        if let exact = candidates.first(where: { framesEqual($0.frame, target.frame) }) {
            return exact.index
        }
        if !target.title.isEmpty,
           let byTitle = candidates.first(where: { $0.title == target.title }) {
            return byTitle.index
        }
        let nearest = candidates.min(by: {
            originDistance($0.frame, target.frame) < originDistance($1.frame, target.frame)
        })
        return nearest?.index
    }

    private static func framesEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
        abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.size.width - b.size.width) <= tolerance &&
        abs(a.size.height - b.size.height) <= tolerance
    }

    private static func originDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.origin.x - b.origin.x
        let dy = a.origin.y - b.origin.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`, all WindowMatcher tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyDefineShortcut/Activation/WindowMatcher.swift Tests/MyDefineShortcutTests/WindowMatcherTests.swift
git commit -m "feat: add AX window matcher (frame/title/nearest)"
```

---

## Task 5: Permissions manager

**Files:**
- Create: `Sources/MyDefineShortcut/Permissions/PermissionsManager.swift`

- [ ] **Step 1: Write `PermissionsManager.swift`**

```swift
import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionState { case granted, denied }

enum PermissionsManager {
    static func accessibilityState() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func screenRecordingState() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Permissions/PermissionsManager.swift
git commit -m "feat: add permissions manager (Accessibility + Screen Recording)"
```

---

## Task 6: Window enumerator (ScreenCaptureKit adapter)

**Files:**
- Create: `Sources/MyDefineShortcut/Windows/WindowEnumerator.swift`

- [ ] **Step 1: Write `WindowEnumerator.swift`**

```swift
import ScreenCaptureKit

enum WindowEnumerator {
    /// Fetches the focused app's visible windows on the current desktop, as SCWindow objects
    /// (filtering delegated to the tested WindowFilter via windowID set).
    static func filteredSCWindows(forPID pid: pid_t) async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let raw = content.windows.map { rawWindow(from: $0) }
        let allowedIDs = Set(WindowFilter.visibleWindows(from: raw, frontmostPID: pid).map(\.windowID))
        return content.windows.filter { allowedIDs.contains($0.windowID) }
    }

    static func info(from window: SCWindow) -> WindowInfo {
        WindowInfo(windowID: window.windowID,
                   title: window.title ?? "",
                   frame: window.frame,
                   appName: window.owningApplication?.applicationName ?? "")
    }

    private static func rawWindow(from window: SCWindow) -> RawWindow {
        RawWindow(windowID: window.windowID,
                  ownerPID: pid_t(window.owningApplication?.processID ?? 0),
                  layer: window.windowLayer,
                  isOnScreen: window.isOnScreen,
                  title: window.title ?? "",
                  appName: window.owningApplication?.applicationName ?? "",
                  frame: window.frame)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Windows/WindowEnumerator.swift
git commit -m "feat: add ScreenCaptureKit window enumerator (current desktop)"
```

(Manual verification happens end-to-end in Task 13; this adapter needs Screen Recording permission and a real session.)

---

## Task 7: Thumbnail capturer

**Files:**
- Create: `Sources/MyDefineShortcut/Windows/ThumbnailCapturer.swift`

- [ ] **Step 1: Write `ThumbnailCapturer.swift`**

```swift
import ScreenCaptureKit
import CoreGraphics

enum ThumbnailCapturer {
    static func capture(_ window: SCWindow, maxWidth: CGFloat = 640) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = max(1, window.frame.width / maxWidth)
        config.width = max(1, Int(window.frame.width / scale))
        config.height = max(1, Int(window.frame.height / scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Windows/ThumbnailCapturer.swift
git commit -m "feat: add per-window thumbnail capturer (SCScreenshotManager)"
```

---

## Task 8: Hotkey event tap

**Files:**
- Create: `Sources/MyDefineShortcut/Hotkey/HotkeyTap.swift`

- [ ] **Step 1: Write `HotkeyTap.swift`**

```swift
import CoreGraphics

final class HotkeyTap {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    /// Returns false if the tap could not be created (usually missing Accessibility permission).
    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if HotkeyMatcher.isCtrlDown(keyCode: keyCode, flags: event.flags) {
            let trigger = onTrigger
            DispatchQueue.main.async { trigger() }
            return nil // swallow → suppress native App Exposé
        }
        return Unmanaged.passUnretained(event)
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Hotkey/HotkeyTap.swift
git commit -m "feat: add CGEventTap that intercepts and swallows Ctrl+Down"
```

---

## Task 9: Window activator (Accessibility raise + activate)

**Files:**
- Create: `Sources/MyDefineShortcut/Activation/WindowActivator.swift`

- [ ] **Step 1: Write `WindowActivator.swift`**

```swift
import AppKit
import ApplicationServices

enum WindowActivator {
    static func activate(_ target: WindowInfo, pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            let candidates = axWindows.enumerated().map { idx, win in
                AXWindowCandidate(index: idx, title: axTitle(win), frame: axFrame(win))
            }
            if let matchIndex = WindowMatcher.bestMatch(for: target, among: candidates),
               matchIndex < axWindows.count {
                AXUIElementPerformAction(axWindows[matchIndex], kAXRaiseAction as CFString)
            }
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
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
           let posValue {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
        }
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/MyDefineShortcut/Activation/WindowActivator.swift
git commit -m "feat: add Accessibility window raise + app activation"
```

---

## Task 10: Snapshot grid view (SwiftUI)

**Files:**
- Create: `Sources/MyDefineShortcut/Overlay/WindowThumbnail.swift`
- Create: `Sources/MyDefineShortcut/Overlay/SnapshotView.swift`

- [ ] **Step 1: Write `WindowThumbnail.swift`**

```swift
import CoreGraphics

struct WindowThumbnail: Identifiable {
    let id: CGWindowID
    let image: CGImage?
    let title: String
    let info: WindowInfo
    let pid: pid_t
}
```

- [ ] **Step 2: Write `SnapshotView.swift`**

```swift
import SwiftUI

struct SnapshotView: View {
    let appName: String
    let thumbnails: [WindowThumbnail]
    let onSelect: (WindowThumbnail) -> Void
    let onDismiss: () -> Void

    private var columns: [GridItem] {
        let count = min(max(thumbnails.count, 1), 4)
        return Array(repeating: GridItem(.flexible(), spacing: 24), count: count)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                Text("\(appName) — \(thumbnails.count) window\(thumbnails.count == 1 ? "" : "s")")
                    .font(.title2).bold()
                    .foregroundStyle(.white)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(thumbnails) { thumb in
                            Button { onSelect(thumb) } label: {
                                cell(thumb)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cell(_ thumb: WindowThumbnail) -> some View {
        VStack(spacing: 8) {
            if let image = thumb.image {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 320, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(width: 320, height: 220)
                    .overlay(Image(systemName: "macwindow").font(.largeTitle).foregroundStyle(.white))
            }
            Text(thumb.title.isEmpty ? appName : thumb.title)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 300)
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/MyDefineShortcut/Overlay/WindowThumbnail.swift Sources/MyDefineShortcut/Overlay/SnapshotView.swift
git commit -m "feat: add SwiftUI snapshot grid view"
```

---

## Task 11: Overlay window + controller

**Files:**
- Create: `Sources/MyDefineShortcut/Overlay/OverlayWindow.swift`
- Create: `Sources/MyDefineShortcut/Overlay/OverlayController.swift`

- [ ] **Step 1: Write `OverlayWindow.swift`**

```swift
import AppKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

- [ ] **Step 2: Write `OverlayController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private var window: OverlayWindow?
    private var keyMonitor: Any?

    func show(appName: String,
              thumbnails: [WindowThumbnail],
              on screen: NSScreen,
              onSelect: @escaping (WindowThumbnail) -> Void) {
        dismiss()

        let root = SnapshotView(
            appName: appName,
            thumbnails: thumbnails,
            onSelect: { [weak self] thumb in
                self?.dismiss()
                onSelect(thumb)
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let win = OverlayWindow(contentRect: screen.frame,
                                styleMask: [.borderless],
                                backing: .buffered,
                                defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visual = NSVisualEffectView(frame: screen.frame)
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: root)
        hosting.frame = visual.bounds
        hosting.autoresizingMask = [.width, .height]
        visual.addSubview(hosting)

        win.contentView = visual
        win.setFrame(screen.frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.dismiss()
                return nil
            }
            return event
        }
        window = win
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window?.orderOut(nil)
        window = nil
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/MyDefineShortcut/Overlay/OverlayWindow.swift Sources/MyDefineShortcut/Overlay/OverlayController.swift
git commit -m "feat: add full-screen overlay window + controller"
```

---

## Task 12: Wire everything in AppDelegate

**Files:**
- Modify: `Sources/MyDefineShortcut/App/AppDelegate.swift` (replace the Task 1 stub entirely)

- [ ] **Step 1: Replace `AppDelegate.swift` with the full implementation**

```swift
import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyTap: HotkeyTap?
    private let overlay = OverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        ensurePermissions()
        startHotkey()
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                     accessibilityDescription: "Window Snapshot")
        let menu = NSMenu()
        menu.addItem(withTitle: "Trigger Snapshot", action: #selector(triggerFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Accessibility Settings…", action: #selector(openAX), keyEquivalent: "")
        menu.addItem(withTitle: "Screen Recording Settings…", action: #selector(openSR), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    private func ensurePermissions() {
        if PermissionsManager.accessibilityState() == .denied {
            PermissionsManager.requestAccessibility()
        }
        if PermissionsManager.screenRecordingState() == .denied {
            PermissionsManager.requestScreenRecording()
        }
    }

    private func startHotkey() {
        let tap = HotkeyTap { [weak self] in self?.handleTrigger() }
        if !tap.start() {
            PermissionsManager.requestAccessibility()
        }
        hotkeyTap = tap
    }

    @objc private func triggerFromMenu() { handleTrigger() }
    @objc private func openAX() { PermissionsManager.openAccessibilitySettings() }
    @objc private func openSR() { PermissionsManager.openScreenRecordingSettings() }

    private func handleTrigger() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "App"
        Task { await presentSnapshot(pid: pid, appName: appName) }
    }

    private func presentSnapshot(pid: pid_t, appName: String) async {
        do {
            let scWindows = try await WindowEnumerator.filteredSCWindows(forPID: pid)
            guard !scWindows.isEmpty else { return }
            var thumbnails: [WindowThumbnail] = []
            for window in scWindows {
                let info = WindowEnumerator.info(from: window)
                let image = try? await ThumbnailCapturer.capture(window)
                thumbnails.append(WindowThumbnail(id: window.windowID,
                                                  image: image,
                                                  title: info.title,
                                                  info: info,
                                                  pid: pid))
            }
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }
            overlay.show(appName: appName, thumbnails: thumbnails, on: screen) { thumb in
                WindowActivator.activate(thumb.info, pid: thumb.pid)
            }
        } catch {
            NSLog("MyDefineShortcut snapshot failed: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Confirm unit tests still pass**

Run: `xcodebuild test -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -destination 'platform=macOS' -derivedDataPath ./build`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/MyDefineShortcut/App/AppDelegate.swift
git commit -m "feat: wire hotkey, enumeration, capture, overlay, and activation"
```

---

## Task 13: End-to-end manual verification

**Files:** none (verification + final launch).

This app's core behavior depends on system permissions and live windows, so it must be verified by hand.

- [ ] **Step 1: Build and launch**

Run:
```bash
xcodebuild build -project MyDefineShortcut.xcodeproj -scheme MyDefineShortcut -configuration Debug -derivedDataPath ./build
open ./build/Build/Products/Debug/MyDefineShortcut.app
```

- [ ] **Step 2: Grant permissions**

On first launch the app prompts for Accessibility and Screen Recording.
- System Settings → Privacy & Security → Accessibility → enable `MyDefineShortcut`.
- System Settings → Privacy & Security → Screen Recording → enable `MyDefineShortcut`.
Then quit and relaunch the app (`open ./build/Build/Products/Debug/MyDefineShortcut.app`).

- [ ] **Step 3: Verify interception + count**

With an app that has 2+ windows open on the current desktop (e.g. several browser windows), press **Ctrl+Down**.
Expected:
- The native macOS App Exposé does **not** fire.
- A dimmed full-screen overlay appears showing one thumbnail per visible window of the focused app, with title labels and a header "<AppName> — N windows".
- N matches the number of that app's windows on the current desktop only (windows on other Spaces are excluded).

*If native App Exposé still fires:* apply the fallback from the spec — disable the system "Application windows" shortcut (System Settings → Keyboard → Keyboard Shortcuts → Mission Control → uncheck "Application windows"), then retest.

- [ ] **Step 4: Verify multi-Space scoping**

Move one of the app's windows to a second desktop (Space). Return to the first desktop, focus the app, press Ctrl+Down.
Expected: the moved window is NOT counted or shown; only current-desktop windows appear.

- [ ] **Step 5: Verify click-to-switch and dismissal**

- Click a thumbnail → that window is raised to the front and the overlay closes.
- Press Ctrl+Down again, then press Esc → overlay closes with no window change.
- Press Ctrl+Down again, then click empty (dimmed) area → overlay closes.

- [ ] **Step 6: Verify Screen Recording fallback**

Temporarily revoke Screen Recording (System Settings → Privacy & Security → Screen Recording → disable `MyDefineShortcut`), relaunch, press Ctrl+Down.
Expected: overlay still shows the correct count with placeholder cards + titles (no thumbnails). Re-enable Screen Recording afterward.

- [ ] **Step 7: Final commit (if any tweaks were needed during verification)**

```bash
git add -A
git commit -m "chore: finalize Ctrl+Down window snapshot after manual verification"
```

---

## Spec Coverage Check

- Intercept Ctrl+Down + suppress native App Exposé → Task 3 (matcher), Task 8 (tap swallow), Task 13 step 3.
- Frontmost app detection → Task 12 (`NSWorkspace.frontmostApplication`).
- Current-desktop, visible windows only → Task 2 (filter), Task 6 (`isOnScreen`), Task 13 step 4.
- Count display → Task 10 (header), Task 13 step 3.
- Thumbnail-grid App Exposé look → Task 7 (capture), Task 10 (grid), Task 11 (overlay).
- Click-to-switch → Task 4 (matcher), Task 9 (AX raise), Task 12 (wiring), Task 13 step 5.
- Esc / click-away dismissal → Task 10 (tap-away), Task 11 (Esc monitor), Task 13 step 5.
- Permissions (AX required, Screen Recording with fallback) → Task 5, Task 12, Task 13 steps 2 & 6.
- Menu-bar LSUIElement agent → Task 1, Task 12.
- Xcode project, stable signing note → Task 1 + signing note.
- Single-display v1 scope → Task 12 (`NSScreen.main`).
```

