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
    private var isShowingOverlay = false  // Guards against race during async overlay creation
    private var tooltipPanel: NSPanel?
    private var highlightWindows: [HighlightWindow] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var moveMonitor: Any?
    private var currentDialog: DialogInfo?
    private var dialogBoundsCG: CGRect = .zero  // Dialog bounds in CG coords (top-left origin)
    private var finderWindows: [(name: String, path: String, bounds: CGRect)] = []
    private let appState: AppState
    private let dialogNavigationService = DialogNavigationService()

    init(appState: AppState) {
        self.appState = appState
    }

    func showOverlay(for dialog: DialogInfo) {
        // If an overlay is already showing or being created, don't create another one
        if overlayPanel != nil || isShowingOverlay { return }
        isShowingOverlay = true

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

                // Show highlight overlays on Finder windows
                if SettingsService.shared.highlightFinderWindows {
                    self.showHighlightWindows()
                }

                // Start CGEvent tap for click interception + move monitor for tooltips
                self.startEventTap()
                self.startMoveMonitor()
            }
        }
    }

    func hideOverlay() {
        overlayPanel?.close()
        overlayPanel = nil
        isShowingOverlay = false
        hideHighlightWindows()
        stopEventTap()
        stopMoveMonitor()
        hideTooltip()
        currentDialog = nil
        dialogBoundsCG = .zero
        finderWindows = []
    }

    // MARK: - Finder Window Highlights

    private func showHighlightWindows() {
        hideHighlightWindows()

        var excludeRects: [CGRect] = []

        if let dialog = currentDialog,
           let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            var pidRects: [CGRect] = []
            for entry in windowList {
                guard let pidVal = entry[kCGWindowOwnerPID as String] as? Int,
                      pid_t(pidVal) == dialog.pid,
                      let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = boundsDict["X"], let y = boundsDict["Y"],
                      let w = boundsDict["Width"], let h = boundsDict["Height"] else { continue }
                pidRects.append(CGRect(x: x, y: y, width: w, height: h))
            }
            excludeRects = Self.dialogExclusionRects(dialogBounds: dialogBoundsCG, pidRects: pidRects)
        }

        // Also exclude the overlay sidebar panel
        if let panel = overlayPanel, let screen = NSScreen.main {
            let pf = panel.frame
            let cgPanelY = screen.frame.height - pf.origin.y - pf.height
            let panelCG = CGRect(x: pf.origin.x, y: cgPanelY, width: pf.width, height: pf.height)
            excludeRects.append(panelCG.insetBy(dx: -12, dy: -12))
        }

        for (colorIndex, fw) in appState.finderWindows.enumerated() {
            let visibleRegions = subtractRects(from: fw.bounds, excluding: excludeRects)
            for region in visibleRegions {
                let clippedFW = FinderWindow(windowID: fw.windowID, title: fw.title, bounds: region, path: fw.path)
                let hw = HighlightWindow(finderWindow: clippedFW, colorIndex: colorIndex)
                hw.onClick = { [weak self] in
                    guard let self = self else { return }
                    let mouseLocation = NSEvent.mouseLocation
                    guard let screen = NSScreen.main else { return }
                    let cgY = screen.frame.height - mouseLocation.y
                    let cgPoint = CGPoint(x: mouseLocation.x, y: cgY)

                    // Check if click is on any pill label (topmost first)
                    for candidate in self.highlightWindows.reversed() {
                        if candidate.pillFrameInScreenCG.contains(cgPoint) {
                            debugLog("Pill click: \(candidate.finderPath)")
                            self.navigateDialog(toPath: candidate.finderPath)
                            return
                        }
                    }

                    // No pill hit — navigate to clicked highlight's path
                    debugLog("Highlight click: \(fw.title) path=\(fw.path)")
                    self.navigateDialog(toPath: fw.path)
                }
                hw.onRightClick = { [weak self, weak hw] in
                    guard let self = self, let hw = hw else { return }
                    self.dismissHighlightWindow(hw)
                }
                hw.orderFrontRegardless()
                highlightWindows.append(hw)
            }
        }

        // Re-activate the dialog's app so its window (with the Open/Save dialog)
        // comes back above the highlights. The sidebar panel at .screenSaver level
        // stays on top regardless.
        if let dialog = currentDialog {
            NSRunningApplication(processIdentifier: dialog.pid)?.activate()
        }

        debugLog("Showed \(highlightWindows.count) highlight windows (clipped around \(excludeRects.count) exclusion rects)")
    }

    /// Determine which windows from the dialog's PID should be excluded from highlights.
    /// Excludes PID windows that overlap at least 50% of the dialog's area — this catches
    /// the dialog itself and its parent/host window, but not unrelated windows from the
    /// same app at different screen positions.
    static func dialogExclusionRects(dialogBounds: CGRect, pidRects: [CGRect]) -> [CGRect] {
        guard !dialogBounds.isEmpty else { return [] }
        let dialogArea = dialogBounds.width * dialogBounds.height
        guard dialogArea > 0 else { return [] }
        var result: [CGRect] = []
        for rect in pidRects {
            let intersection = rect.intersection(dialogBounds)
            guard !intersection.isNull && !intersection.isEmpty else { continue }
            let overlapArea = intersection.width * intersection.height
            if overlapArea / dialogArea > 0.5 {
                let rectArea = rect.width * rect.height
                if rectArea > dialogArea * 2 {
                    // Oversized parent window (e.g. fullscreen Chrome) — only
                    // exclude the dialog-sized region, not the entire window.
                    result.append(dialogBounds.insetBy(dx: -40, dy: -40))
                } else {
                    // Dialog-sized window — exclude at full size.
                    result.append(rect.insetBy(dx: -40, dy: -40))
                }
            }
        }
        return result
    }

    /// Subtract excluding rects from a source rect, returning visible regions.
    /// Uses a simple approach: split horizontally/vertically around each exclusion.
    func subtractRects(from source: CGRect, excluding: [CGRect]) -> [CGRect] {
        var remaining = [source]
        for excl in excluding {
            var next: [CGRect] = []
            for rect in remaining {
                let intersection = rect.intersection(excl)
                if intersection.isNull || intersection.isEmpty {
                    next.append(rect)
                    continue
                }
                // Split into up to 4 pieces: top, bottom, left, right of the exclusion
                // Top strip (above exclusion)
                if intersection.minY > rect.minY {
                    next.append(CGRect(x: rect.minX, y: rect.minY,
                                       width: rect.width, height: intersection.minY - rect.minY))
                }
                // Bottom strip (below exclusion)
                if intersection.maxY < rect.maxY {
                    next.append(CGRect(x: rect.minX, y: intersection.maxY,
                                       width: rect.width, height: rect.maxY - intersection.maxY))
                }
                // Left strip (within exclusion's Y range)
                if intersection.minX > rect.minX {
                    next.append(CGRect(x: rect.minX, y: intersection.minY,
                                       width: intersection.minX - rect.minX, height: intersection.height))
                }
                // Right strip (within exclusion's Y range)
                if intersection.maxX < rect.maxX {
                    next.append(CGRect(x: intersection.maxX, y: intersection.minY,
                                       width: rect.maxX - intersection.maxX, height: intersection.height))
                }
            }
            remaining = next.filter { $0.width > 10 && $0.height > 10 }  // Skip tiny slivers
        }
        return remaining
    }

    private func dismissHighlightWindow(_ hw: HighlightWindow) {
        hw.close()
        highlightWindows.removeAll { $0 === hw }
        hideTooltip()
    }

    private func hideHighlightWindows() {
        for hw in highlightWindows {
            hw.close()
        }
        highlightWindows.removeAll()
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
        guard currentDialog != nil else { return }
        guard let screen = NSScreen.main else { return }

        // Don't intercept clicks on the overlay panel
        if let panel = overlayPanel {
            let pf = panel.frame
            let cgPanelY = screen.frame.height - pf.origin.y - pf.height
            let cgPanelRect = CGRect(x: pf.origin.x, y: cgPanelY, width: pf.width, height: pf.height)
            if cgPanelRect.contains(cgPoint) { return }
        }

        // When highlights are active, they handle clicks via their own mouseDown.
        // The event tap (listenOnly) can't consume events, so both fire.
        // Skip navigation here to avoid double-navigating.
        if !highlightWindows.isEmpty { return }

        // Fallback: raw Finder window bounds (only when highlights are disabled)
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

        // Don't show tooltip over the overlay panel
        if let panel = overlayPanel, panel.frame.contains(mouseLocation) {
            hideTooltip()
            return
        }

        // First pass: check if mouse is directly on any pill label (reverse = topmost first)
        // Pills from lower windows should take hover priority over transparent overlay above them
        for hw in highlightWindows.reversed() {
            if hw.pillFrameInScreenCG.contains(cgPoint) {
                let path = hw.finderPath
                let name = URL(fileURLWithPath: path).lastPathComponent
                showTooltip(for: (name: name, path: path, bounds: hw.pillFrameInScreenCG), at: mouseLocation)
                return
            }
        }

        // Second pass: match against highlight windows in reverse order (last created = on top visually)
        // so the tooltip matches the top-most window, which is what receives the click
        for hw in highlightWindows.reversed() {
            let hf = hw.frame
            let cgHwY = screen.frame.height - hf.origin.y - hf.height
            let cgHwRect = CGRect(x: hf.origin.x, y: cgHwY, width: hf.width, height: hf.height)
            if cgHwRect.contains(cgPoint) {
                let path = hw.finderPath
                let name = URL(fileURLWithPath: path).lastPathComponent
                showTooltip(for: (name: name, path: path, bounds: cgHwRect), at: mouseLocation)
                return
            }
        }

        // Fall back to raw Finder window bounds (for when highlights are disabled)
        if highlightWindows.isEmpty, let matched = finderWindows.first(where: { $0.bounds.contains(cgPoint) }) {
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
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        // Use vibrancy material with dark appearance for a native tooltip feel
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 5
        effectView.layer?.masksToBounds = true

        label.frame = NSRect(x: 8, y: 2, width: label.frame.width, height: 20)
        effectView.addSubview(label)
        panel.contentView = effectView
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

        // Store dialog bounds in CG coords (top-left origin) for highlight clipping
        dialogBoundsCG = CGRect(origin: dialogOrigin, size: dialogSize)

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
