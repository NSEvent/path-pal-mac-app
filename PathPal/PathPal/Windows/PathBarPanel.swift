import AppKit

/// A floating panel for the Cmd+L path bar.
final class PathBarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = true
    }

    override var canBecomeKey: Bool { true }

    /// Position the panel centered above a Finder window.
    func positionAboveFinderWindow() {
        guard let screen = NSScreen.main else { return }

        // Position near top center of screen
        let panelWidth: CGFloat = 500
        let panelHeight: CGFloat = 44
        let x = (screen.frame.width - panelWidth) / 2
        let y = screen.frame.height - 200  // Near top of screen

        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
