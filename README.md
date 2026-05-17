# BarShelf

<p align="center"><img src="docs/assets/app-icon.png" alt="BarShelf app icon" width="128" height="128"></p>

BarShelf is an open-source, free macOS menu bar manager experiment — a tiny native Bartender-style alternative.

Documentation site: https://lvtd-llc.github.io/barshelf/
Signing and notarization: https://lvtd-llc.github.io/barshelf/signing-notarization.html

## Current direction

BarShelf now has two approaches:

1. **Advanced per-item routing** — route detected menu bar items into:
   - Always shown
   - Floating shelf
   - Always hidden
2. **Fallback separator mode** — the original Hidden/Dozer-style separator and spacer technique.

The advanced mode uses macOS status-window discovery, Accessibility menu-extra discovery, screen capture, and Accessibility-assisted click forwarding. The goal is to make third-party and system menu bar icons appear in a compact translucent shelf below the macOS menu bar. Always-hidden items may be visually masked; floating-shelf items remain visible in the real menu bar until BarShelf can move/reorder them safely.

## Permissions

Advanced routing needs user-granted macOS permissions:

- **Accessibility** — forwards clicks from floating shelf items to the original menu bar item.
- **Accessibility menu-extra discovery** — helps detect individual Control Center/SystemUIServer items that macOS exposes through `AXExtrasMenuBar` rather than separate WindowServer images.
- **Screen Recording / Screen Capture** — captures menu bar item images for the floating shelf.

On first launch, BarShelf opens a setup window that shows live permission status, opens the correct macOS Privacy settings panes, and keeps **Finish Setup** disabled until Accessibility is granted. You can reopen this window later from the BarShelf menu → Setup.

## Install

Homebrew:

```bash
brew tap lvtd-llc/tap
brew install --cask barshelf
```

Manual download:

Download the latest `BarShelf.dmg` from GitHub Releases, drag `BarShelf.app` into Applications, then launch it.

Unsigned builds may require right-click → Open the first time. BarShelf is a menu bar app, so it does not stay in the Dock; first launch opens the setup window so the app is visible while permissions are configured.

## Usage

BarShelf’s own `▦` icon always stays visible in the macOS menu bar after launch. Click it to reveal or hide the floating shelf. Enable **Launch BarShelf at login** in first-run setup or Settings if you want BarShelf to start automatically when you sign in.

Open BarShelf Settings with the BarShelf menu item or `Command-comma` while BarShelf is active. Settings includes **Check for Updates**, which can upgrade Homebrew cask installs in-place or open the latest release for manual installs. The detected items are shown in three rows. Drag icons between rows to change state, and drag inside a row to set BarShelf’s preferred visual order:

- **Always shown** keeps the original icon visible in the macOS menu bar.
- **Floating shelf** masks the original icon and shows it in BarShelf’s floating panel below the menu bar when you click the BarShelf icon. The shelf anchors near BarShelf’s own icon and stays clamped to the current screen, similar to Ice’s separate-bar gallery behavior.
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
barshelf launch-at-login status --json
barshelf launch-at-login enable
barshelf launch-at-login disable
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

For local Codex-assisted UI work on a real Mac, install Peekaboo and run the visual smoke check:

```bash
brew install steipete/tap/peekaboo
./Scripts/dev_check.sh
```

The smoke check launches `dist/BarShelf.app`, exercises the bundled `barshelf` CLI, verifies that setup/settings is visible through Peekaboo, and writes screenshots plus JSON observations to `tmp/peekaboo/`. Peekaboo needs Screen Recording permission for screenshots; Accessibility is recommended for click/menu automation.

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
