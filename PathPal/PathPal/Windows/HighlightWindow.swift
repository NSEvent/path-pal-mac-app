import AppKit

/// Color palette for distinguishing multiple Finder window highlights.
/// Muted but distinct — chosen to work well as semi-transparent overlays.
enum HighlightColor: CaseIterable {
    case blue, purple, teal, orange, pink, green, indigo, coral

    var nsColor: NSColor {
        switch self {
        case .blue:    return .systemBlue
        case .purple:  return .systemPurple
        case .teal:    return .systemTeal
        case .orange:  return .systemOrange
        case .pink:    return .systemPink
        case .green:   return .systemGreen
        case .indigo:  return .systemIndigo
        case .coral:   return NSColor(red: 1.0, green: 0.42, blue: 0.38, alpha: 1.0)
        }
    }

    static func forIndex(_ index: Int) -> HighlightColor {
        let all = Self.allCases
        return all[index % all.count]
    }
}

/// A borderless overlay panel placed over a Finder window to highlight it.
/// Uses NSPanel with worksWhenModal so it's clickable during modal dialogs.
final class HighlightWindow: NSPanel {
    var onClick: (() -> Void)?
    var finderPath: String { finderWindowInfo.path }
    private let finderWindowInfo: FinderWindow

    init(finderWindow: FinderWindow, colorIndex: Int = 0) {
        self.finderWindowInfo = finderWindow

        let color = HighlightColor.forIndex(colorIndex)

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
        backgroundColor = color.nsColor.withAlphaComponent(0.08)
        ignoresMouseEvents = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Show last 2 path components for context (e.g. "Projects/MyApp")
        let displayName = Self.shortPath(finderWindow.path)

        let view = HighlightView(frame: NSRect(origin: .zero, size: frame.size),
                                 folderName: displayName,
                                 color: color)
        view.onClick = { [weak self] in self?.onClick?() }
        contentView = view
    }

    /// Returns the last 2 path components, or just the name for shallow paths.
    private static func shortPath(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        // pathComponents includes "/" as first element
        if components.count >= 3 {
            return components.suffix(2).joined(separator: "/")
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

private class HighlightView: NSView {
    var onClick: (() -> Void)?
    private var isHovering = false
    private let pillView: NSView
    private let highlightColor: HighlightColor

    init(frame: NSRect, folderName: String, color: HighlightColor) {
        self.highlightColor = color

        // Build the pill label
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: folderName)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.lineBreakMode = .byTruncatingHead
        label.translatesAutoresizingMaskIntoConstraints = false

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = color.nsColor.withAlphaComponent(0.75).cgColor
        pill.layer?.cornerRadius = 12
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(icon)
        pill.addSubview(label)

        self.pillView = pill

        super.init(frame: frame)
        addSubview(pill)

        NSLayoutConstraint.activate([
            // Icon
            icon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            // Label
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            // Pill sizing and position — bottom center
            pill.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -10),
            pill.heightAnchor.constraint(equalToConstant: 26),
            pill.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, constant: -20),
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
        window?.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.18)
        pillView.layer?.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.9).cgColor
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        window?.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.08)
        pillView.layer?.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.75).cgColor
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let borderColor = highlightColor.nsColor.withAlphaComponent(isHovering ? 0.6 : 0.3)
        borderColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.lineWidth = 2
        path.stroke()
    }
}
