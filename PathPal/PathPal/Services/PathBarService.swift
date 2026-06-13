import Foundation
import AppKit
import ApplicationServices

final class PathBarService {
    /// Finder's front window as an AXUIElement (focused, falling back to main).
    private static func frontFinderAXWindow() -> AXUIElement? {
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)

        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &windowRef)
        }
        guard let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        return (windowRef as! AXUIElement)
    }

    /// Front Finder window's folder, read synchronously via Accessibility.
    /// ~1 ms vs ~200 ms for the AppleScript round-trip, so the path bar can
    /// seed its field before first render. Returns nil for windows without
    /// an AXDocument (e.g. Recents), where the AppleScript fallback applies.
    static func frontFinderWindowPathViaAX() -> String? {
        guard let window = frontFinderAXWindow() else { return nil }
        var docRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef)
        guard let doc = docRef as? String else { return nil }
        if let url = URL(string: doc), url.isFileURL { return url.path }
        if doc.hasPrefix("/") { return doc }
        return nil
    }

    /// Front Finder window's frame in Cocoa (bottom-left origin) coordinates.
    static func frontFinderWindowFrame() -> NSRect? {
        guard let window = frontFinderAXWindow() else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let posRef, CFGetTypeID(posRef) == AXValueGetTypeID(),
              AXValueGetValue((posRef as! AXValue), .cgPoint, &position),
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID(),
              AXValueGetValue((sizeRef as! AXValue), .cgSize, &size),
              size.width > 0 else { return nil }
        // AX reports top-left-origin global coordinates; Cocoa wants
        // bottom-left relative to the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: position.x, y: primaryHeight - position.y - size.height,
                      width: size.width, height: size.height)
    }

    /// Recent folders used for bare-query fuzzy matching; injectable for tests.
    static var recentFoldersProvider: () -> [RecentFolder] = {
        RecentItemsService().recentFolders
    }

    /// Returns autocomplete suggestions for a partial path.
    /// "." and ".." components are resolved, so "/Users/kevin/Movies/.."
    /// lists the contents of /Users/kevin. Bare queries (no slash) fuzzy-match
    /// recent folders, frecency-ranked: "fbm" finds folder-buddy-mac-app.
    static func completions(for input: String) -> [String] {
        guard !input.isEmpty else { return [] }

        // Bare query — fuzzy over recent folders by name
        if !input.contains("/"), !input.hasPrefix("~") {
            let scored = recentFoldersProvider().compactMap { folder -> (folder: RecentFolder, score: Int)? in
                guard let score = fuzzyScore(query: input, candidate: folder.name) else { return nil }
                return (folder, score)
            }
            return scored
                .sorted { ($0.score, $0.folder.accessCount) > ($1.score, $1.folder.accessCount) }
                .map { $0.folder.path + "/" }
        }

        let expanded = (input as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        let lastComponent = (expanded as NSString).lastPathComponent
        let url = URL(fileURLWithPath: standardized)
        let fm = FileManager.default

        // "foo/", "foo/.." and "foo/." all reference a directory — list its contents
        if input.hasSuffix("/") || lastComponent == ".." || lastComponent == "." {
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

        let prefixMatches = contents
            .filter { $0.lastPathComponent.lowercased().hasPrefix(prefix) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        // Fall back to fuzzy subsequence matching when nothing prefix-matches
        let matches: [URL]
        if prefixMatches.isEmpty {
            matches = contents
                .compactMap { item -> (url: URL, score: Int)? in
                    guard let score = fuzzyScore(query: prefix, candidate: item.lastPathComponent) else { return nil }
                    return (item, score)
                }
                .sorted { $0.score > $1.score }
                .map(\.url)
        } else {
            matches = prefixMatches
        }

        return matches.map { item in
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir ? item.path + "/" : item.path
        }
    }

    /// Subsequence fuzzy score; nil when the query isn't a subsequence of the
    /// candidate. Word-boundary hits and consecutive runs score higher.
    static func fuzzyScore(query: String, candidate: String) -> Int? {
        guard !query.isEmpty else { return nil }
        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate.lowercased())
        var queryIndex = 0
        var score = 0
        var lastMatch = -2
        let boundaries: Set<Character> = ["-", "_", " ", "."]

        for (index, char) in candidateChars.enumerated() {
            guard queryIndex < queryChars.count else { break }
            guard char == queryChars[queryIndex] else { continue }
            var points = 1
            if index == 0 || boundaries.contains(candidateChars[index - 1]) { points += 3 }
            if index == lastMatch + 1 { points += 2 }
            score += points
            lastMatch = index
            queryIndex += 1
        }
        return queryIndex == queryChars.count ? score : nil
    }

    /// Navigate Finder to the given path. Runs off the main thread so a busy
    /// Finder can't beachball the app while the path bar dismisses.
    static func navigateFinder(to path: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            FinderScriptingService.shared.navigateFinderTo(path: path)
        }
    }
}
