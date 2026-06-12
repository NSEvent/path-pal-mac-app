import AppKit
import SwiftUI

/// Hosting view that starts clicks/drags on first mouse-down, so the drawer
/// works without its (never-key) panel needing focus first.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floating shelf panel for the file drawer. Non-activating and never key:
/// dragging files in or out must not disturb whichever app is frontmost.
final class FileDrawerPanel: NSPanel {
    init(rootView: FileDrawerView) {
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
        isMovableByWindowBackground = true
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
}
