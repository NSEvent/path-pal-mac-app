import Cocoa
import FinderSync

class FinderSyncExtension: FIFinderSync {
    override init() {
        super.init()
        // Watch all volumes
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String {
        return "PathPal"
    }

    override var toolbarItemToolTip: String {
        return "Open PathPal"
    }

    override var toolbarItemImage: NSImage {
        return NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "PathPal")!
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "PathPal")

        let openItem = NSMenuItem(title: "Open in PathPal", action: #selector(openInPathPal(_:)), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        return menu
    }

    @objc func openInPathPal(_ sender: Any?) {
        guard let targetURL = FIFinderSyncController.default().targetedURL() else { return }

        // Communicate with main app via shared UserDefaults
        if let defaults = UserDefaults(suiteName: "com.kevintang.PathPal.group") {
            defaults.set(targetURL.path, forKey: "lastFinderSyncPath")
            defaults.synchronize()
        }

        // Launch or activate main app
        NSWorkspace.shared.open(URL(string: "pathpal://open")!)
    }
}
