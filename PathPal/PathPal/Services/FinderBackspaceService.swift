import AppKit
import ApplicationServices

/// Plain Backspace navigates the front Finder window to its parent folder —
/// but only when the user isn't editing text (renaming a file, typing in the
/// search field), so it never eats a real backspace.
///
/// This needs a *conditional* consume, so it's a CGEvent tap rather than a
/// Carbon hotkey (which would consume Backspace unconditionally and break
/// renaming). The tap is installed only while Finder is frontmost and the
/// feature is enabled, to avoid intercepting keystrokes anywhere else.
final class FinderBackspaceService {
    static let shared = FinderBackspaceService()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObservers: [NSObjectProtocol] = []

    private static let backspaceKeyCode: Int64 = 51 // kVK_Delete

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateTap() })
        updateTap()
    }

    /// Call when the enabling setting changes.
    func settingChanged() { updateTap() }

    private var shouldRun: Bool {
        SettingsService.shared.finderBackspaceToParentEnabled
            && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    private func updateTap() {
        if shouldRun { installTap() } else { removeTap() }
    }

    // MARK: - Tap lifecycle

    private func installTap() {
        guard tap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let t = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<FinderBackspaceService>.fromOpaque(userInfo).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = service.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }

                if service.shouldConsume(event) {
                    DispatchQueue.main.async {
                        DispatchQueue.global(qos: .userInitiated).async {
                            FinderScriptingService.shared.navigateToParent()
                        }
                    }
                    return nil // consume the Backspace
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else { return }

        tap = t
        runLoopSource = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func removeTap() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            tap = nil
            runLoopSource = nil
        }
    }

    // MARK: - Decision

    private func shouldConsume(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.backspaceKeyCode else { return false }
        // Plain Backspace only — let Cmd/Opt/Ctrl variants through untouched.
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) {
            return false
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return false }
        // Only act when we're CONFIDENT the focus isn't an editable text field —
        // any uncertainty falls through so a real backspace is never eaten.
        return finderFocusAllowsNavigation()
    }

    /// True only when Finder's focused element is confirmed to be a
    /// non-text-editing control (file list, browser, etc.). Any AX failure or a
    /// text-editing role returns false so Backspace passes through.
    private func finderFocusAllowsNavigation() -> Bool {
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder").first else { return false }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05) // never block the event tap

        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        // No focused element → nothing is being edited; safe to navigate.
        if err == .noValue { return true }
        guard err == .success, let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return false }
        let element = focusedRef as! AXUIElement

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else { return false }
        let role = roleRef as? String ?? ""

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String ?? ""

        let editing = role == kAXTextFieldRole
            || role == kAXTextAreaRole
            || role == kAXComboBoxRole
            || subrole == "AXSearchField"
        return !editing
    }
}
