import AppKit

/// Maps Finder color label numbers (0-7) to colors.
enum FolderTag: Int, CaseIterable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    var color: NSColor? {
        switch self {
        case .none: return nil
        case .gray: return .systemGray
        case .green: return .systemGreen
        case .purple: return .systemPurple
        case .blue: return .systemBlue
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .orange: return .systemOrange
        }
    }

    var name: String {
        switch self {
        case .none: return "None"
        case .gray: return "Gray"
        case .green: return "Green"
        case .purple: return "Purple"
        case .blue: return "Blue"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .orange: return "Orange"
        }
    }

    /// Get the Finder tag for a file URL.
    static func forURL(_ url: URL) -> FolderTag? {
        guard let values = try? url.resourceValues(forKeys: [.labelNumberKey]),
              let labelNumber = values.labelNumber else {
            return nil
        }
        return FolderTag(rawValue: labelNumber)
    }
}
