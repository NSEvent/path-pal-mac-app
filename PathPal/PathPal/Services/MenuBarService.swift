import AppKit

final class MenuBarService: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let appState: AppState
    private let recentItemsService: RecentItemsService
    private var onOpenSettings: (() -> Void)?
    private var onShowPathBar: (() -> Void)?

    init(appState: AppState, recentItemsService: RecentItemsService) {
        self.appState = appState
        self.recentItemsService = recentItemsService
        super.init()
    }

    func setup(onOpenSettings: @escaping () -> Void, onShowPathBar: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onShowPathBar = onShowPathBar

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "PathPal")
        }
        statusItem?.menu = buildMenu()
    }

    func refreshMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let home = FileManager.default.homeDirectoryForCurrentUser

        // Quick Access submenu
        let quickAccessItem = NSMenuItem(title: "Quick Access", action: nil, keyEquivalent: "")
        let quickAccessSubmenu = NSMenu()
        let quickAccessFolders: [(name: String, path: String, icon: String)] = [
            ("Desktop", home.appendingPathComponent("Desktop").path, "desktopcomputer"),
            ("Documents", home.appendingPathComponent("Documents").path, "doc.fill"),
            ("Downloads", home.appendingPathComponent("Downloads").path, "arrow.down.circle.fill"),
            ("Pictures", home.appendingPathComponent("Pictures").path, "photo.fill"),
            ("Music", home.appendingPathComponent("Music").path, "music.note"),
            ("Movies", home.appendingPathComponent("Movies").path, "film"),
            ("Home", home.path, "house.fill"),
        ]
        for qa in quickAccessFolders {
            let item = NSMenuItem(title: qa.name, action: #selector(openFolder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = qa.path
            item.image = NSImage(systemSymbolName: qa.icon, accessibilityDescription: qa.name)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            item.toolTip = qa.path
            // Add lazy-loaded children submenu
            let childMenu = NSMenu()
            childMenu.delegate = self
            childMenu.addItem(NSMenuItem(title: "Loading...", action: nil, keyEquivalent: ""))
            item.submenu = childMenu
            item.tag = 1
            quickAccessSubmenu.addItem(item)
        }
        quickAccessItem.submenu = quickAccessSubmenu
        menu.addItem(quickAccessItem)

        // Finder Favorites submenu
        let favorites = FinderFavoritesService.shared.getFavorites()
        if !favorites.isEmpty {
            let favoritesItem = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            let favoritesSubmenu = NSMenu()
            for fav in favorites {
                let item = NSMenuItem(title: fav.name, action: #selector(openFolder(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = fav.path
                item.image = NSWorkspace.shared.icon(forFile: fav.path).resized(to: NSSize(width: 16, height: 16))
                item.toolTip = fav.path
                let childMenu = NSMenu()
                childMenu.delegate = self
                childMenu.addItem(NSMenuItem(title: "Loading...", action: nil, keyEquivalent: ""))
                item.submenu = childMenu
                item.tag = 1
                favoritesSubmenu.addItem(item)
            }
            favoritesItem.submenu = favoritesSubmenu
            menu.addItem(favoritesItem)
        }

        // Recent Folders submenu
        let foldersItem = NSMenuItem(title: "Recent Folders", action: nil, keyEquivalent: "")
        let foldersSubmenu = NSMenu()
        foldersSubmenu.delegate = self

        let folders = recentItemsService.recentFolders.prefix(SettingsService.shared.maxRecentFolders)
        if folders.isEmpty {
            foldersSubmenu.addItem(NSMenuItem(title: "No recent folders", action: nil, keyEquivalent: ""))
        } else {
            for folder in folders {
                let item = NSMenuItem(title: folder.name, action: #selector(openFolder(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = folder.path
                item.image = folderIcon(for: folder)
                item.toolTip = folder.path

                let childMenu = NSMenu()
                childMenu.delegate = self
                childMenu.addItem(NSMenuItem(title: "Loading...", action: nil, keyEquivalent: ""))
                item.submenu = childMenu
                item.tag = 1

                foldersSubmenu.addItem(item)
            }
        }
        foldersItem.submenu = foldersSubmenu
        menu.addItem(foldersItem)

        // Recent Files submenu
        let filesItem = NSMenuItem(title: "Recent Files", action: nil, keyEquivalent: "")
        let filesSubmenu = NSMenu()

        let files = recentItemsService.recentFiles.prefix(SettingsService.shared.maxRecentFiles)
        if files.isEmpty {
            filesSubmenu.addItem(NSMenuItem(title: "No recent files", action: nil, keyEquivalent: ""))
        } else {
            for file in files {
                let item = NSMenuItem(title: file.name, action: #selector(openFile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = file.path
                item.image = NSWorkspace.shared.icon(forFile: file.path).resized(to: NSSize(width: 16, height: 16))
                item.toolTip = file.path
                filesSubmenu.addItem(item)
            }
        }
        filesItem.submenu = filesSubmenu
        menu.addItem(filesItem)

        menu.addItem(.separator())

        let pathBarItem = NSMenuItem(title: "Go to Folder...", action: #selector(showPathBar), keyEquivalent: "")
        pathBarItem.target = self
        menu.addItem(pathBarItem)

        if SettingsService.shared.fileDrawerEnabled {
            let drawerItem = NSMenuItem(
                title: FileDrawerService.shared.isVisible ? "Hide File Drawer" : "Show File Drawer",
                action: #selector(toggleFileDrawer),
                keyEquivalent: ""
            )
            drawerItem.target = self
            menu.addItem(drawerItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit PathPal", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - NSMenuDelegate (lazy child loading)

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Find the parent item for this submenu
        guard let parentItem = menu.supermenu?.items.first(where: { $0.submenu === menu }),
              parentItem.tag == 1,
              let path = parentItem.representedObject as? String else {
            return
        }

        menu.removeAllItems()
        loadChildren(for: path, into: menu, depth: 0)

        if menu.items.isEmpty {
            menu.addItem(NSMenuItem(title: "(empty)", action: nil, keyEquivalent: ""))
        }
    }

    private func loadChildren(for path: String, into menu: NSMenu, depth: Int) {
        let url = URL(fileURLWithPath: path)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .labelNumberKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = contents.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        for childURL in sorted.prefix(30) {
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let item = NSMenuItem(
                title: childURL.lastPathComponent,
                action: isDir ? #selector(openFolder(_:)) : #selector(openFile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = childURL.path
            item.image = NSWorkspace.shared.icon(forFile: childURL.path).resized(to: NSSize(width: 16, height: 16))

            // Add another level of children for directories (up to 2 levels deep)
            if isDir && depth < 1 {
                let childMenu = NSMenu()
                childMenu.delegate = self
                childMenu.addItem(NSMenuItem(title: "Loading...", action: nil, keyEquivalent: ""))
                item.submenu = childMenu
                item.tag = 1
            }

            menu.addItem(item)
        }
    }

    private func folderIcon(for folder: RecentFolder) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: folder.path).resized(to: NSSize(width: 16, height: 16))
        return icon
    }

    // MARK: - Actions

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        recentItemsService.addFolder(path)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        recentItemsService.addFile(path)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func showPathBar() {
        onShowPathBar?()
    }

    @objc private func toggleFileDrawer() {
        FileDrawerService.shared.toggleVisibility()
        refreshMenu()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSImage resizing helper

extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        img.unlockFocus()
        return img
    }
}
