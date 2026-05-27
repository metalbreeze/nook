# Nook

A tiny macOS menu-bar utility that makes window and app switching **desktop-aware**.
macOS shows you *every* window across *every* Space; Nook scopes the two switching
gestures you use most to just the desktop you are looking at right now.

> **Requires macOS 14 (Sonoma) or later.**

## What it does

### Desktop-scoped Cmd+Tab

Press **⌘Tab** and Nook replaces the system switcher with one that lists only the
apps that have a window on the **current desktop** — no clutter from apps parked on
other Spaces.

- **⌘Tab / ⇧⌘Tab** — move the selection forward / backward (hold ⌘).
- **← / →** — pick a specific window of the highlighted app from its live previews.
- **1–9** — jump straight to a numbered window (the number is shown on each preview).
- **Mouse** — hover to highlight, click a preview to switch immediately.
- **Esc** — cancel and keep your current window.

Each desktop can have its own **name**. Click the *Rename* button in the switcher to
edit it inline (Enter saves, Esc cancels). Named desktops show their name; unnamed
ones show "Desktop".

### Ctrl+Down window snapshot

Press **⌃↓** to get an App-Exposé-style grid of the focused app's windows — but only
the windows on the **current desktop**. Click one to bring it forward, or press **Esc**
to return focus to where you were.

### Menu bar

The menu-bar icon shows the **current desktop's name** when you have named it (icon
only otherwise). A toggle — *Show Desktop Name in Menu Bar* — turns the name on or off,
and the title updates live when you switch desktops or rename one. The menu also has
manual triggers and shortcuts to the two macOS permission panes Nook needs.

## Permissions

Nook needs two macOS permissions, granted on first launch (or via **System Settings ▸
Privacy & Security**):

- **Accessibility** — to intercept the ⌘Tab / ⌃↓ shortcuts and to raise the window you pick.
- **Screen Recording** — to capture the window previews and snapshot thumbnails.

Nook talks to no network, stores nothing off-device, and keeps desktop names in your
local user defaults.

## Install

Download the latest notarized build from the [Releases](../../releases) page, move
**Nook.app** to `/Applications`, and launch it. Grant the two permissions when prompted.

## Build from source

Nook uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate its Xcode
project from `project.yml` (the `.xcodeproj` is not checked in).

```sh
brew install xcodegen
xcodegen generate
xcodebuild build -project Nook.xcodeproj -scheme Nook -configuration Release -destination 'platform=macOS'
```

Run the tests with:

```sh
xcodebuild test -project Nook.xcodeproj -scheme Nook -destination 'platform=macOS'
```

## How it works

Nook is a background **menu-bar agent** (`LSUIElement`). It uses a `CGEventTap` to
intercept the two shortcuts, ScreenCaptureKit to enumerate and capture windows, and the
Accessibility API to raise the window you choose. The "current desktop" filter is built
on `CGWindowList`, which authoritatively returns only the windows on the active Space.

## License

Released under the [MIT License](LICENSE).
