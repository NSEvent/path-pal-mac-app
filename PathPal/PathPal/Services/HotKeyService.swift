import Carbon
import AppKit

final class HotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onHotKey: (() -> Void)?

    /// Register Cmd+L as a global hotkey.
    func register(onHotKey: @escaping () -> Void) {
        self.onHotKey = onHotKey

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, refcon -> OSStatus in
            guard let refcon = refcon else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<HotKeyService>.fromOpaque(refcon).takeUnretainedValue()

            // Only activate when Finder is frontmost
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               frontApp.bundleIdentifier == "com.apple.finder" {
                let callback = service.onHotKey
                DispatchQueue.main.async {
                    callback?()
                }
            }

            return noErr
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, refcon, &eventHandler)

        // Cmd+L: key code 37 = 'L'
        var hotKeyID = EventHotKeyID(signature: OSType(0x5050_414C), id: 1) // "PPAL"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
