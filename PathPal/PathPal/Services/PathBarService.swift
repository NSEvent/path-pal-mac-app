import Foundation
import AppKit
import ApplicationServices

final class PathBarService {
    /// Front Finder window's folder, read synchronously via Accessibility.
    /// ~1 ms vs ~200 ms for the AppleScript round-trip, so the path bar can
    /// seed its field before first render. Returns nil for windows without
    /// an AXDocument (e.g. Recents), where the AppleScript fallback applies.
    static func frontFinderWindowPathViaAX() -> String? {
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)

        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &windowRef)
        }
        guard let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement

        var docRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef)
        guard let doc = docRef as? String else { return nil }
        if let url = URL(string: doc), url.isFileURL { return url.path }
        if doc.hasPrefix("/") { return doc }
        return nil
    }

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
