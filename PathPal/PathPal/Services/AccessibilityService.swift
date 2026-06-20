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
                // Try quickly first; keep slower retries for apps that build sheets lazily.
                for delay in [0.05, 0.15, 0.3, 0.8, 1.5] {
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

            if let candidate = DialogInfo.candidate(inApp: pid) {
                let boundsDescription = candidate.bounds.map { "\($0)" } ?? "unavailable"
                axDebugLog("Found existing dialog: \(candidate.type.rawValue) in \(appName), bounds=\(boundsDescription)")
                startDialogPolling(pid: pid)
                let info = DialogInfo(pid: pid, element: candidate.element, type: candidate.type, appName: appName)
                DispatchQueue.main.async { [weak self] in
                    self?.onDialogDetected?(info)
                }
                return
            }
        }
    }

    private var handledNotificationIDs: Set<UUID> = []

    private func handlePossibleDialog(element: AXUIElement, pid: pid_t, notificationID: UUID = UUID()) {
        // If this notification was already handled by an earlier retry, skip
        if handledNotificationIDs.contains(notificationID) { return }

        guard let candidate = DialogInfo.candidate(from: element, pid: pid) else {
            return
        }

        // Mark this notification as handled so later retry attempts are skipped
        handledNotificationIDs.insert(notificationID)

        var pidValue = pid
        ApplicationServices.AXUIElementGetPid(candidate.element, &pidValue)

        let appName: String
        if let app = NSRunningApplication(processIdentifier: pidValue) {
            appName = app.localizedName ?? "Unknown"
        } else {
            appName = "Unknown"
        }

        let info = DialogInfo(pid: pidValue, element: candidate.element, type: candidate.type, appName: appName)
        let boundsDescription = candidate.bounds.map { "\($0)" } ?? "unavailable"
        axDebugLog("Dialog detected: \(candidate.type.rawValue) in \(appName), bounds=\(boundsDescription)")

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

            // Use the same strict candidate resolver as initial detection.
            let dialogStillOpen = DialogInfo.candidate(inApp: self.currentDialogPid) != nil

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

}
