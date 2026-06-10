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
    var onRightClick: (() -> Void)?
    var finderPath: String { finderWindowInfo.path }
    private let finderWindowInfo: FinderWindow

    init(
        finderWindow: FinderWindow,
        colorIndex: Int = 0,
        labelFrameInScreenCG: CGRect? = nil,
        showsLabel: Bool = true
    ) {
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
        let displayName = HighlightLabelLayout.displayName(for: finderWindow.path)
        let resolvedLabelFrame = labelFrameInScreenCG ?? Self.defaultLabelFrameInScreenCG(for: finderWindow)
        let labelFrame = showsLabel ? resolvedLabelFrame.map {
            Self.convertLabelFrameToWindowCoordinates($0, windowBoundsCG: finderWindow.bounds)
        } : nil

        let view = HighlightView(frame: NSRect(origin: .zero, size: frame.size),
                                 folderName: displayName,
                                 color: color,
                                 labelFrame: labelFrame)
        view.onClick = { [weak self] in self?.onClick?() }
        view.onRightClick = { [weak self] in self?.onRightClick?() }
        contentView = view
    }

    /// The pill label's frame in CG screen coordinates (top-left origin),
    /// used by OverlayWindowService for cross-window pill hit-testing.
    var pillFrameInScreenCG: CGRect {
        guard let view = contentView as? HighlightView,
              let screen = NSScreen.main else { return .zero }
        let windowFrame = view.pillFrameInWindow
        let screenFrame = convertToScreen(windowFrame)
        // Convert Cocoa (bottom-left) to CG (top-left)
        return CGRect(x: screenFrame.origin.x,
                      y: screen.frame.height - screenFrame.origin.y - screenFrame.height,
                      width: screenFrame.width,
                      height: screenFrame.height)
    }

    private static func convertLabelFrameToWindowCoordinates(_ labelFrameCG: CGRect, windowBoundsCG: CGRect) -> CGRect {
        CGRect(
            x: labelFrameCG.minX - windowBoundsCG.minX,
            y: windowBoundsCG.maxY - labelFrameCG.maxY,
            width: labelFrameCG.width,
            height: labelFrameCG.height
        )
    }

    private static func defaultLabelFrameInScreenCG(for finderWindow: FinderWindow) -> CGRect? {
        let region = HighlightLabelRegion(
            windowIndex: 0,
            regionIndex: 0,
            bounds: finderWindow.bounds,
            path: finderWindow.path
        )
        return HighlightLabelLayout.assignments(for: [region])[region.id]
    }
}

class HighlightView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    private var isHovering = false
    private let pillView: NSView
    private let pillTintLayer: CALayer
    private let highlightColor: HighlightColor
    private let labelFrame: CGRect?

    /// Pill label frame in window coordinates (for converting to screen coords).
    var pillFrameInWindow: CGRect {
        guard !pillView.isHidden else { return .zero }
        return pillView.convert(pillView.bounds, to: nil)
    }

    init(frame: NSRect, folderName: String, color: HighlightColor, labelFrame: CGRect?) {
        self.highlightColor = color
        self.labelFrame = labelFrame

        // Build the pill label using vibrancy material with colored tint
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

        // Vibrancy background with colored tint overlay
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.translatesAutoresizingMaskIntoConstraints = false

        let tintLayer = CALayer()
        tintLayer.backgroundColor = color.nsColor.withAlphaComponent(0.55).cgColor

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 12
        pill.layer?.masksToBounds = true
        // Subtle inner border for definition against complex backgrounds
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = true
        pill.isHidden = labelFrame == nil
        pill.addSubview(effectView)
        pill.addSubview(icon)
        pill.addSubview(label)

        self.pillView = pill
        self.pillTintLayer = tintLayer

        super.init(frame: frame)
        addSubview(pill)

        NSLayoutConstraint.activate([
            // Effect view fills pill
            effectView.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: pill.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: pill.bottomAnchor),

            // Icon
            icon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            // Label
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        if let labelFrame {
            pillView.frame = labelFrame
        }

        // Ensure tint layer is added and sized to fill the effect view
        if pillTintLayer.superlayer == nil {
            if let effectView = pillView.subviews.first as? NSVisualEffectView {
                effectView.layer?.addSublayer(pillTintLayer)
            }
        }
        pillTintLayer.frame = pillView.bounds
    }

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
        if !pillView.isHidden {
            pillTintLayer.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.7).cgColor
            pillView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        window?.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.08)
        if !pillView.isHidden {
            pillTintLayer.backgroundColor = highlightColor.nsColor.withAlphaComponent(0.55).cgColor
            pillView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let borderColor = highlightColor.nsColor.withAlphaComponent(isHovering ? 0.6 : 0.3)
        borderColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.lineWidth = 2
        path.stroke()
    }
}
