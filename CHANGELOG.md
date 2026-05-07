# Changelog

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
