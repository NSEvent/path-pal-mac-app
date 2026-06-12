import ApplicationServices
import AppKit
import Carbon

final class DialogNavigationService {

    /// Navigate an Open/Save dialog to the specified path.
    /// Uses Cmd+Shift+G to open "Go to Folder", then sets the path via Accessibility API
    /// (no clipboard manipulation, no fixed delays).
    func navigateDialog(pid: pid_t, toPath path: String) {
        NSLog("[PathPal] Navigating dialog (pid %d) to: %@", pid, path)

        // Reactivate the target app so the dialog is focused
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            NSLog("[PathPal] Could not find app for pid %d", pid)
            return
        }
        app.activate()
        NSLog("[PathPal] Activated app: %@", app.localizedName ?? "unknown")

        // Snapshot the currently focused element before triggering Go to Folder
        let systemWide = AXUIElementCreateSystemWide()
        var preFocusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &preFocusedRef)
        let preFocused = Self.asAXUIElement(preFocusedRef)

        // Wait for app to become active, then send Cmd+Shift+G
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            NSLog("[PathPal] Sending Cmd+Shift+G via HID")
            Self.postKey(code: 5, flags: [.maskCommand, .maskShift]) // G

            // Poll for the Go to Folder text field to appear
            self.pollForGoToFolderField(
                pid: pid,
                path: path,
                preFocused: preFocused,
                attempt: 0
            )
        }
    }

    /// Poll the AX tree to find the Go to Folder text field, then set its value.
    private func pollForGoToFolderField(pid: pid_t, path: String, preFocused: AXUIElement?, attempt: Int) {
        // Give up after ~3 seconds (30 attempts * 100ms)
        guard attempt < 30 else {
            NSLog("[PathPal] Timed out waiting for Go to Folder field")
            return
        }

        // Check the currently focused element — after Cmd+Shift+G, focus moves to the Go to Folder text field
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        if let focusedElement = Self.asAXUIElement(focusedRef) {

            // Check if the focused element is a text field or combo box (the Go to Folder input)
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &role)
            let roleStr = role as? String ?? ""

            let isTextField = roleStr == kAXTextFieldRole || roleStr == kAXComboBoxRole || roleStr == kAXTextAreaRole

            // Make sure it's a different element than what was focused before Cmd+Shift+G
            let isDifferent = preFocused == nil || !CFEqual(focusedElement, preFocused!)

            if isTextField && isDifferent {
                NSLog("[PathPal] Found Go to Folder field (role: %@), setting path via AX", roleStr)

                // Set the path value directly via Accessibility API
                let result = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, path as CFTypeRef)
                NSLog("[PathPal] AXSetValue result: %d", result.rawValue)

                if result == .success {
                    // Press Return to confirm navigation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NSLog("[PathPal] Pressing Return to confirm")
                        Self.postKey(code: 36, flags: []) // Return
                    }
                } else {
                    // Fallback: type the path character by character via CGEvent
                    NSLog("[PathPal] AXSetValue failed, falling back to keystroke typing")
                    Self.postKey(code: 0, flags: [.maskCommand]) // Cmd+A to select all first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        Self.typeString(path)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            Self.postKey(code: 36, flags: []) // Return
                        }
                    }
                }
                return
            }
        }

        // Not found yet — try again in 100ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pollForGoToFolderField(pid: pid, path: path, preFocused: preFocused, attempt: attempt + 1)
        }
    }

    /// Type-checked conversion from a CFTypeRef attribute value to AXUIElement.
    private static func asAXUIElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Post a key event to the currently active application via HID event tap.
    private static func postKey(code: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            NSLog("[PathPal] Failed to create CGEvent")
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Type a string by posting unicode keyboard events to the active application.
    private static func typeString(_ string: String) {
        let chars = Array(string.utf16)
        let chunkSize = 20
        for i in stride(from: 0, to: chars.count, by: chunkSize) {
            let end = min(i + chunkSize, chars.count)
            var chunk = Array(chars[i..<end])

            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                continue
            }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
