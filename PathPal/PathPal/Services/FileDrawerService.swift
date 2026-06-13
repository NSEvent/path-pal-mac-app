import AppKit
import SwiftUI

/// Items shown in the file drawer, observable by SwiftUI.
@Observable
final class FileDrawerState {
    var items: [URL] = []
    /// Cmd-click multi-selection; a drag from a selected row carries them all.
    var selectedPaths: Set<String> = []
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

    /// Set by AppDelegate: routes a clicked item to the open Open/Save
    /// dialog. Returns false when no dialog is up.
    var dialogNavigator: ((String) -> Bool)?

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
        state.selectedPaths.remove(url.path)
        save()
    }

    func clear() {
        state.items.removeAll()
        state.selectedPaths.removeAll()
        save()
    }

    /// Click semantics: with a dialog open, clicking teleports the dialog to
    /// the item (folder, or file — Go To Folder selects files). Otherwise
    /// clicks manage the multi-selection used for group drag-out.
    func handleItemClick(_ url: URL, commandKey: Bool) {
        if dialogNavigator?(url.path) == true { return }
        if commandKey {
            if state.selectedPaths.contains(url.path) {
                state.selectedPaths.remove(url.path)
            } else {
                state.selectedPaths.insert(url.path)
            }
        } else if state.selectedPaths == [url.path] {
            state.selectedPaths.removeAll()
        } else {
            state.selectedPaths = [url.path]
        }
    }

    /// Copy files into a folder item (drawer folder rows act as drop targets).
    /// Collisions get a numbered suffix; never overwrites.
    func copyFiles(_ urls: [URL], into folder: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            for url in urls {
                guard url.standardizedFileURL.path != folder.path,
                      url.deletingLastPathComponent().path != folder.path else { continue }
                let base = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                var dest = folder.appendingPathComponent(url.lastPathComponent)
                var counter = 2
                while fm.fileExists(atPath: dest.path) {
                    let suffixed = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                    dest = folder.appendingPathComponent(suffixed)
                    counter += 1
                }
                try? fm.copyItem(at: url, to: dest)
            }
        }
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
                onClear: { [weak self] in self?.clear() },
                onItemClick: { [weak self] url, commandKey in self?.handleItemClick(url, commandKey: commandKey) },
                onCopyInto: { [weak self] urls, folder in self?.copyFiles(urls, into: folder) }
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
