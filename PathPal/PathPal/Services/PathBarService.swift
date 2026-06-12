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

    /// Returns autocomplete suggestions for a partial path.
    /// "." and ".." components are resolved, so "/Users/kevin/Movies/.."
    /// lists the contents of /Users/kevin.
    static func completions(for input: String) -> [String] {
        guard !input.isEmpty else { return [] }

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
