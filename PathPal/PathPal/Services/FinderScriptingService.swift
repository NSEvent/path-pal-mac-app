import Foundation

final class FinderScriptingService {
    static let shared = FinderScriptingService()

    /// Get all Finder window names and paths.
    func getFinderWindows() -> [(name: String, path: String)] {
        let script = """
        tell application "Finder"
            set windowList to {}
            repeat with w in windows
                try
                    set windowName to name of w
                    set windowPath to POSIX path of (target of w as alias)
                    set end of windowList to windowName & "||" & windowPath
                end try
            end repeat
            set AppleScript's text item delimiters to "\\n"
            return windowList as text
        end tell
        """
        guard let result = runAppleScript(script) else { return [] }
        return result.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "||")
            guard parts.count == 2 else { return nil }
            return (name: parts[0], path: parts[1])
        }
    }

    /// Navigate the front Finder window to a path.
    func navigateFinderTo(path: String) {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            set target of front window to (POSIX file "\(escaped)" as alias)
            activate
        end tell
        """
        _ = runAppleScript(script)
    }

    /// Open a path in Finder.
    func openInFinder(path: String) {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            open (POSIX file "\(escaped)" as alias)
            activate
        end tell
        """
        _ = runAppleScript(script)
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error = error {
            NSLog("[PathPal] AppleScript error: %@", error)
            return nil
        }
        return result.stringValue
    }
}
