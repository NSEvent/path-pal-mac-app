import AppKit
import SwiftUI

/// Items shown in the file drawer, observable by SwiftUI.
@Observable
final class FileDrawerState {
    var items: [URL] = []
    /// Row frames in SwiftUI global (top-left window) coordinates, published
    /// by the view so the panel can map mouse-downs to rows for drag-out.
    @ObservationIgnored var rowFrames: [String: CGRect] = [:]
}

/// A Default Folder X-style file drawer: a floating shelf users drag files
/// onto, then drag them back out anywhere (Finder, dialogs, other apps).
/// The shelf never steals focus and its contents persist across launches.
final class FileDrawerService {
    static let shared = FileDrawerService()
    static let visibilityChangedNotification = Notification.Name("PathPalFileDrawerVisibilityChanged")

    let state = FileDrawerState()
    private var panel: FileDrawerPanel?
    private let storageURL: URL
    private let maxItems = 50

    init(storageDirectory: URL? = nil) {
        let baseDir = storageDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PathPal")
        storageURL = baseDir.appendingPathComponent("drawer_items.json")
        if !FileManager.default.fileExists(atPath: baseDir.path) {
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: - Items

    /// Insert files at a specific position (drop-to-insert), or append at the
    /// end when no index is given. Re-adding an existing file moves it to the
    /// drop position, so dragging rows around reorders the list.
    func addFiles(_ urls: [URL], at index: Int? = nil) {
        var insertAt = min(index ?? state.items.count, state.items.count)
        for url in urls {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            if let existing = state.items.firstIndex(where: { $0.path == standardized.path }) {
                state.items.remove(at: existing)
                if existing < insertAt { insertAt -= 1 }
            }
            insertAt = max(0, min(insertAt, state.items.count))
            state.items.insert(standardized, at: insertAt)
            insertAt += 1
        }
        if state.items.count > maxItems {
            state.items = Array(state.items.prefix(maxItems))
        }
        save()
    }

    func removeFile(_ url: URL) {
        state.items.removeAll { $0.path == url.path }
        save()
    }

    func clear() {
        state.items.removeAll()
        save()
    }

    /// Drop entries whose files no longer exist on disk.
    func pruneMissingItems() {
        let before = state.items.count
        state.items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        if state.items.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        state.items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func save() {
        let paths = state.items.map(\.path)
        guard let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    // MARK: - Panel

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        pruneMissingItems()
        if panel == nil {
            panel = FileDrawerPanel(rootView: FileDrawerView(
                state: state,
                onAdd: { [weak self] urls, index in self?.addFiles(urls, at: index) },
                onRemove: { [weak self] url in self?.removeFile(url) },
                onClear: { [weak self] in self?.clear() }
            ), state: state)
        }
        panel?.orderFrontRegardless()
        NotificationCenter.default.post(name: Self.visibilityChangedNotification, object: nil)
    }

    func hide() {
        panel?.orderOut(nil)
        NotificationCenter.default.post(name: Self.visibilityChangedNotification, object: nil)
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    /// Settings toggle hook: the drawer exists while the feature is enabled.
    func setEnabled(_ enabled: Bool) {
        enabled ? show() : hide()
    }
}
