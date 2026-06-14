# Rebound (per-app folder memory) — removed

**Status:** implemented in 0.2.0-dev, removed 2026-06-14 before any public release.

## What it was

"Rebound" was a clone of Default Folder X's defining feature: PathPal remembered,
per application, the folder you last navigated that app's Open/Save dialogs to, and
**auto-navigated each new dialog there** before you touched anything.

- `AppFolderMemoryService` stored a `[bundleID: {appName, path, pinned}]` map in
  `~/Library/Application Support/PathPal/app_folders.json`.
- Every PathPal-driven dialog navigation (`DialogNavigationService.navigateDialog`)
  recorded the destination folder for that app's bundle ID, unless the entry was
  pinned.
- On dialog detection (`AppDelegate`), if the app had a remembered folder, PathPal
  scheduled an auto-navigation ~0.5s later via the Go To Folder sheet.
- Settings → "Per-App Folders" let you toggle the whole feature, see the learned
  list, pin an entry to a fixed folder, choose a folder manually, or forget an app.
- A `navigatedDialogPIDs` set in `AppDelegate` suppressed re-triggering rebound when
  the navigation's own Go To Folder sheet was re-detected as a "new" dialog, and
  prevented rebound from overriding a manual drawer/path-bar pick.

## Why it was removed

It didn't work well enough in practice:

- **Auto-navigation drives the Go To Folder sheet** (Cmd+Shift+G → type path →
  Return). That's visible and racy — a flash of the sheet on every dialog, and it
  competes with the app's own dialog setup. On a busy or slow app the AX poll for
  the Go To Folder field could miss, leaving the dialog unmoved or half-driven.
- **Loop / override hazards.** The sheet that navigation opens fires its own
  window-created event, re-detected as a dialog. This caused a navigation loop until
  it was patched with per-pid suppression, and the same machinery was needed so a
  drawer/path-bar pick wasn't immediately overridden by a re-fired rebound. The
  feature's correctness depended on fragile bookkeeping around dialog identity.
- **Net result:** the magic-when-it-works payoff wasn't worth the jank and edge
  cases. The manual surfaces (the overlay, the file drawer, Cmd+L path bar, recent
  folders) already cover "get this dialog to the right folder" reliably.

## If revisited

The right implementation would set the dialog's folder **without** driving the Go To
Folder sheet — e.g. via the dialog's own AX tree / a private panel API, or by
nudging `NSUserDefaults`-backed "last directory" keys before the panel opens — so
there's no keystroke race and no re-detection loop. Until that path is proven,
rebound stays out.

Removed in: see the commit referencing this doc. The implementation lived in
`AppFolderMemoryService.swift` (+ tests), with hooks in `AppDelegate.swift`,
`DialogNavigationService.swift`, `SettingsService.swift`, and `SettingsView.swift`.
