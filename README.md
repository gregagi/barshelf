# BarShelf

BarShelf is an open-source, free macOS menu bar manager experiment — a tiny native Bartender-style alternative.

## Current direction

BarShelf now has two approaches:

1. **Advanced per-item routing** — route detected menu bar items into:
   - Always shown
   - Floating shelf
   - Always hidden
2. **Fallback separator mode** — the original Hidden/Dozer-style separator and spacer technique.

The advanced mode uses macOS window discovery, screen capture, visual masking overlays, and Accessibility-assisted click forwarding. The goal is to make third-party menu bar icons appear in a compact translucent shelf below the macOS menu bar while masking the originals.

## Permissions

Advanced routing needs user-granted macOS permissions:

- **Accessibility** — forwards clicks from floating shelf items to the original menu bar item.
- **Screen Recording / Screen Capture** — captures menu bar item images for the floating shelf.

BarShelf asks for these from Settings → Request permissions. After granting permissions, quit and reopen BarShelf, then click Rescan.

## Install

Download the latest `BarShelf.dmg` from GitHub Releases, drag `BarShelf.app` into Applications, then launch it.

Unsigned builds may require right-click → Open the first time.

## Usage

BarShelf’s own `▦` icon always stays visible in the macOS menu bar. Click it to reveal or hide the floating shelf.

Open BarShelf Settings and assign each detected menu bar item to one of the three modes:

- **Always shown** keeps the original icon visible in the macOS menu bar.
- **Floating shelf** masks the original icon and shows it in BarShelf’s shelf below the menu bar when you click the BarShelf icon.
- **Always hidden** masks the original icon and does not show it in the shelf.

If an item cannot be detected reliably, use fallback separator mode: hold `Command (⌘)`, drag menu bar icons to the left of BarShelf's `│` separator, then collapse/expand the shelf.



## CLI

BarShelf also ships a native Swift CLI for developers, prosumers, and AI agents. In the app bundle it lives at:

```bash
/Applications/BarShelf.app/Contents/MacOS/barshelf
```

Initial commands:

```bash
barshelf status --json
barshelf list --json
barshelf show
barshelf hide
barshelf toggle
barshelf rescan
barshelf set <item-id> always-shown
barshelf set <item-id> floating-shelf
barshelf set <item-id> always-hidden
barshelf open-settings
barshelf permissions
barshelf install-cli
barshelf uninstall-cli
```

To make the CLI available as `barshelf` from your shell, run it once from the app bundle:

```bash
/Applications/BarShelf.app/Contents/MacOS/barshelf install-cli
```

By default this creates `/usr/local/bin/barshelf -> /Applications/BarShelf.app/Contents/MacOS/barshelf`. If `/usr/local/bin` is not writable, use a user-writable location already on your PATH:

```bash
/Applications/BarShelf.app/Contents/MacOS/barshelf install-cli --path "$HOME/.local/bin/barshelf"
```

The CLI and app share the same settings store (`com.gregagi.barshelf`). Live commands are delivered to the running app through macOS distributed notifications, so no daemon or local server is required.

## Testing

BarShelf uses SwiftPM XCTest for headless logic that can run reliably on GitHub-hosted macOS runners. The CI pipeline runs on every pull request and on pushes to `main`:

```bash
swift test --configuration debug --enable-code-coverage
swift build -c release
./Scripts/build_app.sh
```

UI behavior that depends on macOS Accessibility or Screen Recording prompts still needs manual verification on a real Mac because GitHub runners cannot grant those permissions interactively.

## Build locally

```bash
swift build -c release
```

To create an app bundle locally on macOS:

```bash
./Scripts/build_app.sh
```

## Release

Create a GitHub release tag like `v0.3.1`. The release workflow builds on `macos-14`, creates `BarShelf.app`, packages `BarShelf.dmg`, and uploads it to the release assets.

## Roadmap

- Harden per-item detection across macOS versions and notched displays
- Better matching for duplicate items from the same app
- Launch at login
- Keyboard shortcut
- Signed + notarized builds once Apple Developer credentials are available
