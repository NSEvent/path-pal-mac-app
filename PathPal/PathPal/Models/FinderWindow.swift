import CoreGraphics
import Foundation

struct FinderWindow: Identifiable, Equatable {
    let windowID: CGWindowID
    let title: String
    let bounds: CGRect
    let path: String

    var id: CGWindowID { windowID }

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }

    static func == (lhs: FinderWindow, rhs: FinderWindow) -> Bool {
        lhs.windowID == rhs.windowID && lhs.title == rhs.title && lhs.path == rhs.path
    }
}
