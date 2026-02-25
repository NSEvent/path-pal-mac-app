import AppKit
import SwiftUI

private func debugLog(_ message: String) {
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

final class OverlayWindowService {
    private var overlayPanel: OverlayPanel?
    private var tooltipPanel: NSPanel?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var moveMonitor: Any?
    private var currentDialog: DialogInfo?
    private var finderWindows: [(name: String, path: String, bounds: CGRect)] = []
    private let appState: AppState
    private let dialogNavigationService = DialogNavigationService()

    init(appState: AppState) {
        self.appState = appState
    }

    func showOverlay(for dialog: DialogInfo) {
        // If an overlay is already showing, don't create another one
        if overlayPanel != nil { return }

        currentDialog = dialog

        // Get Finder windows on a background thread to avoid blocking during modal dialogs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let windows = FinderScriptingService.shared.getFinderWindowsWithBounds()
            DispatchQueue.main.async {
                guard let self = self, self.currentDialog != nil else { return }
                self.finderWindows = windows
                debugLog("Found \(windows.count) Finder windows (via AppleScript)")
                for fw in windows {
                    debugLog("  Window: \(fw.name) at (\(fw.bounds.origin.x),\(fw.bounds.origin.y),\(fw.bounds.width),\(fw.bounds.height)) path=\(fw.path)")
                }

                // Update appState for the sidebar list
                self.appState.finderWindows = windows.enumerated().map { (i, fw) in
                    FinderWindow(windowID: CGWindowID(i), title: fw.name, bounds: fw.bounds, path: fw.path)
                }

                // Create overlay panel near the dialog
                let panel = OverlayPanel()
                let sidebarWindows = self.appState.finderWindows
                let contentView = OverlayPanelView(
                    finderWindows: sidebarWindows,
                    dialogType: dialog.type,
                    onFolderSelected: { [weak self] path in
                        self?.navigateDialog(toPath: path)
                    },
                    onDesktopSelected: { [weak self] in
                        let desktop = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Desktop").path
                        self?.navigateDialog(toPath: desktop)
                    },
                    onDismiss: { [weak self] in
                        self?.hideOverlay()
                    }
                )
                panel.contentView = NSHostingView(rootView: contentView)
                self.positionOverlay(panel, relativeTo: dialog)
                panel.orderFrontRegardless()
                debugLog("Overlay panel shown, isVisible=\(panel.isVisible), level=\(panel.level.rawValue), frame=\(panel.frame)")
                self.overlayPanel = panel

                // Start CGEvent tap for click interception + move monitor for tooltips
                self.startEventTap()
                self.startMoveMonitor()
            }
        }
    }

    func hideOverlay() {
        overlayPanel?.close()
        overlayPanel = nil
        stopEventTap()
        stopMoveMonitor()
        hideTooltip()
        currentDialog = nil
        finderWindows = []
    }

    private func navigateDialog(toPath path: String) {
        guard let dialog = currentDialog else { return }
        dialogNavigationService.navigateDialog(pid: dialog.pid, toPath: path)
    }

    // MARK: - CGEvent Tap for Click Interception

    private func startEventTap() {
        stopEventTap()

        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)

        // Use Unmanaged to pass self as userInfo
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }
                let service = Unmanaged<OverlayWindowService>.fromOpaque(userInfo).takeUnretainedValue()
                service.handleClickEvent(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        ) else {
            debugLog("[PathPal] Failed to create CGEvent tap — check Accessibility/Input Monitoring permissions")
            // Fall back to NSEvent global monitor
            startClickMonitorFallback()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        debugLog("[PathPal] CGEvent tap started for click interception")
    }

    private func startClickMonitorFallback() {
        debugLog("[PathPal] Using NSEvent global monitor fallback for clicks")
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.main else { return }
            let cgY = screen.frame.height - mouseLocation.y
            let cgPoint = CGPoint(x: mouseLocation.x, y: cgY)
            self.checkClickOnFinderWindow(at: cgPoint)
        }
    }

    private func handleClickEvent(_ event: CGEvent) {
        // CGEvent location is in screen coords with top-left origin
        let cgPoint = event.location
        checkClickOnFinderWindow(at: cgPoint)
    }

    private func checkClickOnFinderWindow(at cgPoint: CGPoint) {
        guard currentDialog != nil, !finderWindows.isEmpty else { return }

        // Don't intercept clicks on the overlay panel itself
        if let panel = overlayPanel {
            let panelFrame = panel.frame
            guard let screen = NSScreen.main else { return }
            // Convert panel frame (Cocoa bottom-left) to CG (top-left)
            let cgPanelY = screen.frame.height - panelFrame.origin.y - panelFrame.height
            let cgPanelRect = CGRect(x: panelFrame.origin.x, y: cgPanelY,
                                     width: panelFrame.width, height: panelFrame.height)
            if cgPanelRect.contains(cgPoint) {
                return
            }
        }

        // Check if click landed on any Finder window (bounds are already in CG top-left coords)
        if let matched = finderWindows.first(where: { $0.bounds.contains(cgPoint) }) {
            debugLog("Click matched Finder window: \(matched.name) path=\(matched.path)")
            DispatchQueue.main.async { [weak self] in
                self?.hideTooltip()
                self?.navigateDialog(toPath: matched.path)
            }
        }
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    // MARK: - Move Monitor (tooltip on hover)

    private func startMoveMonitor() {
        stopMoveMonitor()
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleGlobalMove()
        }
    }

    private var lastLoggedMove: Date = .distantPast

    private func handleGlobalMove() {
        guard currentDialog != nil, !finderWindows.isEmpty else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return }
        let cgY = screen.frame.height - mouseLocation.y
        let cgPoint = CGPoint(x: mouseLocation.x, y: cgY)

        // Log mouse position periodically for debugging
        if Date().timeIntervalSince(lastLoggedMove) > 2.0 {
            lastLoggedMove = Date()
            debugLog("Mouse at CG(\(Int(cgPoint.x)), \(Int(cgPoint.y))) Cocoa(\(Int(mouseLocation.x)), \(Int(mouseLocation.y))) — checking \(finderWindows.count) Finder windows")
        }

        // Don't show tooltip over the overlay panel
        if let panel = overlayPanel, panel.frame.contains(mouseLocation) {
            hideTooltip()
            return
        }

        if let matched = finderWindows.first(where: { $0.bounds.contains(cgPoint) }) {
            showTooltip(for: matched, at: mouseLocation)
        } else {
            hideTooltip()
        }
    }

    private func stopMoveMonitor() {
        if let monitor = moveMonitor {
            NSEvent.removeMonitor(monitor)
            moveMonitor = nil
        }
    }

    // MARK: - Tooltip

    private func showTooltip(for window: (name: String, path: String, bounds: CGRect), at mouseLocation: NSPoint) {
        let text = " \(window.name) — \(window.path) "

        if let existing = tooltipPanel {
            if let label = existing.contentView?.subviews.first as? NSTextField {
                if label.stringValue == text {
                    // Just update position
                    var frame = existing.frame
                    frame.origin = NSPoint(x: mouseLocation.x + 14, y: mouseLocation.y - 28)
                    existing.setFrame(frame, display: true)
                    return
                }
                label.stringValue = text
                label.sizeToFit()
                let size = NSSize(width: label.frame.width + 16, height: 24)
                let origin = NSPoint(x: mouseLocation.x + 14, y: mouseLocation.y - 28)
                existing.setFrame(NSRect(origin: origin, size: size), display: true)
            }
            return
        }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.sizeToFit()

        let size = NSSize(width: label.frame.width + 16, height: 24)
        let origin = NSPoint(x: mouseLocation.x + 14, y: mouseLocation.y - 28)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        label.frame = NSRect(x: 8, y: 2, width: label.frame.width, height: 20)
        container.addSubview(label)
        panel.contentView = container
        panel.orderFront(nil)
        tooltipPanel = panel
    }

    private func hideTooltip() {
        tooltipPanel?.close()
        tooltipPanel = nil
    }

    // MARK: - Overlay Positioning

    private func positionOverlay(_ panel: OverlayPanel, relativeTo dialog: DialogInfo) {
        var positionValue: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(dialog.element, kAXPositionAttribute as CFString, &positionValue)

        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(dialog.element, kAXSizeAttribute as CFString, &sizeValue)

        debugLog("positionOverlay: posResult=\(posResult.rawValue) sizeResult=\(sizeResult.rawValue)")

        var dialogOrigin = CGPoint.zero
        var dialogSize = CGSize(width: 500, height: 400)

        if let positionValue = positionValue {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &dialogOrigin)
        }
        if let sizeValue = sizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &dialogSize)
        }

        debugLog("positionOverlay: dialog at (\(dialogOrigin.x), \(dialogOrigin.y)) size (\(dialogSize.width) x \(dialogSize.height))")

        let panelWidth: CGFloat = 260
        let panelHeight: CGFloat = 400
        var x = dialogOrigin.x - panelWidth - 10
        let y = dialogOrigin.y

        if x < 0 {
            x = dialogOrigin.x + dialogSize.width + 10
        }

        if let screen = NSScreen.main {
            let cocoaY = screen.frame.height - y - panelHeight
            let frame = NSRect(x: x, y: cocoaY, width: panelWidth, height: panelHeight)
            debugLog("positionOverlay: panel frame = (\(frame.origin.x), \(frame.origin.y), \(frame.width), \(frame.height))")
            panel.setFrame(frame, display: true)
        } else {
            debugLog("positionOverlay: no main screen!")
        }
    }
}
