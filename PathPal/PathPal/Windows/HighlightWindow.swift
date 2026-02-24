import AppKit

/// A borderless overlay window placed over a Finder window to highlight it.
final class HighlightWindow: NSWindow {
    var onClick: (() -> Void)?
    private let finderWindowInfo: FinderWindow

    init(finderWindow: FinderWindow) {
        self.finderWindowInfo = finderWindow

        // Convert from CGWindowList coords (top-left origin) to Cocoa coords (bottom-left origin)
        let screenFrame = NSScreen.main?.frame ?? .zero
        let cocoaY = screenFrame.height - finderWindow.bounds.origin.y - finderWindow.bounds.height

        let frame = NSRect(
            x: finderWindow.bounds.origin.x,
            y: cocoaY,
            width: finderWindow.bounds.width,
            height: finderWindow.bounds.height
        )

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08)
        level = .floating
        ignoresMouseEvents = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        let view = HighlightView(frame: frame)
        view.onClick = { [weak self] in self?.onClick?() }
        view.toolTip = finderWindow.path
        contentView = view
    }
}

private class HighlightView: NSView {
    var onClick: (() -> Void)?
    private var isHovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        window?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        window?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw a subtle border
        let borderColor = NSColor.systemBlue.withAlphaComponent(isHovering ? 0.6 : 0.3)
        borderColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.lineWidth = 2
        path.stroke()
    }
}
