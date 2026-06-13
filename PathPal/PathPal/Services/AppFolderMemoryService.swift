import AppKit

/// Per-app folder memory ("rebound"): remembers the last folder each app's
/// dialogs were navigated to through PathPal, and auto-navigates that app's
/// next dialog there. A user-pinned folder beats the learned one and is
/// never overwritten by learning.
final class AppFolderMemoryService {
    static let shared = AppFolderMemoryService()

    struct Entry: Codable, Equatable {
        var appName: String
        var path: String
        var pinned: Bool
    }

    private(set) var entries: [String: Entry] = [:] // keyed by bundle ID
    private let storageURL: URL

    init(storageDirectory: URL? = nil) {
        let baseDir = storageDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PathPal")
        storageURL = baseDir.appendingPathComponent("app_folders.json")
        if !FileManager.default.fileExists(atPath: baseDir.path) {
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        load()
    }

    /// The folder this app's dialogs should start in, if one is known and
    /// still exists on disk.
    func folder(forBundleID bundleID: String) -> String? {
        guard let entry = entries[bundleID] else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return entry.path
    }

    /// Learn from a navigation. File paths record their containing folder.
    /// Pinned entries are never overwritten by learning.
    func recordNavigation(toPath path: String, bundleID: String, appName: String) {
        if let existing = entries[bundleID], existing.pinned { return }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        let folder = (exists && isDirectory.boolValue) ? path : (path as NSString).deletingLastPathComponent
        guard !folder.isEmpty, folder != "/" || path == "/" else { return }
        entries[bundleID] = Entry(appName: appName, path: folder, pinned: false)
        save()
    }

    func setPinned(_ pinned: Bool, forBundleID bundleID: String) {
        guard var entry = entries[bundleID] else { return }
        entry.pinned = pinned
        entries[bundleID] = entry
        save()
    }

    func setFolder(_ path: String, forBundleID bundleID: String) {
        guard var entry = entries[bundleID] else { return }
        entry.path = path
        entries[bundleID] = entry
        save()
    }

    func removeEntry(forBundleID bundleID: String) {
        entries.removeValue(forKey: bundleID)
        save()
    }

    /// Entries sorted for display: pinned first, then by app name.
    var sortedEntries: [(bundleID: String, entry: Entry)] {
        entries.map { (bundleID: $0.key, entry: $0.value) }
            .sorted {
                if $0.entry.pinned != $1.entry.pinned { return $0.entry.pinned }
                return $0.entry.appName.localizedCaseInsensitiveCompare($1.entry.appName) == .orderedAscending
            }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
