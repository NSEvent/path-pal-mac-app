import ApplicationServices

enum DialogType: String {
    case open
    case save
}

struct DialogInfo {
    let pid: pid_t
    let element: AXUIElement
    let type: DialogType
    let appName: String

    /// Classify a dialog based on button titles found in its AX children.
    static func classify(buttonTitles: [String]) -> DialogType? {
        let titles = Set(buttonTitles.map { $0.lowercased() })
        if titles.contains("save") || titles.contains("export") {
            return .save
        }
        if titles.contains("open") || titles.contains("upload") || titles.contains("choose") {
            return .open
        }
        return nil
    }
}
