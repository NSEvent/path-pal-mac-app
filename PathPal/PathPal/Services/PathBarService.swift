import Foundation

final class PathBarService {
    /// Returns autocomplete suggestions for a partial path.
    static func completions(for input: String) -> [String] {
        guard !input.isEmpty else { return [] }

        let expanded = (input as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let fm = FileManager.default

        // If input ends with "/", list directory contents
        if input.hasSuffix("/") {
            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return contents
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                .map { item in
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    return isDir ? item.path + "/" : item.path
                }
        }

        // Otherwise, complete the last component
        let parentURL = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent.lowercased()

        guard let contents = try? fm.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.lastPathComponent.lowercased().hasPrefix(prefix) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDir ? item.path + "/" : item.path
            }
    }

    /// Navigate Finder to the given path. Runs off the main thread so a busy
    /// Finder can't beachball the app while the path bar dismisses.
    static func navigateFinder(to path: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            FinderScriptingService.shared.navigateFinderTo(path: path)
        }
    }
}
