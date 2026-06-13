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

    /// Vibrant, high-visibility handle gradient.
    private let handleGradient = LinearGradient(
        colors: [Color(red: 0.30, green: 0.36, blue: 1.0),
                 Color(red: 0.78, green: 0.20, blue: 0.95)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        // Always rendered at full height and pinned to the top by the hosting
        // panel; minimizing animates the window smaller and clips the list
        // behind the handle (no relayout = smooth roll-up).
        VStack(spacing: 0) {
            handle

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
        .frame(width: FileDrawerPanel.drawerWidth, height: FileDrawerPanel.fullHeight)
        // Faint material so the desktop/windows behind show through clearly.
        .background(.ultraThinMaterial.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.white.opacity(0.15)),
                    lineWidth: isDropTargeted ? 2 : 0.5
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onPreferenceChange(RowFramesKey.self) { frames in
            state.rowFrames = frames
        }
        .onPreferenceChange(HandleControlFramesKey.self) { frames in
            state.handleControlFrames = frames
        }
    }

    // MARK: - Vibrant handle (always visible; also the grab/move bar)

    // Controls are visual only; clicks route through FileDrawerPanel.sendEvent
    // (SwiftUI buttons don't fire reliably in this never-key panel). A click on
    // the handle toggles minimize, a click on the clear icon clears, a drag
    // moves the panel.
    private var handle: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text("File Drawer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            if !state.items.isEmpty {
                Text("\(state.items.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.25)))
            }
            Spacer(minLength: 0)
            if !state.isMinimized && !state.items.isEmpty {
                Image(systemName: "xmark.bin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: HandleControlFramesKey.self,
                                               value: ["clear": geo.frame(in: .global)])
                    })
                    .help("Clear all items")
            }
            Image(systemName: state.isMinimized ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .help(state.isMinimized ? "Expand drawer" : "Minimize drawer")
        }
        .padding(.horizontal, 10)
        .frame(height: FileDrawerPanel.handleHeight)
        .frame(maxWidth: .infinity)
        .background(handleGradient)
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
        // Row clicks are routed via FileDrawerPanel.sendEvent → onItemClick;
        // SwiftUI tap gestures never fire in this never-key panel.
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

/// Handle-control frames (e.g. "clear") in global coordinates, so the panel
/// can route handle clicks without relying on SwiftUI button hit-testing.
struct HandleControlFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
