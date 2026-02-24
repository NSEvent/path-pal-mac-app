import ApplicationServices
import AppKit

final class AccessibilityService {
    private var observers: [pid_t: AXObserver] = [:]
    private var onDialogDetected: ((DialogInfo) -> Void)?
    private var onDialogDismissed: (() -> Void)?

    func start(onDialogDetected: @escaping (DialogInfo) -> Void, onDialogDismissed: @escaping () -> Void) {
        self.onDialogDetected = onDialogDetected
        self.onDialogDismissed = onDialogDismissed

        // Watch existing apps
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observeApp(pid: app.processIdentifier, name: app.localizedName ?? "Unknown")
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
                .defaultMode
            )
        }
        observers.removeAll()
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
                service.handlePossibleDialog(element: element, pid: elementPid)
            } else if notificationStr == kAXUIElementDestroyedNotification {
                service.onDialogDismissed?()
            }
        }, &observer)

        guard result == .success, let observer = observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, appElement, kAXSheetCreatedNotification as CFString, refcon)

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        observers[pid] = observer
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    private func handlePossibleDialog(element: AXUIElement, pid: pid_t) {
        let buttonTitles = findButtonTitles(in: element)
        guard let dialogType = DialogInfo.classify(buttonTitles: buttonTitles) else { return }

        var pidValue = pid
        ApplicationServices.AXUIElementGetPid(element, &pidValue)

        let appName: String
        if let app = NSRunningApplication(processIdentifier: pidValue) {
            appName = app.localizedName ?? "Unknown"
        } else {
            appName = "Unknown"
        }

        let info = DialogInfo(pid: pidValue, element: element, type: dialogType, appName: appName)
        NSLog("[PathPal] Dialog detected: .%@ in %@", dialogType.rawValue, appName)

        DispatchQueue.main.async { [weak self] in
            self?.onDialogDetected?(info)
        }

        // Watch for destruction
        var observer: AXObserver?
        let createResult = AXObserverCreate(pidValue, { (_, _, notification, refcon) in
            guard let refcon = refcon else { return }
            let service = Unmanaged<AccessibilityService>.fromOpaque(refcon).takeUnretainedValue()
            service.onDialogDismissed?()
        }, &observer)

        if createResult == .success, let observer = observer {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    private func findButtonTitles(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 5 else { return [] }

        var titles: [String] = []
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        if let role = role as? String, role == kAXButtonRole {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            if let title = title as? String, !title.isEmpty {
                titles.append(title)
            }
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
