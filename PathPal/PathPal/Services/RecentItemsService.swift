import Foundation

final class RecentItemsService {
    private let settings = SettingsService.shared
    private let fileManager = FileManager.default
    private let storageURL: URL

    private(set) var recentFolders: [RecentFolder] = []
    private(set) var recentFiles: [RecentFile] = []

    init(storageDirectory: URL? = nil) {
        let baseDir = storageDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PathPal")
        self.storageURL = baseDir.appendingPathComponent("recent_items.json")

        if !fileManager.fileExists(atPath: baseDir.path) {
            try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: - Folder Tracking

    func addFolder(_ path: String) {
        let now = Date()
        if let idx = recentFolders.firstIndex(where: { $0.path == path }) {
            var folder = recentFolders.remove(at: idx)
            folder.lastAccessed = now
            folder.accessCount += 1
            recentFolders.insert(folder, at: 0)
        } else {
            let folder = RecentFolder(path: path, lastAccessed: now, accessCount: 1)
            recentFolders.insert(folder, at: 0)
        }
        trimFolders()
        save()
    }

    func addFile(_ path: String) {
        let now = Date()
        if let idx = recentFiles.firstIndex(where: { $0.path == path }) {
            var file = recentFiles.remove(at: idx)
            file.lastAccessed = now
            recentFiles.insert(file, at: 0)
        } else {
            let file = RecentFile(path: path, lastAccessed: now)
            recentFiles.insert(file, at: 0)
        }
        trimFiles()
        save()
    }

    func removeDeletedItems() {
        recentFolders.removeAll { !$0.exists }
        recentFiles.removeAll { !$0.exists }
        save()
    }

    // MARK: - Persistence

    private struct StorageData: Codable {
        var folders: [RecentFolder]
        var files: [RecentFile]
    }

    func load() {
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode(StorageData.self, from: data) else {
            return
        }
        recentFolders = stored.folders
        recentFiles = stored.files
    }

    func save() {
        let stored = StorageData(folders: recentFolders, files: recentFiles)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func trimFolders() {
        let max = settings.maxRecentFolders
        if recentFolders.count > max {
            recentFolders = Array(recentFolders.prefix(max))
        }
    }

    private func trimFiles() {
        let max = settings.maxRecentFiles
        if recentFiles.count > max {
            recentFiles = Array(recentFiles.prefix(max))
        }
    }
}
