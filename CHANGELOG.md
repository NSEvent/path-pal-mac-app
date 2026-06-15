# Changelog

## Unreleased

- Cmd+Return in Finder opens the selected folder in the same window, or Quick Looks a selected file — browse the filesystem keyboard-only (opt-in, Settings → Keyboard)
- Backspace in Finder navigates to the parent folder (opt-in, Settings → Keyboard) — ignored while renaming or searching, so it never eats a real backspace
- F2 in Finder renames the selected item, Windows-style (opt-in, Settings → Keyboard)
- Fixed: Finder highlight overlays could occasionally cover the Open/Save dialog itself (the dialog's own bounds are now always carved out, read fresh from Accessibility)
- Removed the per-app "rebound" auto-navigation feature — it was unreliable in practice. See `docs/rebound.md` for what it was and why it was pulled.

## 0.2.0 — 2026-06-12

- Keyboard navigation in the dialog overlay: ⌃⌥↑/⌃⌥↓ select, ⌃⌥↩ open, ⌃1–9 jump to Quick Access/favorites
- Recent Files section in Open dialogs — click to select the file itself
- File drawer: click an item while a dialog is open to teleport the dialog there; folder items accept drops (copy into folder); Cmd-click multi-select drags out as a group
- Cmd+L path bar now works inside Open/Save dialogs and drives the dialog
- Fuzzy path matching: "fbm" finds folder-buddy-mac-app (frecency-ranked for bare queries)
- Per-app exclusion list — PathPal leaves chosen apps' dialogs alone
- Live demo dialog right after onboarding
- Sparkle auto-updates (Check for Updates in the menu bar)

## 0.1.0 — 2026-06-11

Initial release.

- Open/Save dialog overlay with Finder windows, Quick Access, favorites, and recents
- Color-coded Finder window highlighting with click-to-navigate
- Menu bar recent folders/files with browsable submenus
- Cmd+L path bar for Finder with autocomplete, pre-filled with the front Finder window's path (open in Finder or iTerm)
- Optional file drawer: park files on a floating shelf, drag them out anywhere
- Optional FinderSync toolbar button
- Launch at login
