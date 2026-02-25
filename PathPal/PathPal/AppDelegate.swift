import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appState = AppState()
    private var menuBarService: MenuBarService!
    private let recentItemsService = RecentItemsService()
    private let accessibilityService = AccessibilityService()
    private var overlayWindowService: OverlayWindowService!
    private var pathBarPanel: PathBarPanel?
    private var finderPollingTimer: Timer?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no dock icon
        NSApp.setActivationPolicy(.accessory)

        // Set up menu bar
        menuBarService = MenuBarService(appState: appState, recentItemsService: recentItemsService)
        menuBarService.setup(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onShowPathBar: { [weak self] in self?.showPathBar() }
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
    }

    private func startServices() {
        // Start Accessibility observer
        if PermissionsService.shared.isAccessibilityGranted {
            accessibilityService.start(
                onDialogDetected: { [weak self] dialog in
                    self?.appState.currentDialog = dialog
                    self?.overlayWindowService.showOverlay(for: dialog)
                },
                onDialogDismissed: { [weak self] in
                    self?.appState.currentDialog = nil
                    self?.overlayWindowService.hideOverlay()
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
            let windows = FinderScriptingService.shared.getFinderWindows()
            DispatchQueue.main.async {
                for window in windows {
                    self?.recentItemsService.addFolder(window.path)
                }
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

        let panel = PathBarPanel()
        let pathBarView = PathBarView(
            onNavigate: { [weak self] path in
                PathBarService.navigateFinder(to: path)
                self?.pathBarPanel?.close()
                self?.pathBarPanel = nil
            },
            onOpen: { [weak self] path, target in
                self?.openPath(path, in: target)
                self?.pathBarPanel?.close()
                self?.pathBarPanel = nil
            },
            onDismiss: { [weak self] in
                self?.pathBarPanel?.close()
                self?.pathBarPanel = nil
            }
        )
        panel.contentView = NSHostingView(rootView: pathBarView)
        panel.positionAboveFinderWindow()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        pathBarPanel = panel
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
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
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
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
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
        }))
        window.center()
        window.delegate = self

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === onboardingWindow else { return }
        onboardingWindow = nil
        SettingsService.shared.hasCompletedOnboarding = true
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityService.stop()
        finderPollingTimer?.invalidate()
        recentItemsService.save()
    }
}

