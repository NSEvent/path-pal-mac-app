import AppKit

/// A floating panel for the path bar.
final class PathBarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

    /// Position the panel centered near the top of the screen.
    func positionAboveFinderWindow() {
        guard let screen = NSScreen.main else { return }

        let panelWidth: CGFloat = 500
        let panelHeight: CGFloat = 400
        let x = screen.frame.origin.x + (screen.frame.width - panelWidth) / 2
        let y = screen.frame.origin.y + screen.frame.height - panelHeight - 100

        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
