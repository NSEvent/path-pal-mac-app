import AppKit
import ApplicationServices
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appState = AppState()
    private var menuBarService: MenuBarService!
    private let recentItemsService = RecentItemsService()
    private let accessibilityService = AccessibilityService()
    private let hotKeyService = HotKeyService()
    private let dialogNavigationService = DialogNavigationService()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    private var overlayWindowService: OverlayWindowService!
    private var pathBarPanel: PathBarPanel?
    private var finderPollingTimer: Timer?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no dock icon
        NSApp.setActivationPolicy(.accessory)

        // Drop recents whose folders/files no longer exist
        recentItemsService.removeDeletedItems()

        // Set up menu bar
        menuBarService = MenuBarService(appState: appState, recentItemsService: recentItemsService)
        menuBarService.setup(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onShowPathBar: { [weak self] in self?.showPathBar() },
            onCheckForUpdates: { [weak self] in self?.updaterController.checkForUpdates(nil) }
        )

        // Set up overlay service
        overlayWindowService = OverlayWindowService(appState: appState)

        // Check permissions and start services
        appState.isAccessibilityGranted = PermissionsService.shared.isAccessibilityGranted

        // Always start services (they gracefully handle missing permissions)
        startServices()

        if !SettingsService.shared.hasCompletedOnboarding {
            showOnboarding()
        }

        // Drawer clicks teleport an open dialog to the clicked item.
        FileDrawerService.shared.dialogNavigator = { [weak self] path in
            self?.overlayWindowService.navigateCurrentDialog(toPath: path) ?? false
        }

        if SettingsService.shared.fileDrawerEnabled {
            FileDrawerService.shared.show()
        }
        NotificationCenter.default.addObserver(
            forName: FileDrawerService.visibilityChangedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.menuBarService.refreshMenu()
        }

        // Prompt for Full Disk Access if not yet granted (needed for Finder
        // favorites). FDA is optional, so nag at most once — after that it's
        // discoverable in onboarding and Settings.
        let fdaPromptKey = "hasPromptedFullDiskAccess"
        if !PermissionsService.shared.isFullDiskAccessGranted,
           !UserDefaults.standard.bool(forKey: fdaPromptKey) {
            UserDefaults.standard.set(true, forKey: fdaPromptKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                PermissionsService.shared.requestFullDiskAccess()
            }
        }
    }

    /// Post a Space keystroke to the frontmost app (Finder) to toggle Quick
    /// Look on the selected file — the Cmd+Return-on-a-file behavior.
    ///
    /// The user just pressed Cmd+Return and is likely still holding Command.
    /// If we post Space while Command is down, the OS reads it as Cmd+Space and
    /// can trigger other apps' Cmd+Space hotkeys (Spotlight, Sol, etc.). So we
    /// wait for Command to be released first, then post a plain Space with
    /// explicitly-cleared modifier flags.
    private static func pressSpaceForQuickLook(attempt: Int = 0) {
        if NSEvent.modifierFlags.contains(.command) && attempt < 30 { // up to ~900ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                pressSpaceForQuickLook(attempt: attempt + 1)
            }
            return
        }
        let space: CGKeyCode = 49
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: space, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: space, keyDown: false) else { return }
        down.flags = []  // never inherit the still-held Command modifier
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Post Return to Finder, which toggles inline rename of the selected item:
    /// starts editing from the file list, commits/exits when already editing.
    private static func postReturnForRename() {
        let returnKey: CGKeyCode = 36
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: returnKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: returnKey, keyDown: false) else { return }
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func debugLog(_ message: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PathPal")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func startServices() {
        // Start Accessibility observer
        let axGranted = PermissionsService.shared.isAccessibilityGranted
        AppDelegate.debugLog("startServices: Accessibility granted = \(axGranted)")
        if axGranted {
            accessibilityService.start(
                onDialogDetected: { [weak self] dialog in
                    guard let self else { return }
                    let bundleID = NSRunningApplication(processIdentifier: dialog.pid)?.bundleIdentifier

                    // Per-app exclusion: leave this app's dialogs alone entirely.
                    // PathPal's own panels (Settings' folder picker, the demo)
                    // are handled explicitly, never via auto-detection.
                    if let bundleID,
                       SettingsService.shared.excludedBundleIDs.contains(bundleID)
                        || bundleID == Bundle.main.bundleIdentifier {
                        return
                    }

                    self.appState.currentDialog = dialog
                    self.overlayWindowService.showOverlay(for: dialog)
                    self.hotKeyService.setDialogActive(true)
                },
                onDialogDismissed: { [weak self] in
                    self?.appState.currentDialog = nil
                    self?.overlayWindowService.hideOverlay()
                    self?.hotKeyService.setDialogActive(false)
                }
            )
        }

        // Start Finder window polling
        startFinderPolling()

        // Register URL scheme handler for FinderSync toolbar button
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        hotKeyService.register(
            onPathBar: { [weak self] in
                guard SettingsService.shared.pathBarHotKeyEnabled else { return }
                self?.showPathBar()
            },
            onOpenFolder: {
                guard SettingsService.shared.finderOpenFolderHotKeyEnabled else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let action = FinderScriptingService.shared.actOnSelectedFinderItem()
                    // A file: trigger Quick Look by pressing Space in Finder
                    // (Finder is frontmost; the file is selected).
                    if action == .file {
                        DispatchQueue.main.async {
                            Self.pressSpaceForQuickLook()
                        }
                    }
                }
            },
            onRename: {
                guard SettingsService.shared.finderRenameHotKeyEnabled else { return }
                // Posting Return toggles Finder's inline rename: it starts
                // editing when the file list is focused, and commits/exits when
                // already editing.
                Self.postReturnForRename()
            }
        )

        // Backspace-to-parent in Finder (conditional event tap)
        FinderBackspaceService.shared.start()

        // Re-arm hotkeys / refresh the Backspace tap when their settings toggle
        NotificationCenter.default.addObserver(
            forName: .pathPalHotKeysChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hotKeyService.updateArming()
            FinderBackspaceService.shared.settingChanged()
        }

        // Update recent items from Finder
        updateRecentFromFinder()
    }

    // MARK: - Finder Polling

    private func startFinderPolling() {
        let interval = SettingsService.shared.finderPollingInterval
        finderPollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateRecentFromFinder()
        }
    }

    private func updateRecentFromFinder() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let windows = FinderScriptingService.shared.getFinderWindowsWithBounds().enumerated().map { index, window in
                FinderWindow(
                    windowID: CGWindowID(index),
                    title: window.name,
                    bounds: window.bounds,
                    path: window.path
                )
            }
            DispatchQueue.main.async {
                for window in windows {
                    self?.recentItemsService.addFolder(window.path)
                }
                self?.appState.finderWindows = windows
                self?.appState.finderWindowsUpdatedAt = Date()
                self?.appState.recentFolders = self?.recentItemsService.recentFolders ?? []
                self?.appState.recentFiles = self?.recentItemsService.recentFiles ?? []
                self?.menuBarService.refreshMenu()
            }
        }
    }

    // MARK: - URL Scheme Handler

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        if url.host == "pathbar" || url.path == "/pathbar" {
            showPathBar()
        }
    }

    // MARK: - Path Bar

    private func showPathBar() {
        if let existing = pathBarPanel, existing.isVisible {
            existing.close()
            pathBarPanel = nil
            return
        }

        // With an Open/Save dialog up, the path bar drives the dialog instead
        // of Finder.
        let dialog = appState.currentDialog
        let initialPath: String?
        if dialog != nil {
            initialPath = nil
        } else {
            initialPath = PathBarService.frontFinderWindowPathViaAX() ?? appState.finderWindows.first?.path
        }

        let navigate: (String) -> Void = { [weak self] path in
            if dialog != nil {
                self?.overlayWindowService.navigateCurrentDialog(toPath: path)
            } else {
                PathBarService.navigateFinder(to: path)
            }
        }

        let panel = PathBarPanel()
        let pathBarView = PathBarView(
            initialPath: initialPath,
            resolveFrontFinderPath: dialog != nil ? nil : { completion in
                DispatchQueue.global(qos: .userInitiated).async {
                    let path = FinderScriptingService.shared.getFinderWindows().first?.path
                    DispatchQueue.main.async { completion(path) }
                }
            },
            onNavigate: { [weak self] path in
                navigate(path)
                self?.pathBarPanel?.close()
                self?.pathBarPanel = nil
            },
            onOpen: { [weak self] path, target in
                if dialog != nil {
                    navigate(path)
                } else {
                    self?.openPath(path, in: target)
                }
                self?.pathBarPanel?.close()
                self?.pathBarPanel = nil
            },
            onDismiss: { [weak self] in
                self?.pathBarPanel?.close()
                self?.pathBarPanel = nil
            }
        )
        panel.contentView = NSHostingView(rootView: pathBarView)
        panel.onLostFocus = { [weak self] in
            self?.pathBarPanel?.close()
            self?.pathBarPanel = nil
        }
        panel.position(above: dialogFrameInCocoaCoords() ?? PathBarService.frontFinderWindowFrame())
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        pathBarPanel = panel
    }

    /// Current dialog's frame converted from AX (top-left origin) to Cocoa
    /// coordinates, for docking the path bar above it.
    private func dialogFrameInCocoaCoords() -> NSRect? {
        guard let dialog = appState.currentDialog,
              let bounds = OverlayWindowService.dialogBounds(for: dialog.element) else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: bounds.origin.x, y: primaryHeight - bounds.origin.y - bounds.height,
                      width: bounds.width, height: bounds.height)
    }

    private func openPath(_ path: String, in target: OpenTarget) {
        switch target {
        case .finder:
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .iTerm:
            let script = """
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                end if
                tell current session of current window
                    write text "cd \(path.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: " ", with: "\\\\ "))"
                end tell
            end tell
            """
            FinderScriptingService.shared.runAsync(script)
        }
    }

    // MARK: - Settings

    private func openSettings() {
        // Reuse existing window if still around
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PathPal Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        settingsWindow = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Watch for all windows closing to switch back to accessory
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowDidClose(_ notification: Notification) {
        // Check if any visible windows remain (excluding panels and status bar)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible && !(window is NSPanel) && window.className != "NSStatusBarWindow"
            }
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
                NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            }
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to PathPal"
        window.contentView = NSHostingView(rootView: OnboardingView(onComplete: { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.appState.hasCompletedOnboarding = true
            SettingsService.shared.hasCompletedOnboarding = true
            NSApp.setActivationPolicy(.accessory)
            self?.showDemoSavePanel()
        }))
        window.center()
        window.delegate = self

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
    }

    /// Right after onboarding, show PathPal's own save panel so the user sees
    /// the overlay in action within seconds of granting permissions. The
    /// overlay is triggered explicitly (auto-detection skips our own dialogs).
    private func showDemoSavePanel() {
        let panel = NSSavePanel()
        panel.message = "PathPal demo — a normal Save dialog. Use the panel beside it to jump folders, then press Cancel."
        panel.nameFieldStringValue = "PathPal Demo.txt"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] _ in
            self?.appState.currentDialog = nil
            self?.overlayWindowService.hideOverlay()
            self?.hotKeyService.setDialogActive(false)
            NSApp.setActivationPolicy(.accessory)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.appState.currentDialog == nil else { return }
            let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var windowRef: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
            guard let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return }
            let info = DialogInfo(
                pid: ProcessInfo.processInfo.processIdentifier,
                element: (windowRef as! AXUIElement),
                type: .save,
                appName: "PathPal"
            )
            self.appState.currentDialog = info
            self.overlayWindowService.showOverlay(for: info)
            self.hotKeyService.setDialogActive(true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === onboardingWindow else { return }
        onboardingWindow = nil
        SettingsService.shared.hasCompletedOnboarding = true
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityService.stop()
        hotKeyService.unregister()
        finderPollingTimer?.invalidate()
        recentItemsService.save()
    }
}
