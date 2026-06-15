import Carbon
import AppKit

/// Carbon global hotkeys, armed only in the contexts where they apply so they
/// never shadow the same keystroke elsewhere. RegisterEventHotKey (not an
/// NSEvent monitor) consumes the keystroke, so Finder doesn't also see it and
/// beep.
///
/// - **Cmd+L** — show the path bar. Armed while Finder is frontmost or an
///   Open/Save dialog is up.
/// - **Cmd+Return** — open (navigate into) the selected Finder folder, for
///   keyboard-only browsing. Armed while Finder is frontmost; opt-in.
/// - **F2** — rename the selected Finder item (Windows-style). Armed while
///   Finder is frontmost; opt-in.
final class HotKeyService {
    private enum HotKeyKind: UInt32 {
        case pathBar = 1
        case openFolder = 2
        case renameItem = 3
    }

    private var pathBarRef: EventHotKeyRef?
    private var openFolderRef: EventHotKeyRef?
    private var renameRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onPathBar: (() -> Void)?
    private var onOpenFolder: (() -> Void)?
    private var onRename: (() -> Void)?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var dialogActive = false

    private static let signature: OSType = 0x5050_414C // "PPAL"

    private static func debugLog(_ message: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PathPal")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func register(onPathBar: @escaping () -> Void, onOpenFolder: @escaping () -> Void, onRename: @escaping () -> Void) {
        unregister()
        self.onPathBar = onPathBar
        self.onOpenFolder = onOpenFolder
        self.onRename = onRename

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                switch HotKeyKind(rawValue: hotKeyID.id) {
                case .pathBar: service.onPathBar?()
                case .openFolder: service.onOpenFolder?()
                case .renameItem: service.onRename?()
                case nil: break
                }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateArming()
            // Transient activations (open(1), our own panels) can bounce focus
            // straight back to Finder without a fresh didActivate event —
            // re-check shortly so the hotkeys don't stay dead.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.updateArming()
            }
        })

        updateArming()
        HotKeyService.debugLog("Carbon hotkeys installed (Cmd+L, Cmd+Return)")
    }

    /// Arm Cmd+L while an Open/Save dialog is up in any app, so the path bar
    /// can drive the dialog.
    func setDialogActive(_ active: Bool) {
        dialogActive = active
        updateArming()
    }

    /// Re-evaluate which hotkeys should be armed for the current context.
    /// Call after any setting change too.
    func updateArming() {
        let finderFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"

        let wantPathBar = SettingsService.shared.pathBarHotKeyEnabled && (finderFront || dialogActive)
        setArmed(&pathBarRef, kind: .pathBar, keyCode: UInt32(kVK_ANSI_L),
                 modifiers: UInt32(cmdKey), want: wantPathBar)

        let wantOpenFolder = SettingsService.shared.finderOpenFolderHotKeyEnabled && finderFront
        setArmed(&openFolderRef, kind: .openFolder, keyCode: UInt32(kVK_Return),
                 modifiers: UInt32(cmdKey), want: wantOpenFolder)

        let wantRename = SettingsService.shared.finderRenameHotKeyEnabled && finderFront
        setArmed(&renameRef, kind: .renameItem, keyCode: UInt32(kVK_F2),
                 modifiers: 0, want: wantRename)
    }

    private func setArmed(_ ref: inout EventHotKeyRef?, kind: HotKeyKind, keyCode: UInt32, modifiers: UInt32, want: Bool) {
        if want, ref == nil {
            let id = EventHotKeyID(signature: Self.signature, id: kind.rawValue)
            RegisterEventHotKey(keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        } else if !want, let existing = ref {
            UnregisterEventHotKey(existing)
            ref = nil
        }
    }

    func unregister() {
        for ref in [pathBarRef, openFolderRef, renameRef].compactMap({ $0 }) {
            UnregisterEventHotKey(ref)
        }
        pathBarRef = nil
        openFolderRef = nil
        renameRef = nil
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
        workspaceObservers.removeAll()
        onPathBar = nil
        onOpenFolder = nil
        onRename = nil
    }

    deinit {
        unregister()
    }
}
