# Changelog

## 0.3.4 - 2026-05-07

- Added a first-run setup window so opening BarShelf is visible even before menu bar permissions are granted.
- Shows live Accessibility and Screen Recording permission status with buttons that open the relevant macOS Privacy settings panes.
- Added a Launch at Login checkbox to first-run setup.
- Keeps Finish Setup disabled until Accessibility permission is granted.

## 0.3.3 - 2026-05-07

- Added generated BarShelf app icon/logo assets.
- Wired the icon into the macOS app bundle and DMG volume metadata.
- Added the icon to the README and GitHub Pages docs.
- Documented Homebrew installation via `brew tap lvtd-llc/tap` and `brew install --cask barshelf`.
- Added conditional Developer ID signing and Apple notarization support to the release workflow.
- Added signing/notarization docs, including required GitHub secrets and macOS-vs-iOS distribution notes.
- Added a repo-contained static documentation site under `docs/`.
- Added a GitHub Actions workflow to deploy `docs/` to GitHub Pages.

## 0.3.2 - 2026-05-07

- Added native Launch at Login support using Apple ServiceManagement (`SMAppService.mainApp`).
- Added a Settings checkbox plus CLI commands for launch-at-login status/enable/disable.

## 0.3.1 - 2026-05-07

- Added `barshelf install-cli` and `barshelf uninstall-cli` helpers for creating/removing a PATH symlink to the app-bundled CLI.
- Documented default `/usr/local/bin/barshelf` install path plus user-writable `--path` fallback.

## 0.3.0 - 2026-05-07

- Added native Swift `barshelf` CLI executable for status/list JSON output, shelf show/hide/toggle, rescan, settings, permissions, and per-item visibility mode updates.
- Added shared app/CLI settings storage under `com.gregagi.barshelf` and distributed-notification IPC for live app commands.
- Packaged the CLI inside `BarShelf.app/Contents/MacOS/barshelf`.
- Added a `BarShelfCore` SwiftPM library target with XCTest coverage for visibility modes, menu bar item identity, and persisted routing mode serialization.
- Updated PR CI to run `swift test` with code coverage before release/app bundle builds.

## 0.2.1 - 2026-05-07

- Made BarShelf’s own status bar icon persistently visible and changed its default click behavior to reveal/hide the floating shelf of hidden icons.
- Start with the floating shelf hidden by default; users reveal it by clicking the BarShelf icon.

## 0.2.0 - 2026-05-07

- Added advanced per-item routing settings with three modes: always shown, floating shelf, and always hidden.
- Added CGWindow-based menu bar item discovery, permission prompts, visual masking overlays, and a translucent floating shelf below the menu bar.
- Kept the original separator/spacer mode as a fallback for items macOS does not expose reliably.

## 0.1.0 - 2026-05-06

- Initial native macOS BarShelf app.
- Added menu bar UI using the separator/spacer hidden shelf pattern.
- Added GitHub Actions release workflow to build and upload `BarShelf.dmg`.
