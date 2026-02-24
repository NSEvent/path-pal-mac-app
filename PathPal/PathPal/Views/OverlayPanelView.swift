import SwiftUI

struct OverlayPanelView: View {
    let finderWindows: [FinderWindow]
    let dialogType: DialogType
    let onFolderSelected: (String) -> Void
    let onDesktopSelected: () -> Void
    let onDismiss: () -> Void

    @State private var recentFolders: [RecentFolder] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(dialogType == .open ? "Open in..." : "Save to...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Finder Windows section
                    if !finderWindows.isEmpty {
                        sectionHeader("Finder Windows")
                        ForEach(finderWindows) { window in
                            folderRow(name: window.name, path: window.path, icon: "folder.fill") {
                                onFolderSelected(window.path)
                            }
                        }
                    }

                    // Quick Access
                    sectionHeader("Quick Access")
                    folderRow(name: "Desktop", path: "~/Desktop", icon: "desktopcomputer") {
                        onDesktopSelected()
                    }
                    folderRow(name: "Documents", path: "~/Documents", icon: "doc.fill") {
                        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path
                        onFolderSelected(path)
                    }
                    folderRow(name: "Downloads", path: "~/Downloads", icon: "arrow.down.circle.fill") {
                        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
                        onFolderSelected(path)
                    }
                    folderRow(name: "Home", path: "~", icon: "house.fill") {
                        onFolderSelected(FileManager.default.homeDirectoryForCurrentUser.path)
                    }

                    // Recent Folders
                    if !recentFolders.isEmpty {
                        sectionHeader("Recent Folders")
                        ForEach(recentFolders.prefix(10)) { folder in
                            folderRow(name: folder.name, path: folder.path, icon: "clock.fill") {
                                onFolderSelected(folder.path)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .frame(width: 250, height: 390)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            let service = RecentItemsService()
            recentFolders = service.recentFolders
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func folderRow(name: String, path: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(path)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
        )
    }
}
