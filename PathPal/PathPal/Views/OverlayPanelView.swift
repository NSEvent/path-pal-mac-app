import SwiftUI
import Combine

struct OverlayPanelView: View {
    let finderWindows: [FinderWindow]
    let dialogType: DialogType
    var keyCommands: AnyPublisher<OverlayKeyCommand, Never>?
    let onFolderSelected: (String) -> Void
    let onDesktopSelected: () -> Void
    let onDismiss: () -> Void

    @State private var recentFolders: [RecentFolder] = []
    @State private var recentFiles: [RecentFile] = []
    @State private var finderFavorites: [(name: String, path: String)] = []
    @State private var hoveredFinderWindow: CGWindowID?
    @State private var hoveredQuickAccess: String?
    @State private var selectedIndex: Int = -1

    private let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: - Quick Access Items

    private struct QuickAccessItem: Identifiable {
        let id: String
        let name: String
        let icon: String
        let tint: Color
        let action: () -> Void
    }

    private var quickAccessItems: [QuickAccessItem] {
        [
            QuickAccessItem(id: "desktop", name: "Desktop", icon: "desktopcomputer", tint: .gray, action: onDesktopSelected),
            QuickAccessItem(id: "documents", name: "Documents", icon: "doc.fill", tint: .blue, action: { onFolderSelected(home.appendingPathComponent("Documents").path) }),
            QuickAccessItem(id: "downloads", name: "Downloads", icon: "arrow.down.circle.fill", tint: .teal, action: { onFolderSelected(home.appendingPathComponent("Downloads").path) }),
            QuickAccessItem(id: "pictures", name: "Pictures", icon: "photo.fill", tint: .orange, action: { onFolderSelected(home.appendingPathComponent("Pictures").path) }),
            QuickAccessItem(id: "music", name: "Music", icon: "music.note", tint: .pink, action: { onFolderSelected(home.appendingPathComponent("Music").path) }),
            QuickAccessItem(id: "movies", name: "Movies", icon: "film", tint: .purple, action: { onFolderSelected(home.appendingPathComponent("Movies").path) }),
            QuickAccessItem(id: "home", name: "Home", icon: "house.fill", tint: .blue, action: { onFolderSelected(home.path) }),
        ]
    }

    // MARK: - Keyboard selection bookkeeping

    private var visibleRecentFolders: [RecentFolder] { Array(recentFolders.prefix(8)) }
    private var visibleRecentFiles: [RecentFile] {
        dialogType == .open ? Array(recentFiles.prefix(6)) : []
    }

    /// Flat selection order: Finder windows, Quick Access, favorites,
    /// recent folders, recent files.
    private var selectableCount: Int {
        finderWindows.count + quickAccessItems.count + finderFavorites.count
            + visibleRecentFolders.count + visibleRecentFiles.count
    }

    private func flatIndex(section: Int, offset: Int) -> Int {
        let sectionStarts = [
            0,
            finderWindows.count,
            finderWindows.count + quickAccessItems.count,
            finderWindows.count + quickAccessItems.count + finderFavorites.count,
            finderWindows.count + quickAccessItems.count + finderFavorites.count + visibleRecentFolders.count,
        ]
        return sectionStarts[section] + offset
    }

    private func activate(index: Int) {
        var i = index
        guard i >= 0 else { return }
        if i < finderWindows.count { onFolderSelected(finderWindows[i].path); return }
        i -= finderWindows.count
        if i < quickAccessItems.count { quickAccessItems[i].action(); return }
        i -= quickAccessItems.count
        if i < finderFavorites.count { onFolderSelected(finderFavorites[i].path); return }
        i -= finderFavorites.count
        if i < visibleRecentFolders.count { onFolderSelected(visibleRecentFolders[i].path); return }
        i -= visibleRecentFolders.count
        if i < visibleRecentFiles.count { onFolderSelected(visibleRecentFiles[i].path) }
    }

