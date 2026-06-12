import SwiftUI
import UniformTypeIdentifiers

struct FileDrawerView: View {
    var state: FileDrawerState
    let onAdd: ([URL]) -> Void
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
        .onHover { hovering in
            hoveredItem = hovering ? url.path : (hoveredItem == url.path ? nil : hoveredItem)
        }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                if let url {
                    DispatchQueue.main.async { onAdd([url]) }
                }
            }
        }
        return accepted
    }
}
