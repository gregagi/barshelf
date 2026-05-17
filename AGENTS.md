# BarShelf Codex Notes

BarShelf is a SwiftPM/AppKit macOS menu bar app with a bundled CLI.

Use these checks before handing off changes:

- Headless logic changes: `swift test --configuration debug --enable-code-coverage`
- Release/package changes: `./Scripts/build_app.sh`
- UI, menu bar, setup, settings, permission, or CLI changes: `./Scripts/dev_check.sh`

`Scripts/dev_check.sh` builds the app, launches `dist/BarShelf.app`, drives the bundled `barshelf` CLI, and uses Peekaboo to verify that a setup/settings window is actually visible. It writes screenshots and JSON observations to `tmp/peekaboo/`.

Peekaboo requirements:

- Install: `brew install steipete/tap/peekaboo`
- Required: grant Screen Recording to the shell/Codex host that runs `peekaboo`
- Recommended: grant Accessibility as well, so future checks can click menu/status items instead of only capturing windows

For local visual debugging, inspect `tmp/peekaboo/barshelf-window.png` after running the smoke check. Set `BARSHELF_KEEP_APP=1 ./Scripts/dev_check.sh` when you want the launched app to remain open after the check.
