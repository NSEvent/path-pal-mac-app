import SwiftUI

struct OverlayPanelView: View {
    let finderWindows: [FinderWindow]
    let dialogType: DialogType
    let onFolderSelected: (String) -> Void
    let onDesktopSelected: () -> Void
    let onDismiss: () -> Void

    @State private var recentFolders: [RecentFolder] = []
    @State private var finderFavorites: [(name: String, path: String)] = []
    @State private var hoveredFinderWindow: CGWindowID?
    @State private var hoveredQuickAccess: String?

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
                        ForEach(finderWindows) { window in
                            finderWindowRow(window: window)
                        }
                    }

                    // Quick Access — compact icon row
                    sectionHeader("Quick Access")
                    quickAccessRow

                    // Finder Favorites
                    if !finderFavorites.isEmpty {
                        sectionHeader("Favorites")
                        ForEach(Array(finderFavorites.enumerated()), id: \.offset) { _, fav in
                            folderRow(name: fav.name, path: fav.path, icon: "star.fill", tint: .orange) {
                                onFolderSelected(fav.path)
                            }
                        }
                    }

                    // Recent Folders
                    if !recentFolders.isEmpty {
                        sectionHeader("Recent")
                        ForEach(recentFolders.prefix(8)) { folder in
                            folderRow(name: folder.name, path: folder.path, icon: "clock.fill", tint: .secondary) {
                                onFolderSelected(folder.path)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .frame(width: 250, height: 370)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            recentFolders = RecentItemsService().recentFolders
            finderFavorites = FinderFavoritesService.shared.getFavorites()
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

    private func finderWindowRow(window: FinderWindow) -> some View {
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
                    .fill(hoveredFinderWindow == window.windowID
                          ? Color.accentColor.opacity(0.1)
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
            ForEach(quickAccessItems) { item in
                Button(action: item.action) {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(item.tint)
                            .frame(width: 28, height: 24)
                        Text(item.name)
                            .font(.system(size: 8))
                            .foregroundStyle(hoveredQuickAccess == item.id ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(hoveredQuickAccess == item.id
                                  ? Color.primary.opacity(0.06)
                                  : Color.clear)
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

    // MARK: - Folder Row (Favorites / Recent)

    private func folderRow(name: String, path: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
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
        }
        .buttonStyle(.plain)
    }
}
