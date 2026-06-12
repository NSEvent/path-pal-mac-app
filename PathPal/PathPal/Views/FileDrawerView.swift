import SwiftUI
import UniformTypeIdentifiers

struct FileDrawerView: View {
    var state: FileDrawerState
    /// Add URLs at an index (drop-to-insert), or append when index is nil.
    let onAdd: ([URL], Int?) -> Void
    let onRemove: (URL) -> Void
    let onClear: () -> Void

    @State private var isDropTargeted = false
    @State private var hoveredItem: String?

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
                .fill(hoveredItem == url.path ? Color.primary.opacity(0.07) : Color.clear)
        )
        .contentShape(Rectangle())
        // AppKit drag source behind the row content: starts a real dragging
        // session carrying the file URL, which Finder and dialogs accept.
        // SwiftUI's .onDrag can't do this here — the non-activating panel's
        // window-move-by-background would swallow the gesture.
        .background(FileDragSource(url: url))
        .onHover { hovering in
            hoveredItem = hovering ? url.path : (hoveredItem == url.path ? nil : hoveredItem)
        }
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

// MARK: - AppKit drag-out source

/// Transparent NSView behind each row that starts a real AppKit dragging
/// session with the file URL on mouse-drag. `mouseDownCanMoveWindow` is
/// disabled so the gesture drags the file, not the panel.
private struct FileDragSource: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.url = url
        return view
    }

    func updateNSView(_ view: DragSourceNSView, context: Context) {
        view.url = url
    }

    final class DragSourceNSView: NSView, NSDraggingSource {
        var url: URL?
        private var mouseDownLocation: NSPoint?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let url,
                  let start = mouseDownLocation,
                  hypot(event.locationInWindow.x - start.x,
                        event.locationInWindow.y - start.y) > 4 else { return }
            mouseDownLocation = nil

            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let size = NSSize(width: 32, height: 32)
            let point = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(
                NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                       width: size.width, height: size.height),
                contents: icon
            )
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .generic] : .generic
        }
    }
}
