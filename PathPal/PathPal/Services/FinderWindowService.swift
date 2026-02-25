import AppKit

final class FinderWindowService {
    private let scriptingService = FinderScriptingService.shared

    /// Get all visible Finder windows with positions and paths.
    func getFinderWindows() -> [FinderWindow] {
        let cgWindows = getCGFinderWindows()
        let asWindows = scriptingService.getFinderWindows()

        // Correlate by title — both APIs return front-to-back order
        var results: [FinderWindow] = []
        var usedASIndices = Set<Int>()

        for cgWin in cgWindows {
            for (i, asWin) in asWindows.enumerated() where !usedASIndices.contains(i) {
                if cgWin.title == asWin.name {
                    let finderWindow = FinderWindow(
                        windowID: cgWin.windowID,
                        title: cgWin.title,
                        bounds: cgWin.bounds,
                        path: asWin.path
                    )
                    results.append(finderWindow)
                    usedASIndices.insert(i)
                    break
                }
            }
        }
        return results
    }

    struct CGWindowEntry {
        let windowID: CGWindowID
        let title: String
        let bounds: CGRect
    }

    /// Parse CGWindowList dictionaries into entries filtered to Finder.
    static func parseCGWindowList(_ windowList: [[String: Any]]) -> [CGWindowEntry] {
        var entries: [CGWindowEntry] = []
        for dict in windowList {
            guard let ownerName = dict[kCGWindowOwnerName as String] as? String,
                  ownerName == "Finder",
                  let title = dict[kCGWindowName as String] as? String,
                  !title.isEmpty,
                  title != "Finder",  // Skip the desktop window
                  let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat else {
                continue
            }
            entries.append(CGWindowEntry(windowID: windowID, title: title, bounds: CGRect(x: x, y: y, width: w, height: h)))
        }
        return entries
    }

    private func getCGFinderWindows() -> [CGWindowEntry] {
        // Use .optionAll to get Finder windows even if behind other windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return Self.parseCGWindowList(windowList)
    }
}
