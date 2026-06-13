import AppKit
import SwiftUI

/// Hosting view that starts clicks/drags on first mouse-down, so the drawer
/// works without its (never-key) panel needing focus first.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floating shelf panel for the file drawer. Non-activating and never key:
/// dragging files in or out must not disturb whichever app is frontmost.
///
/// Drag-out is initiated here at the window level: `sendEvent` sees every
/// mouse event before SwiftUI hit-testing can claim it, maps the press to a
/// row via the frames the view publishes, and starts a real
/// `NSDraggingSession` whose NSURL pasteboard writer Finder and dialogs
/// accept. (SwiftUI `.onDrag` and embedded NSView drag sources both lose
/// the gesture inside a movable-by-background, non-activating panel.)
final class FileDrawerPanel: NSPanel, NSDraggingSource {
    // Shared geometry — the SwiftUI view sizes itself to match.
    static let drawerWidth: CGFloat = 190
    static let fullHeight: CGFloat = 340
    static let handleHeight: CGFloat = 44

    private enum PressTarget {
        case row(String)
        case background
    }

    private let drawerState: FileDrawerState
    private var press: (target: PressTarget, start: NSPoint)?

    /// Row click handler (path, command-key). Clicks are routed here from
    /// sendEvent because SwiftUI tap gestures and Buttons don't fire reliably
    /// in a never-key panel.
    var onRowClick: ((String, Bool) -> Void)?
    /// Handle clicked (not on a control): toggle minimize.
    var onToggleMinimize: (() -> Void)?
    /// Clear control in the handle clicked.
    var onClear: (() -> Void)?

    init(rootView: FileDrawerView, state: FileDrawerState) {
        drawerState = state
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.drawerWidth, height: Self.fullHeight),
            // Borderless so the window frame equals the content exactly — no
            // titlebar offset to confuse handle/row click coordinates.
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Window-move-by-background arms the window server at mouse-down,
        // which would drag the panel along with row drag-outs. Moving the
        // panel is handled manually in sendEvent for non-row presses.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        // A rounded, clipping container fills the window. The SwiftUI content
        // sits inside at a FIXED full height, pinned to the top, so minimizing
        // just animates the window (and this container) smaller — the content
        // rolls up behind the handle and is clipped, with no SwiftUI relayout.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.drawerWidth, height: Self.fullHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        let hosting = FirstMouseHostingView(rootView: rootView)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .minYMargin] // fixed height, pinned to top
        container.addSubview(hosting)
        contentView = container

        // Default to the right screen edge, vertically centered; remember
        // wherever the user drags it afterwards.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.maxX - frame.width - 16
            let y = visible.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        setFrameAutosaveName("PathPalFileDrawer")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Minimize / maximize

    /// Collapse to just the handle bar (or restore), keeping the handle's top
    /// edge fixed on screen so it doesn't appear to jump.
    func applyMinimized(_ minimized: Bool, animated: Bool) {
        let targetHeight = minimized ? Self.handleHeight : Self.fullHeight
        var newFrame = frame
        let topEdge = frame.maxY
        newFrame.size.height = targetHeight
        newFrame.origin.y = topEdge - targetHeight // keep top fixed
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }

    // MARK: - Drag-out interception

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if let path = rowPath(at: event) {
                press = (.row(path), event.locationInWindow)
            } else {
                press = (.background, event.locationInWindow)
            }
        case .leftMouseDragged:
            if let press,
               hypot(event.locationInWindow.x - press.start.x,
                     event.locationInWindow.y - press.start.y) > 4 {
                self.press = nil
                switch press.target {
                case .row(let path):
                    beginRowDrag(path: path, event: event)
                case .background:
                    performDrag(with: event)
                }
                return // the drag (file or window) owns the gesture from here
            }
        case .leftMouseUp:
            if let press,
               hypot(event.locationInWindow.x - press.start.x,
                     event.locationInWindow.y - press.start.y) <= 4,
               let contentView {
                let point = CGPoint(
                    x: event.locationInWindow.x,
                    y: contentView.bounds.height - event.locationInWindow.y
                )
                switch press.target {
                case .row(let path):
                    // Ignore the trailing strip where the remove button lives.
                    if let frame = drawerState.rowFrames[path], point.x < frame.maxX - 28 {
                        let commandKey = event.modifierFlags.contains(.command)
                        DispatchQueue.main.async { [weak self] in
                            self?.onRowClick?(path, commandKey)
                        }
                    }
                case .background:
                    // A click in the handle region: clear icon, or toggle.
                    if point.y <= Self.handleHeight {
                        if let clear = drawerState.handleControlFrames["clear"], clear.insetBy(dx: -6, dy: -6).contains(point) {
                            DispatchQueue.main.async { [weak self] in self?.onClear?() }
                        } else {
                            DispatchQueue.main.async { [weak self] in self?.onToggleMinimize?() }
                        }
                    }
                }
            }
            press = nil
        default:
            break
        }
        super.sendEvent(event)
    }

    /// Map a mouse event to the drawer row under it, converting the window's
    /// bottom-left coordinates to SwiftUI's top-left global space. The header
    /// strip is never a row, even if a scrolled-away row reports a frame there.
    private func rowPath(at event: NSEvent) -> String? {
        guard let contentView else { return nil }
        let point = CGPoint(
            x: event.locationInWindow.x,
            y: contentView.bounds.height - event.locationInWindow.y
        )
        guard point.y > Self.handleHeight else { return nil }
        return drawerState.rowFrames.first(where: { $0.value.contains(point) })?.key
    }

    private func beginRowDrag(path: String, event: NSEvent) {
        guard let contentView else { return }

        // Dragging a selected row carries the whole selection, in list order.
        let paths: [String]
        if drawerState.selectedPaths.contains(path), drawerState.selectedPaths.count > 1 {
            paths = drawerState.items.map(\.path).filter { drawerState.selectedPaths.contains($0) }
        } else {
            paths = [path]
        }

        let size = NSSize(width: 32, height: 32)
        let point = contentView.convert(event.locationInWindow, from: nil)
        let items = paths.enumerated().map { index, itemPath in
            let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: itemPath) as NSURL)
            let offset = CGFloat(index) * 4
            item.setDraggingFrame(
                NSRect(x: point.x - size.width / 2 + offset, y: point.y - size.height / 2 - offset,
                       width: size.width, height: size.height),
                contents: NSWorkspace.shared.icon(forFile: itemPath)
            )
            return item
        }
        Self.drawerLog("beginDraggingSession for \(paths.count) item(s)")
        contentView.beginDraggingSession(with: items, event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy-only outside the app: the original file never moves, no matter
        // how the destination would prefer to interpret the drop.
        context == .outsideApplication ? .copy : .generic
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        Self.drawerLog("drag ended, operation rawValue \(operation.rawValue)")
    }

    private static func drawerLog(_ message: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PathPal")
        let logURL = dir.appendingPathComponent("debug.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] [Drawer] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
