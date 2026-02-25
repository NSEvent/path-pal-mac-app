import AppKit

/// A borderless overlay panel placed over a Finder window to highlight it.
/// Uses NSPanel with worksWhenModal so it's clickable during modal dialogs.
final class HighlightWindow: NSPanel {
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
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        worksWhenModal = true
        level = .modalPanel
        isOpaque = false
        backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08)
        ignoresMouseEvents = false
        hasShadow = false
        hidesOnDeactivate = false
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
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        window?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08)
        needsDisplay = true
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
