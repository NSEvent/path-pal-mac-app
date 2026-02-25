import ApplicationServices
import AppKit
import Carbon

final class DialogNavigationService {

    /// Navigate an Open/Save dialog to the specified path.
    func navigateDialog(pid: pid_t, toPath path: String) {
        NSLog("[PathPal] Navigating dialog (pid %d) to: %@", pid, path)

        // Reactivate the target app so the dialog is focused
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            NSLog("[PathPal] Could not find app for pid %d", pid)
            return
        }
        app.activate()
        NSLog("[PathPal] Activated app: %@", app.localizedName ?? "unknown")

        // Wait for app to become active, then send Cmd+Shift+G via HID tap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSLog("[PathPal] Sending Cmd+Shift+G via HID")
            Self.postKey(code: 5, flags: [.maskCommand, .maskShift]) // G

            // Wait for "Go to Folder" sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSLog("[PathPal] Pasting path via clipboard")

                // Save current clipboard, set path, paste, restore
                let pasteboard = NSPasteboard.general
                let oldContents = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                pasteboard.setString(path, forType: .string)

                // Select all then paste
                Self.postKey(code: 0, flags: [.maskCommand]) // Cmd+A
                usleep(50_000)
                Self.postKey(code: 9, flags: [.maskCommand]) // Cmd+V

                // Press Return to confirm, then restore clipboard
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSLog("[PathPal] Pressing Return")
                    Self.postKey(code: 36, flags: [])

                    // Restore clipboard after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let old = oldContents {
                            pasteboard.clearContents()
                            pasteboard.setString(old, forType: .string)
                        }
                    }
                }
            }
        }
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