    private func handle(_ command: OverlayKeyCommand) {
        switch command {
        case .moveSelection(let delta):
            guard selectableCount > 0 else { return }
            if selectedIndex < 0 {
                selectedIndex = delta > 0 ? 0 : selectableCount - 1
            } else {
                selectedIndex = (selectedIndex + delta + selectableCount) % selectableCount
            }
        case .activateSelection:
            activate(index: selectedIndex)
        case .quickJump(let digit):
            // ⌃1–⌃7 Quick Access, ⌃8–⌃9 first favorites
            let jumpIndex = digit - 1
            if jumpIndex < quickAccessItems.count {
                quickAccessItems[jumpIndex].action()
            } else if jumpIndex - quickAccessItems.count < finderFavorites.count {
                onFolderSelected(finderFavorites[jumpIndex - quickAccessItems.count].path)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(dialogType == .open ? "Open in..." : "Save to...")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Finder Windows — hero section
                    if !finderWindows.isEmpty {
                        sectionHeader("Finder Windows")
                        ForEach(Array(finderWindows.enumerated()), id: \.element.id) { index, window in
                            finderWindowRow(window: window, isSelected: flatIndex(section: 0, offset: index) == selectedIndex)
                        }
                    }

                    // Quick Access — compact icon row
                    sectionHeader("Quick Access")
                    quickAccessRow

                    // Finder Favorites
                    if !finderFavorites.isEmpty {
                        sectionHeader("Favorites")
                        ForEach(Array(finderFavorites.enumerated()), id: \.offset) { index, fav in
                            folderRow(name: fav.name, path: fav.path, icon: "star.fill", tint: .orange,
                                      isSelected: flatIndex(section: 2, offset: index) == selectedIndex) {
                                onFolderSelected(fav.path)
                            }
                        }
                    }

                    // Recent Folders
                    if !visibleRecentFolders.isEmpty {
                        sectionHeader("Recent")
                        ForEach(Array(visibleRecentFolders.enumerated()), id: \.element.id) { index, folder in
                            folderRow(name: folder.name, path: folder.path, icon: "clock.fill", tint: .secondary,
                                      isSelected: flatIndex(section: 3, offset: index) == selectedIndex) {
                                onFolderSelected(folder.path)
                            }
                        }
                    }

                    // Recent Files — Open dialogs only; clicking selects the file
                    if !visibleRecentFiles.isEmpty {
                        sectionHeader("Recent Files")
                        ForEach(Array(visibleRecentFiles.enumerated()), id: \.element.id) { index, file in
                            folderRow(name: file.name, path: file.path, icon: "doc.text.fill", tint: .cyan,
                                      isSelected: flatIndex(section: 4, offset: index) == selectedIndex) {
                                onFolderSelected(file.path)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Divider()

            // Keyboard hints
            Text("⌃⌥↑↓ select · ⌃⌥↩ open · ⌃1–9 jump")
                .font(.system(size: 8.5))
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .frame(width: 250, height: 370)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            let recents = RecentItemsService()
            recentFolders = recents.recentFolders
            recentFiles = recents.recentFiles
            DispatchQueue.global(qos: .utility).async {
                let favorites = FinderFavoritesService.shared.getFavorites()
                DispatchQueue.main.async {
                    finderFavorites = favorites
                }
            }
        }
        .onReceive(keyCommands ?? Empty().eraseToAnyPublisher()) { command in
            handle(command)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: - Finder Window Row (Hero)

    private func finderWindowRow(window: FinderWindow, isSelected: Bool) -> some View {
        Button {
            onFolderSelected(window.path)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(window.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected || hoveredFinderWindow == window.windowID
                          ? Color.accentColor.opacity(isSelected ? 0.22 : 0.1)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredFinderWindow = isHovered ? window.windowID : nil
        }
    }

    // MARK: - Quick Access Icon Row

    private var quickAccessRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(quickAccessItems.enumerated()), id: \.element.id) { index, item in
                let isSelected = flatIndex(section: 1, offset: index) == selectedIndex
                Button(action: item.action) {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(item.tint)
                            .frame(width: 28, height: 24)
                        Text(item.name)
                            .font(.system(size: 8))
                            .foregroundStyle(hoveredQuickAccess == item.id || isSelected ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected
                                  ? Color.accentColor.opacity(0.22)
                                  : hoveredQuickAccess == item.id ? Color.primary.opacity(0.06) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredQuickAccess = isHovered ? item.id : nil
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Folder Row (Favorites / Recent / Files)

    private func folderRow(name: String, path: String, icon: String, tint: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
