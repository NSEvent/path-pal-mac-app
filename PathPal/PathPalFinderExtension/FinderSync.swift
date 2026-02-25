import Cocoa
import FinderSync

class FinderSyncExtension: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String {
        return "PathPal"
    }

    override var toolbarItemToolTip: String {
        return "Open PathPal path bar"
    }

    override var toolbarItemImage: NSImage {
        return NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "PathPal")!
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "PathPal")

        let pathBarItem = NSMenuItem(title: "Open Path Bar", action: #selector(openPathBar(_:)), keyEquivalent: "")
        pathBarItem.target = self
        menu.addItem(pathBarItem)

        return menu
    }

    @objc func openPathBar(_ sender: Any?) {
        // Open path bar in main app via URL scheme
        if let url = URL(string: "pathpal://pathbar") {
            NSWorkspace.shared.open(url)
        }
    }
}
