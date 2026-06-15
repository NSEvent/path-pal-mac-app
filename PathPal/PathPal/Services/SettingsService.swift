import Foundation

extension Notification.Name {
    /// Posted when a hotkey-related setting changes so HotKeyService re-arms.
    static let pathPalHotKeysChanged = Notification.Name("PathPalHotKeysChanged")
}

final class SettingsService {
    static let shared = SettingsService()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let maxRecentFolders = "maxRecentFolders"
        static let maxRecentFiles = "maxRecentFiles"
        static let highlightFinderWindows = "highlightFinderWindows"
        static let showFinderWindowNames = "showFinderWindowNames"
        static let clickFinderWindowToChoose = "clickFinderWindowToChoose"
        static let clickDesktopToChoose = "clickDesktopToChoose"
        static let autoSelectLastFile = "autoSelectLastFile"
        static let defaultToDocumentFolder = "defaultToDocumentFolder"
        static let pathBarHotKeyEnabled = "pathBarHotKeyEnabled"
        static let finderPollingInterval = "finderPollingInterval"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let fileDrawerEnabled = "fileDrawerEnabled"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let finderOpenFolderHotKeyEnabled = "finderOpenFolderHotKeyEnabled"
        static let finderBackspaceToParentEnabled = "finderBackspaceToParentEnabled"
        static let fileDrawerMinimized = "fileDrawerMinimized"
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    var maxRecentFolders: Int {
        get {
            let val = defaults.integer(forKey: Keys.maxRecentFolders)
            return val > 0 ? val : 50
        }
        set { defaults.set(newValue, forKey: Keys.maxRecentFolders) }
    }

    var maxRecentFiles: Int {
        get {
            let val = defaults.integer(forKey: Keys.maxRecentFiles)
            return val > 0 ? val : 50
        }
        set { defaults.set(newValue, forKey: Keys.maxRecentFiles) }
    }

    var highlightFinderWindows: Bool {
        get { defaults.object(forKey: Keys.highlightFinderWindows) == nil ? true : defaults.bool(forKey: Keys.highlightFinderWindows) }
        set { defaults.set(newValue, forKey: Keys.highlightFinderWindows) }
    }

    var showFinderWindowNames: Bool {
        get { defaults.object(forKey: Keys.showFinderWindowNames) == nil ? true : defaults.bool(forKey: Keys.showFinderWindowNames) }
        set { defaults.set(newValue, forKey: Keys.showFinderWindowNames) }
    }

    var clickFinderWindowToChoose: Bool {
        get { defaults.object(forKey: Keys.clickFinderWindowToChoose) == nil ? true : defaults.bool(forKey: Keys.clickFinderWindowToChoose) }
        set { defaults.set(newValue, forKey: Keys.clickFinderWindowToChoose) }
    }

    var clickDesktopToChoose: Bool {
        get { defaults.object(forKey: Keys.clickDesktopToChoose) == nil ? true : defaults.bool(forKey: Keys.clickDesktopToChoose) }
        set { defaults.set(newValue, forKey: Keys.clickDesktopToChoose) }
    }

    var autoSelectLastFile: Bool {
        get { defaults.bool(forKey: Keys.autoSelectLastFile) }
        set { defaults.set(newValue, forKey: Keys.autoSelectLastFile) }
    }

    var defaultToDocumentFolder: Bool {
        get { defaults.bool(forKey: Keys.defaultToDocumentFolder) }
        set { defaults.set(newValue, forKey: Keys.defaultToDocumentFolder) }
    }

    var pathBarHotKeyEnabled: Bool {
        get { defaults.object(forKey: Keys.pathBarHotKeyEnabled) == nil ? true : defaults.bool(forKey: Keys.pathBarHotKeyEnabled) }
        set { defaults.set(newValue, forKey: Keys.pathBarHotKeyEnabled) }
    }

    var finderPollingInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: Keys.finderPollingInterval)
            return val > 0 ? val : 10.0
        }
        set { defaults.set(newValue, forKey: Keys.finderPollingInterval) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var fileDrawerEnabled: Bool {
        get { defaults.bool(forKey: Keys.fileDrawerEnabled) }
        set { defaults.set(newValue, forKey: Keys.fileDrawerEnabled) }
    }

    /// Apps whose Open/Save dialogs PathPal should leave alone entirely.
    var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? [] }
        set { defaults.set(newValue, forKey: Keys.excludedBundleIDs) }
    }

    /// Cmd+Return in Finder opens (navigates into) the selected folder. Opt-in.
    var finderOpenFolderHotKeyEnabled: Bool {
        get { defaults.bool(forKey: Keys.finderOpenFolderHotKeyEnabled) }
        set { defaults.set(newValue, forKey: Keys.finderOpenFolderHotKeyEnabled) }
    }

    /// Backspace in Finder navigates to the parent folder (except while editing
    /// text — renaming, search). Opt-in.
    var finderBackspaceToParentEnabled: Bool {
        get { defaults.bool(forKey: Keys.finderBackspaceToParentEnabled) }
        set { defaults.set(newValue, forKey: Keys.finderBackspaceToParentEnabled) }
    }

    /// Whether the file drawer is collapsed to its handle. Persisted so the
    /// chosen state survives relaunch.
    var fileDrawerMinimized: Bool {
        get { defaults.bool(forKey: Keys.fileDrawerMinimized) }
        set { defaults.set(newValue, forKey: Keys.fileDrawerMinimized) }
    }
}
