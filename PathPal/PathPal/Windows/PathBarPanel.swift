import AppKit

/// A floating panel for the path bar.
final class PathBarPanel: NSPanel {
    var onLostFocus: (() -> Void)?

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
        isReleasedWhenClosed = false

        // Spotlight-style bar: no window chrome. Esc, Enter, or clicking
        // away dismisses it.
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }

    private var isFadingOut = false

    /// Fade out briefly instead of vanishing on the spot.
    override func close() {
        guard !isFadingOut else { return }
        isFadingOut = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 0
        }, completionHandler: {
            super.close()
        })
    }

    override func resignKey() {
        super.resignKey()
        onLostFocus?()
    }

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
