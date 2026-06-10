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
    private var clickMonitor: Any?
    private var moveMonitor: Any?
    private var dialogFrameTimer: Timer?
    private var currentDialog: DialogInfo?
    private var overlayRequestID = 0
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
        overlayRequestID += 1
        let requestID = overlayRequestID

        let panel = OverlayPanel()
        panel.contentView = makeOverlayContent(finderWindows: appState.finderWindows, dialogType: dialog.type)
        positionOverlay(panel, relativeTo: dialog)
        panel.orderFrontRegardless()
        overlayPanel = panel

        // Start monitors immediately; Finder windows populate asynchronously.
        startEventTap()
        startMoveMonitor()
        startDialogFrameMonitor()

        debugLog("Overlay panel shown, isVisible=\(panel.isVisible), level=\(panel.level.rawValue), frame=\(panel.frame)")

        // Get Finder windows on a background thread so the overlay appears immediately.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let windows = FinderScriptingService.shared.getFinderWindowsWithBounds().enumerated().map { index, window in
                FinderWindow(
                    windowID: CGWindowID(index),
                    title: window.name,
                    bounds: window.bounds,
                    path: window.path
                )
            }
            DispatchQueue.main.async {
                guard let self = self,
                      self.overlayRequestID == requestID,
                      self.currentDialog != nil,
                      let panel = self.overlayPanel else { return }

                self.appState.finderWindows = windows
                self.finderWindows = windows.map {
                    (name: $0.title, path: $0.path, bounds: $0.bounds)
                }
                panel.contentView = self.makeOverlayContent(finderWindows: windows, dialogType: dialog.type)
                debugLog("Found \(windows.count) Finder windows")

                if SettingsService.shared.highlightFinderWindows {
                    self.showHighlightWindows()
                }
            }
        }
    }

    func hideOverlay() {
        overlayRequestID += 1
        overlayPanel?.orderOut(nil)
        overlayPanel = nil
        isShowingOverlay = false
        hideHighlightWindows()
        stopEventTap()
        stopClickMonitorFallback()
        stopMoveMonitor()
        stopDialogFrameMonitor()
        hideTooltip()
        currentDialog = nil
        dialogBoundsCG = .zero
        finderWindows = []
    }

    private func makeOverlayContent(finderWindows: [FinderWindow], dialogType: DialogType) -> NSView {
        NSHostingView(rootView: OverlayPanelView(
            finderWindows: finderWindows,
            dialogType: dialogType,
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
        ))
    }

    // MARK: - Finder Window Highlights

    private func showHighlightWindows() {
        let oldHighlightWindows = highlightWindows
        highlightWindows.removeAll(keepingCapacity: true)

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

        let clickEnabled = SettingsService.shared.clickFinderWindowToChoose

        var labelRegions: [HighlightLabelRegion] = []
        var highlightSpecs: [(id: HighlightLabelRegionID, finderWindow: FinderWindow, title: String, path: String, colorIndex: Int)] = []

        for (colorIndex, fw) in appState.finderWindows.enumerated() {
            let visibleRegions = subtractRects(from: fw.bounds, excluding: excludeRects)
            for (regionIndex, region) in visibleRegions.enumerated() {
                let clippedFW = FinderWindow(windowID: fw.windowID, title: fw.title, bounds: region, path: fw.path)
                let id = HighlightLabelRegionID(windowIndex: colorIndex, regionIndex: regionIndex)
                labelRegions.append(HighlightLabelRegion(windowIndex: colorIndex, regionIndex: regionIndex, bounds: region, path: fw.path))
                highlightSpecs.append((id: id, finderWindow: clippedFW, title: fw.title, path: fw.path, colorIndex: colorIndex))
            }
        }

        let labelFrames = HighlightLabelLayout.assignments(for: labelRegions)

        for spec in highlightSpecs {
            let labelFrame = labelFrames[spec.id]
            let hw = HighlightWindow(
                finderWindow: spec.finderWindow,
                colorIndex: spec.colorIndex,
                labelFrameInScreenCG: labelFrame,
                showsLabel: labelFrame != nil
            )
            hw.ignoresMouseEvents = !clickEnabled
            hw.onClick = { [weak self] in
                guard let self = self else { return }
                guard SettingsService.shared.clickFinderWindowToChoose else { return }
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

                // No pill hit - navigate to clicked highlight's path
                debugLog("Highlight click: \(spec.title) path=\(spec.path)")
                self.navigateDialog(toPath: spec.path)
            }
            hw.onRightClick = { [weak self, weak hw] in
                guard let self = self, let hw = hw else { return }
                self.dismissHighlightWindow(hw)
            }
            hw.orderFrontRegardless()
            highlightWindows.append(hw)
        }

        oldHighlightWindows.forEach { $0.orderOut(nil) }

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
        hw.orderOut(nil)
        highlightWindows.removeAll { $0 === hw }
        hideTooltip()
    }

    private func hideHighlightWindows() {
        for hw in highlightWindows {
            hw.orderOut(nil)
        }
        highlightWindows.removeAll(keepingCapacity: true)
    }

    private func navigateDialog(toPath path: String) {
        guard let dialog = currentDialog else { return }
        dialogNavigationService.navigateDialog(pid: dialog.pid, toPath: path)
    }

    // MARK: - CGEvent Tap for Click Interception

    private func startEventTap() {
        stopEventTap()
        stopClickMonitorFallback()

        guard SettingsService.shared.clickFinderWindowToChoose else {
            debugLog("[PathPal] Finder window click-to-choose disabled")
            return
        }

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
        stopClickMonitorFallback()
        debugLog("[PathPal] Using NSEvent global monitor fallback for clicks")
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
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
        guard SettingsService.shared.clickFinderWindowToChoose else { return }
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

    private func stopClickMonitorFallback() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Move Monitor (tooltip on hover)

    private func startMoveMonitor() {
        stopMoveMonitor()
        guard SettingsService.shared.showFinderWindowNames else {
            hideTooltip()
            return
        }
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleGlobalMove()
        }
    }

    private var lastLoggedMove: Date = .distantPast

    private func handleGlobalMove() {
        guard currentDialog != nil, !finderWindows.isEmpty else { return }
        guard SettingsService.shared.showFinderWindowNames else {
            hideTooltip()
            return
        }

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
        tooltipPanel?.orderOut(nil)
        tooltipPanel = nil
    }

    // MARK: - Dialog Frame Monitoring

    private func startDialogFrameMonitor() {
        stopDialogFrameMonitor()
        guard currentDialog != nil else { return }

        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.refreshDialogFrameIfNeeded()
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        dialogFrameTimer = timer
    }

    private func stopDialogFrameMonitor() {
        dialogFrameTimer?.invalidate()
        dialogFrameTimer = nil
    }

    private func refreshDialogFrameIfNeeded() {
        guard let dialog = currentDialog,
              let newBounds = Self.dialogBounds(for: dialog.element),
              Self.dialogFrameNeedsRefresh(previous: dialogBoundsCG, current: newBounds) else {
            return
        }

        debugLog("Dialog frame changed: \(dialogBoundsCG) -> \(newBounds)")
        dialogBoundsCG = newBounds

        if let panel = overlayPanel {
            positionOverlay(panel, dialogBounds: newBounds)
        }

        if SettingsService.shared.highlightFinderWindows {
            showHighlightWindows()
        }
    }

    static func dialogFrameNeedsRefresh(previous: CGRect, current: CGRect, tolerance: CGFloat = 1.0) -> Bool {
        guard !previous.isEmpty else { return !current.isEmpty }
        return abs(previous.origin.x - current.origin.x) > tolerance
            || abs(previous.origin.y - current.origin.y) > tolerance
            || abs(previous.width - current.width) > tolerance
            || abs(previous.height - current.height) > tolerance
    }

    static func dialogBounds(for element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              let rawPosition = positionValue,
              CFGetTypeID(rawPosition) == AXValueGetTypeID() else {
            return nil
        }
        let position = rawPosition as! AXValue
        guard AXValueGetType(position) == .cgPoint else { return nil }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let rawSize = sizeValue,
              CFGetTypeID(rawSize) == AXValueGetTypeID() else {
            return nil
        }
        let size = rawSize as! AXValue
        guard AXValueGetType(size) == .cgSize else { return nil }

        var origin = CGPoint.zero
        var boundsSize = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &boundsSize),
              boundsSize.width > 0,
              boundsSize.height > 0 else {
            return nil
        }

        return CGRect(origin: origin, size: boundsSize)
    }

    // MARK: - Overlay Positioning

    private func positionOverlay(_ panel: OverlayPanel, relativeTo dialog: DialogInfo) {
        let fallbackBounds = CGRect(origin: .zero, size: CGSize(width: 500, height: 400))
        positionOverlay(panel, dialogBounds: Self.dialogBounds(for: dialog.element) ?? fallbackBounds)
    }

    private func positionOverlay(_ panel: OverlayPanel, dialogBounds: CGRect) {
        debugLog("positionOverlay: dialog at (\(dialogBounds.origin.x), \(dialogBounds.origin.y)) size (\(dialogBounds.width) x \(dialogBounds.height))")

        // Store dialog bounds in CG coords (top-left origin) for highlight clipping
        dialogBoundsCG = dialogBounds

        let panelWidth: CGFloat = 260
        let panelHeight: CGFloat = 400
        var x = dialogBounds.origin.x - panelWidth - 10
        let y = dialogBounds.origin.y

        if x < 0 {
            x = dialogBounds.origin.x + dialogBounds.width + 10
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
