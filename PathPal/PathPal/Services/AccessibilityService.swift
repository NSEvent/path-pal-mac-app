import ApplicationServices
import AppKit

private func axDebugLog(_ message: String) {
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

final class AccessibilityService {
    private var observers: [pid_t: AXObserver] = [:]
    private var destructionObservers: [AXObserver] = []
    private var onDialogDetected: ((DialogInfo) -> Void)?
    private var onDialogDismissed: (() -> Void)?
    private var dialogPollingTimer: Timer?
    private var currentDialogPid: pid_t = 0
    func start(onDialogDetected: @escaping (DialogInfo) -> Void, onDialogDismissed: @escaping () -> Void) {
        self.onDialogDetected = onDialogDetected
        self.onDialogDismissed = onDialogDismissed

        // Watch existing apps
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observeApp(pid: app.processIdentifier, name: app.localizedName ?? "Unknown")
        }

        // Check if there's already an active dialog (e.g., if PathPal restarted while a dialog is open)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkExistingDialogs()
        }

        // Watch for new app launches
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for (_, observer) in observers {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observers.removeAll()
        for observer in destructionObservers {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        destructionObservers.removeAll()
        handledNotificationIDs.removeAll()
        dialogPollingTimer?.invalidate()
        dialogPollingTimer = nil
        currentDialogPid = 0
    }

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        observeApp(pid: app.processIdentifier, name: app.localizedName ?? "Unknown")
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        removeObserver(pid: app.processIdentifier)
    }

    private func observeApp(pid: pid_t, name: String) {
        guard observers[pid] == nil else { return }
        // Skip Finder — we don't want to intercept its own windows
        if name == "Finder" { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let service = Unmanaged<AccessibilityService>.fromOpaque(refcon).takeUnretainedValue()
            let notificationStr = notification as String

            if notificationStr == kAXWindowCreatedNotification || notificationStr == kAXSheetCreatedNotification {
                var elementPid: pid_t = 0
                ApplicationServices.AXUIElementGetPid(element, &elementPid)
                axDebugLog("Possible dialog from pid \(elementPid) (notification: \(notificationStr))")
                // Use a unique ID to link retries for this notification
                let notificationID = UUID()
                // Try multiple delays to let the dialog UI fully build
                for delay in [0.3, 0.8, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        service.handlePossibleDialog(element: element, pid: elementPid, notificationID: notificationID)
                    }
                }
            }
        }, &observer)

        guard result == .success, let observer = observer else {
            axDebugLog("Failed to create AXObserver for \(name) (pid \(pid)), result: \(result.rawValue)")
            return
        }
        axDebugLog("Observing \(name) (pid \(pid))")

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, appElement, kAXSheetCreatedNotification as CFString, refcon)

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        observers[pid] = observer
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    /// Check all running apps for an already-open Open/Save dialog
    /// Only considers windows whose title or subrole indicates a dialog (not regular app windows)
    private func checkExistingDialogs() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            let appName = app.localizedName ?? "Unknown"
            if appName == "Finder" { continue }

            let appElement = AXUIElementCreateApplication(pid)
            var windows: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
            guard let windows = windows as? [AXUIElement] else { continue }

            for window in windows {
                // Only check windows that look like dialogs (title is "Open", "Save", etc.
                // or subrole is AXDialog/AXSheet)
                var subrole: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
                var title: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)

                let subroleStr = subrole as? String ?? ""
                let titleStr = (title as? String ?? "").lowercased()

                let isLikelyDialog = subroleStr == "AXDialog" || subroleStr == "AXSheet"
                    || titleStr == "open" || titleStr == "save" || titleStr == "save as"
                    || titleStr.hasPrefix("open ") || titleStr.hasPrefix("save ")

                guard isLikelyDialog else { continue }

                let titles = findButtonTitles(in: window, depth: 0)
                if let dialogType = DialogInfo.classify(buttonTitles: titles) {
                    axDebugLog("Found existing dialog: \(dialogType.rawValue) in \(appName)")
                    startDialogPolling(pid: pid)
                    let info = DialogInfo(pid: pid, element: window, type: dialogType, appName: appName)
                    DispatchQueue.main.async { [weak self] in
                        self?.onDialogDetected?(info)
                    }
                    return
                }
            }
        }
    }

    private var handledNotificationIDs: Set<UUID> = []

    private func handlePossibleDialog(element: AXUIElement, pid: pid_t, notificationID: UUID = UUID()) {
        // If this notification was already handled by an earlier retry, skip
        if handledNotificationIDs.contains(notificationID) { return }

        // Try the element itself first
        var buttonTitles = findButtonTitles(in: element, depth: 0)

        // Also check sheets attached to this window
        if buttonTitles.isEmpty {
            var sheets: CFTypeRef?
            AXUIElementCopyAttributeValue(element, "AXSheets" as CFString, &sheets)
            if let sheets = sheets as? [AXUIElement] {
                for sheet in sheets {
                    buttonTitles.append(contentsOf: findButtonTitles(in: sheet, depth: 0))
                }
            }
        }

        // Also try the focused window of this app
        if buttonTitles.isEmpty {
            let appElement = AXUIElementCreateApplication(pid)
            var focusedWindow: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
            if let focusedWindow = focusedWindow {
                buttonTitles = findButtonTitles(in: (focusedWindow as! AXUIElement), depth: 0)
            }
        }

        guard let dialogType = DialogInfo.classify(buttonTitles: buttonTitles) else {
            return
        }

        // Mark this notification as handled so later retry attempts are skipped
        handledNotificationIDs.insert(notificationID)

        var pidValue = pid
        ApplicationServices.AXUIElementGetPid(element, &pidValue)

        let appName: String
        if let app = NSRunningApplication(processIdentifier: pidValue) {
            appName = app.localizedName ?? "Unknown"
        } else {
            appName = "Unknown"
        }

        let info = DialogInfo(pid: pidValue, element: element, type: dialogType, appName: appName)
        axDebugLog("Dialog detected: \(dialogType.rawValue) in \(appName)")

        // Start polling to detect when the dialog is dismissed
        startDialogPolling(pid: pidValue)

        DispatchQueue.main.async { [weak self] in
            self?.onDialogDetected?(info)
        }
    }

    /// Poll the app to detect when its Open/Save dialog is dismissed.
    /// Checks whether the app still has a window with Open/Save/Cancel buttons.
    private func startDialogPolling(pid: pid_t) {
        dialogPollingTimer?.invalidate()
        currentDialogPid = pid

        dialogPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.currentDialogPid != 0 else { return }

            // Check if the app still has a dialog open by scanning its windows
            let appElement = AXUIElementCreateApplication(self.currentDialogPid)
            var windows: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)

            var dialogStillOpen = false
            if let windows = windows as? [AXUIElement] {
                for window in windows {
                    let titles = self.findButtonTitles(in: window, depth: 0)
                    if DialogInfo.classify(buttonTitles: titles) != nil {
                        dialogStillOpen = true
                        break
                    }
                }
            }

            if !dialogStillOpen {
                axDebugLog("Dialog polling: no dialog found in pid \(self.currentDialogPid), dismissing")
                self.dialogPollingTimer?.invalidate()
                self.dialogPollingTimer = nil
                self.currentDialogPid = 0
                self.handledNotificationIDs.removeAll()
                self.onDialogDismissed?()
            }
        }
    }

    private func findButtonTitles(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 10 else { return [] }

        var titles: [String] = []
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String

        // Found a button — grab its title
        if roleStr == kAXButtonRole {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            if let title = title as? String, !title.isEmpty {
                titles.append(title)
            }
            return titles
        }

        // Skip content containers that can be huge (file lists, tables, etc.)
        let skipRoles: Set<String> = [
            kAXScrollAreaRole, kAXTableRole, kAXOutlineRole, kAXListRole,
            kAXBrowserRole, "AXWebArea"
        ]
        if let roleStr = roleStr, skipRoles.contains(roleStr) {
            return []
        }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if let children = children as? [AXUIElement] {
            for child in children {
                titles.append(contentsOf: findButtonTitles(in: child, depth: depth + 1))
            }
        }

        return titles
    }
}
