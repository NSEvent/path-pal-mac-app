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

    /// Check if Full Disk Access is granted by trying to read a TCC-protected file.
    var isFullDiskAccessGranted: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testPath = home.appendingPathComponent(
            "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl4"
        )
        return FileManager.default.isReadableFile(atPath: testPath.path)
    }

    /// Prompt the user to grant Full Disk Access.
    /// Shows an alert explaining why it's needed, then opens System Settings.
    func requestFullDiskAccess() {
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = "PathPal needs Full Disk Access to read your Finder sidebar favorites.\n\nClick \"Open Settings\" to go to System Settings, then toggle PathPal ON in the Full Disk Access list.\n\nAfter granting access, restart PathPal for the change to take effect."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Skip")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openFullDiskAccessPreferences()
        }
    }

    /// Open Accessibility preferences pane.
    func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open Full Disk Access preferences pane.
    func openFullDiskAccessPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
