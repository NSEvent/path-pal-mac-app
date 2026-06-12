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
    private enum PressTarget {
        case row(String)
        case background
    }

    private let drawerState: FileDrawerState
    private var press: (target: PressTarget, start: NSPoint)?

    init(rootView: FileDrawerView, state: FileDrawerState) {
        drawerState = state
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 190, height: 320),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Window-move-by-background arms the window server at mouse-down,
        // which would drag the panel along with row drag-outs. Moving the
        // panel is handled manually in sendEvent for non-row presses.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentView = FirstMouseHostingView(rootView: rootView)

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
        guard point.y > 34 else { return nil }
        return drawerState.rowFrames.first(where: { $0.value.contains(point) })?.key
    }

    private func beginRowDrag(path: String, event: NSEvent) {
        guard let contentView else { return }
        let url = URL(fileURLWithPath: path)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: path)
        let size = NSSize(width: 32, height: 32)
        let point = contentView.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                   width: size.width, height: size.height),
            contents: icon
        )
        Self.drawerLog("beginDraggingSession for \(url.lastPathComponent)")
        contentView.beginDraggingSession(with: [item], event: event, source: self)
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
