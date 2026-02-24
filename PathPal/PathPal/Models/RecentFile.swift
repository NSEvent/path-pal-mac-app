import Foundation

struct RecentFile: Codable, Identifiable, Equatable {
    var id: String { path }
    let path: String
    var lastAccessed: Date

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
