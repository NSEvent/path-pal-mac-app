import Carbon
import AppKit

/// Cmd+L hotkey, armed only while Finder is frontmost.
/// Uses Carbon RegisterEventHotKey (not an NSEvent monitor) so the keystroke
/// is consumed — otherwise Finder also receives Cmd+L and beeps. Registering
/// per-activation keeps Cmd+L untouched in every other app (browsers etc.).
final class HotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onHotKey: (() -> Void)?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var dialogActive = false

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

    func register(onHotKey: @escaping () -> Void) {
        unregister()
        self.onHotKey = onHotKey

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                service.onHotKey?()
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
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.finder" || self?.dialogActive == true {
                self?.armHotKey()
            } else {
                self?.disarmHotKey()
                // Transient activations (open(1), our own panels) can bounce
                // focus straight back to Finder without a fresh didActivate
                // event — re-check shortly so the hotkey doesn't stay dead.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
                        self?.armHotKey()
                    }
                }
            }
        })

        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
            armHotKey()
        }
        HotKeyService.debugLog("Cmd+L Carbon hotkey installed (arms when Finder is frontmost)")
    }

    /// Arm Cmd+L while an Open/Save dialog is up in any app, so the path bar
    /// can drive the dialog. Disarms again when the dialog closes (unless
    /// Finder is frontmost, which keeps it armed as usual).
    func setDialogActive(_ active: Bool) {
        dialogActive = active
        if active {
            armHotKey()
        } else if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.finder" {
            disarmHotKey()
        }
    }

    private func armHotKey() {
        guard hotKeyRef == nil, SettingsService.shared.pathBarHotKeyEnabled else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5050_4C31), id: 1) // "PPL1"
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_L), UInt32(cmdKey), hotKeyID,
            GetEventDispatcherTarget(), 0, &hotKeyRef
        )
        HotKeyService.debugLog("Cmd+L armed (Finder frontmost), status \(status)")
    }

    private func disarmHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            HotKeyService.debugLog("Cmd+L disarmed (Finder resigned frontmost)")
        }
    }

    func unregister() {
        disarmHotKey()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
        workspaceObservers.removeAll()
        onHotKey = nil
    }

    deinit {
        unregister()
    }
}
