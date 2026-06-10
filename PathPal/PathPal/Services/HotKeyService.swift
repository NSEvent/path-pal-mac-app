import Carbon
import AppKit

final class HotKeyService {
    private var globalMonitor: Any?
    private var onHotKey: (() -> Void)?

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

    /// Register Cmd+L as a hotkey that only fires when Finder is frontmost.
    func register(onHotKey: @escaping () -> Void) {
        unregister()
        self.onHotKey = onHotKey

        HotKeyService.debugLog("Registering Cmd+L via NSEvent global monitor")

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Check for Cmd+L only (command key, no shift/opt/ctrl)
            guard flags == .command,
                  event.keyCode == UInt16(kVK_ANSI_L) else {
                return
            }

            if let frontApp = NSWorkspace.shared.frontmostApplication,
               frontApp.bundleIdentifier == "com.apple.finder" {
                HotKeyService.debugLog("Cmd+L fired in Finder — showing path bar")
                self?.onHotKey?()
            }
        }

        HotKeyService.debugLog("Cmd+L global monitor registered successfully")
    }

    func unregister() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        onHotKey = nil
    }

    deinit {
        unregister()
    }
}
