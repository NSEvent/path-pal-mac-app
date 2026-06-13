import SwiftUI
import UniformTypeIdentifiers

struct FileDrawerView: View {
    var state: FileDrawerState
    /// Add URLs at an index (drop-to-insert), or append when index is nil.
    let onAdd: ([URL], Int?) -> Void
    let onRemove: (URL) -> Void
    let onClear: () -> Void
    /// Click on a row: routes to an open dialog, or manages selection.
    let onItemClick: (URL, Bool) -> Void
    /// Copy files into a drawer folder row used as a drop target.
    let onCopyInto: ([URL], URL) -> Void

    @State private var isDropTargeted = false
    @State private var hoveredItem: String?
    @State private var dropTargetedFolder: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("File Drawer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !state.items.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.bin")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all items")
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            if state.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.items, id: \.path) { url in
                            itemRow(url)
                        }
                        .onInsert(of: [UTType.fileURL]) { index, providers in
                            loadURLs(from: providers) { urls in
                                onAdd(urls, index)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: 190, height: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    lineWidth: isDropTargeted ? 2 : 0.5
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onPreferenceChange(RowFramesKey.self) { frames in
            state.rowFrames = frames
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Drag files here")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Park files, then drag them\nout anywhere")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func itemRow(_ url: URL) -> some View {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let isFolder = isDirectory.boolValue
        let isSelected = state.selectedPaths.contains(url.path)
        let isFolderDropTarget = dropTargetedFolder == url.path

        return HStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(url.deletingLastPathComponent().lastPathComponent)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            // Publish this row's frame so the panel can map mouse-downs to
            // rows and start drag-out sessions (see FileDrawerPanel.sendEvent).
            .background(GeometryReader { geo in
                Color.clear.preference(key: RowFramesKey.self,
                                       value: [url.path: geo.frame(in: .global)])
            })
            if hoveredItem == url.path {
                Button {
                    onRemove(url)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.25)
                      : hoveredItem == url.path ? Color.primary.opacity(0.07) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isFolderDropTarget ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredItem = hovering ? url.path : (hoveredItem == url.path ? nil : hoveredItem)
        }
        .onTapGesture {
            let commandKey = NSEvent.modifierFlags.contains(.command)
            onItemClick(url, commandKey)
        }
        .modifier(FolderDropTarget(
            isFolder: isFolder,
            isTargeted: Binding(
                get: { dropTargetedFolder == url.path },
                set: { dropTargetedFolder = $0 ? url.path : (dropTargetedFolder == url.path ? nil : dropTargetedFolder) }
            ),
            onDrop: { providers in
                loadURLs(from: providers) { urls in
                    onCopyInto(urls.filter { $0.path != url.path }, url)
                }
                return true
            }
        ))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }
        loadURLs(from: fileProviders) { urls in
            onAdd(urls, nil)
        }
        return true
    }

    /// Resolve file URLs from providers, preserving their order; completion
    /// runs on the main queue.
    private func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return }
        var results = [URL?](repeating: nil, count: fileProviders.count)
        let lock = NSLock()
        let group = DispatchGroup()
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                lock.lock()
                results[index] = url
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(results.compactMap { $0 })
        }
    }
}

// MARK: - Folder drop target

/// Folder rows accept file drops and copy the files into the folder; plain
/// file rows are left untouched so the list's insert gaps keep working.
private struct FolderDropTarget: ViewModifier {
    let isFolder: Bool
    let isTargeted: Binding<Bool>
    let onDrop: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        if isFolder {
            content.onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
                onDrop(providers)
            }
        } else {
            content
        }
    }
}

// MARK: - Row frame publishing

/// Row frames in SwiftUI global coordinates, keyed by file path. The panel
/// uses these to map mouse-downs to rows for drag-out.
struct RowFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
