import Foundation

final class FinderScriptingService {
    static let shared = FinderScriptingService()

    /// Get all Finder window names and paths.
    func getFinderWindows() -> [(name: String, path: String)] {
        let script = """
        tell application "Finder"
            set wCount to count of Finder windows
            set resultLines to {}
            repeat with i from 1 to wCount
                try
                    set w to Finder window i
                    set windowName to name of w
                    set windowPath to POSIX path of ((target of w) as alias)
                    set end of resultLines to windowName & "||" & windowPath
                end try
            end repeat
            set tid to AppleScript's text item delimiters
            set AppleScript's text item delimiters to ASCII character 10
            set resultText to resultLines as text
            set AppleScript's text item delimiters to tid
            return resultText
        end tell
        """
        guard let result = runAppleScript(script) else { return [] }
        return result.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "||")
            guard parts.count == 2 else { return nil }
            return (name: parts[0], path: parts[1])
        }
    }

    /// Get all Finder windows with names, paths, and bounds (from AppleScript, no Screen Recording needed).
    func getFinderWindowsWithBounds() -> [(name: String, path: String, bounds: CGRect)] {
        let script = """
        tell application "Finder"
            set wCount to count of Finder windows
            set resultLines to {}
            repeat with i from 1 to wCount
                try
                    set w to Finder window i
                    set windowName to name of w
                    set windowPath to POSIX path of ((target of w) as alias)
                    set b to bounds of w
                    set bStr to ((item 1 of b) as text) & "," & ((item 2 of b) as text) & "," & ((item 3 of b) as text) & "," & ((item 4 of b) as text)
                    set end of resultLines to windowName & "||" & windowPath & "||" & bStr
                end try
            end repeat
            set tid to AppleScript's text item delimiters
            set AppleScript's text item delimiters to ASCII character 10
            set resultText to resultLines as text
            set AppleScript's text item delimiters to tid
            return resultText
        end tell
        """
        guard let result = runAppleScript(script) else { return [] }
        return result.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "||")
            guard parts.count == 3 else { return nil }
            let coords = parts[2].components(separatedBy: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard coords.count == 4 else { return nil }
            // AppleScript bounds: {left, top, right, bottom} in screen coords (top-left origin)
            let rect = CGRect(x: coords[0], y: coords[1], width: coords[2] - coords[0], height: coords[3] - coords[1])
            return (name: parts[0], path: parts[1], bounds: rect)
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
        // Use osascript subprocess instead of NSAppleScript to avoid blocking
        // during modal dialogs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        } catch {
            NSLog("[PathPal] osascript error: %@", error.localizedDescription)
            return nil
        }
    }
}
