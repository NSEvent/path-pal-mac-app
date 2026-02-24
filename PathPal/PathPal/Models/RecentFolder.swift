import Foundation

struct RecentFolder: Codable, Identifiable, Equatable {
    var id: String { path }
    let path: String
    var lastAccessed: Date
    var accessCount: Int

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }

    var exists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
