import Foundation

private func favLog(_ message: String) {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PathPal")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("debug.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] [Favorites] \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

final class FinderFavoritesService {
    static let shared = FinderFavoritesService()

    private var cachedFavorites: [(name: String, path: String)]?
    private var lastFetchTime: Date?
    private var failedOnce = false

    /// Returns Finder sidebar favorites in the same order they appear in Finder.
    /// Reads the TCC-protected sfl4 file; requires Full Disk Access.
    /// Caches results for 60 seconds. Stops retrying after first TCC failure
    /// (until app restart or explicit refresh).
    func getFavorites() -> [(name: String, path: String)] {
        // Return cached if fresh (< 60s old)
        if let cached = cachedFavorites, let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < 60 {
            return cached
        }

        // Don't keep retrying if we already know FDA is missing
        if failedOnce { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let sfl4Path = home.appendingPathComponent(
            "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl4"
        )

        if let results = parseSfl4(at: sfl4Path) {
            favLog("resolved \(results.count) favorites")
            cachedFavorites = results
            lastFetchTime = Date()
            return results
        }

        favLog("cannot read favorites — Full Disk Access required")
        failedOnce = true
        return []
    }

    /// Force a re-read (e.g., after user grants Full Disk Access)
    func refresh() {
        cachedFavorites = nil
        lastFetchTime = nil
        failedOnce = false
    }

    private func parseSfl4(at url: URL) -> [(name: String, path: String)]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else {
            return nil
        }

        var results: [(name: String, path: String)] = []
        for obj in objects {
            guard let bookmarkData = obj as? Data, bookmarkData.count > 48 else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withoutMounting],
                bookmarkDataIsStale: &isStale
            ) else { continue }
            let path = url.path
            if FileManager.default.fileExists(atPath: path) {
                results.append((name: url.lastPathComponent, path: path))
            }
        }
        return results.isEmpty ? nil : results
    }
}
