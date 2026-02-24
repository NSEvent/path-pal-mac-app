import ApplicationServices
import AppKit

final class PermissionsService {
    static let shared = PermissionsService()

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permissions (shows system dialog).
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Trigger Automation permission prompt by sending an AppleEvent to Finder.
    /// Returns true if permission is granted.
    func requestAndCheckAutomationPermission() -> Bool {
        // Use a simple command that works even with no Finder windows
        let script = NSAppleScript(source: "tell application \"Finder\" to return name")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error, let errorNumber = error[NSAppleScript.errorNumber] as? Int {
            // -1743 = permission denied, -600 = app not running (not a permission issue)
            return errorNumber != -1743
        }
        return true
    }

    /// Open Accessibility preferences pane.
    func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
