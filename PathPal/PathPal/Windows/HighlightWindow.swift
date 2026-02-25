import AppKit

/// A borderless overlay panel placed over a Finder window to highlight it.
/// Uses NSPanel with worksWhenModal so it's clickable during modal dialogs.
final class HighlightWindow: NSPanel {
    var onClick: (() -> Void)?
    var finderPath: String { finderWindowInfo.path }
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

        let view = HighlightView(frame: NSRect(origin: .zero, size: frame.size),
                                 folderName: finderWindow.name)
        view.onClick = { [weak self] in self?.onClick?() }
        contentView = view
    }
}

private class HighlightView: NSView {
    var onClick: (() -> Void)?
    private var isHovering = false
    private let pillView: NSView
    private let pillLabel: NSTextField
    private let pillIcon: NSImageView

    init(frame: NSRect, folderName: String) {
        // Build the pill label
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: folderName)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        pill.layer?.cornerRadius = 10
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(icon)
        pill.addSubview(label)

        self.pillView = pill
        self.pillLabel = label
        self.pillIcon = icon

        super.init(frame: frame)
        addSubview(pill)

        NSLayoutConstraint.activate([
            // Icon
            icon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 12),
            icon.heightAnchor.constraint(equalToConstant: 12),

            // Label
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            // Pill sizing and position — bottom center
            pill.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
            pill.heightAnchor.constraint(equalToConstant: 22),
            pill.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

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
        pillView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        window?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08)
        pillView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let borderColor = NSColor.systemBlue.withAlphaComponent(isHovering ? 0.6 : 0.3)
        borderColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.lineWidth = 2
        path.stroke()
    }
}
