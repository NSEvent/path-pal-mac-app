import AppKit
import QuartzCore

/// Color palette for distinguishing multiple Finder window highlights.
/// Muted but distinct — chosen to work well as semi-transparent overlays.
enum HighlightColor: CaseIterable, Equatable {
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
    var finderWindowID: CGWindowID { finderWindowInfo.windowID }
    var frameInScreenCG: CGRect { finderWindowInfo.bounds }
    var highlightColor: HighlightColor { color }
    var pillFramesInScreenCG: [CGRect] { labelFramesInScreenCG }
    private(set) var isHighlightedForHover = false
    private let finderWindowInfo: FinderWindow
    private let visibleRegionsInScreenCG: [CGRect]
    private let labelFramesInScreenCG: [CGRect]
    private let color: HighlightColor

    convenience init(
        finderWindow: FinderWindow,
        colorIndex: Int = 0,
        labelFrameInScreenCG: CGRect? = nil,
        showsLabel: Bool = true
    ) {
        let resolvedLabelFrame = labelFrameInScreenCG ?? Self.defaultLabelFrameInScreenCG(for: finderWindow)
        self.init(
            finderWindow: finderWindow,
            colorIndex: colorIndex,
            visibleRegionsInScreenCG: [finderWindow.bounds],
            labelFramesInScreenCG: showsLabel ? resolvedLabelFrame.map { [$0] } ?? [] : []
        )
    }

    init(
        finderWindow: FinderWindow,
        colorIndex: Int = 0,
        visibleRegionsInScreenCG: [CGRect],
        labelFramesInScreenCG: [CGRect]
    ) {
        self.finderWindowInfo = finderWindow
        self.visibleRegionsInScreenCG = visibleRegionsInScreenCG
        self.labelFramesInScreenCG = labelFramesInScreenCG

        let color = HighlightColor.forIndex(colorIndex)
        self.color = color

        // Convert from CGWindowList coords (top-left origin) to Cocoa coords
        // (bottom-left origin). CG global coordinates are anchored at the
        // PRIMARY screen's top-left, so the conversion must use screens.first
        // — NSScreen.main is whichever screen has the key window.
        let screenFrame = NSScreen.screens.first?.frame ?? .zero
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
        backgroundColor = .clear
        ignoresMouseEvents = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Show last 2 path components for context (e.g. "Projects/MyApp")
        let displayName = HighlightLabelLayout.displayName(for: finderWindow.path)
        let regionFrames = visibleRegionsInScreenCG.map {
            Self.convertScreenCGFrameToWindowCoordinates($0, windowBoundsCG: finderWindow.bounds)
        }
        let labelFrames = labelFramesInScreenCG.map {
            Self.convertLabelFrameToWindowCoordinates($0, windowBoundsCG: finderWindow.bounds)
        }

        let view = HighlightView(frame: NSRect(origin: .zero, size: frame.size),
                                 folderName: displayName,
                                 color: color,
                                 regionFrames: regionFrames,
                                 labelFrames: labelFrames)
        view.onClick = { [weak self] in self?.onClick?() }
        view.onRightClick = { [weak self] in self?.onRightClick?() }
        contentView = view
    }

    func setHighlighted(_ highlighted: Bool) {
        guard isHighlightedForHover != highlighted else { return }
        isHighlightedForHover = highlighted
        (contentView as? HighlightView)?.setHighlighted(highlighted)
    }

    func orderFrontWithEntranceAnimation(sequenceIndex: Int) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            alphaValue = 1
            orderFrontRegardless()
            return
        }

        let delay = min(TimeInterval(sequenceIndex) * 0.012, 0.048)
        alphaValue = 0
        (contentView as? HighlightView)?.prepareForEntranceAnimation()
        orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isVisible else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.9, 0.2, 1.0)
                self.animator().alphaValue = 1
            }
            (self.contentView as? HighlightView)?.animateEntrance()
        }
    }

    func containsPointInScreenCG(_ point: CGPoint) -> Bool {
        hitRegionFrameInScreenCG(at: point) != nil
    }

    func hitRegionFrameInScreenCG(at point: CGPoint) -> CGRect? {
        visibleRegionsInScreenCG.reversed().first { $0.contains(point) }
    }

    /// The pill label's frame in CG screen coordinates (top-left origin),
    /// used by OverlayWindowService for cross-window pill hit-testing.
    var pillFrameInScreenCG: CGRect {
        pillFramesInScreenCG.first ?? .zero
    }

    private static func convertLabelFrameToWindowCoordinates(_ labelFrameCG: CGRect, windowBoundsCG: CGRect) -> CGRect {
        convertScreenCGFrameToWindowCoordinates(labelFrameCG, windowBoundsCG: windowBoundsCG)
    }

    private static func convertScreenCGFrameToWindowCoordinates(_ frameCG: CGRect, windowBoundsCG: CGRect) -> CGRect {
        CGRect(
            x: frameCG.minX - windowBoundsCG.minX,
            y: windowBoundsCG.maxY - frameCG.maxY,
            width: frameCG.width,
            height: frameCG.height
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
    private let pillViews: [NSView]
    private let pillTintLayers: [CALayer]
    private let highlightColor: HighlightColor
    private let regionFrames: [CGRect]
    private let labelFrames: [CGRect]

    /// Pill label frame in window coordinates (for converting to screen coords).
    var pillFrameInWindow: CGRect {
        pillFramesInWindow.first ?? .zero
    }

    var pillFramesInWindow: [CGRect] {
        pillViews.map { $0.convert($0.bounds, to: nil) }
    }

    init(frame: NSRect, folderName: String, color: HighlightColor, regionFrames: [CGRect], labelFrames: [CGRect]) {
        self.highlightColor = color
        self.regionFrames = regionFrames
        self.labelFrames = labelFrames

        var builtPills: [NSView] = []
        var builtTintLayers: [CALayer] = []
        for _ in labelFrames {
            let pill = Self.makePill(folderName: folderName, color: color)
            builtPills.append(pill.view)
            builtTintLayers.append(pill.tintLayer)
        }

        self.pillViews = builtPills
        self.pillTintLayers = builtTintLayers

        super.init(frame: frame)
        wantsLayer = true
        for pill in pillViews {
            addSubview(pill)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func makePill(folderName: String, color: HighlightColor) -> (view: NSView, tintLayer: CALayer) {
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
        pill.addSubview(effectView)
        pill.addSubview(icon)
        pill.addSubview(label)

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
        return (pill, tintLayer)
    }

    func setHighlighted(_ highlighted: Bool) {
        guard isHovering != highlighted else { return }
        isHovering = highlighted
        updateHoverAppearance()
    }

    private func updateHoverAppearance() {
        for (pillView, pillTintLayer) in zip(pillViews, pillTintLayers) {
            pillTintLayer.backgroundColor = highlightColor.nsColor.withAlphaComponent(isHovering ? 0.7 : 0.55).cgColor
            pillView.layer?.borderColor = NSColor.white.withAlphaComponent(isHovering ? 0.25 : 0.15).cgColor
        }
        needsDisplay = true
    }

    func prepareForEntranceAnimation() {
        wantsLayer = true
        layer?.removeAnimation(forKey: "pathPalHighlightEntrance")
        for pillView in pillViews {
            pillView.wantsLayer = true
            pillView.layer?.removeAnimation(forKey: "pathPalPillEntrance")
        }
    }

    func animateEntrance() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        if let layer {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.992
            scale.toValue = 1

            let group = CAAnimationGroup()
            group.animations = [scale]
            group.duration = 0.16
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.9, 0.2, 1.0)
            group.isRemovedOnCompletion = true
            layer.add(group, forKey: "pathPalHighlightEntrance")
        }

        for (index, pillView) in pillViews.enumerated() {
            guard let layer = pillView.layer else { continue }
            let delay = min(CFTimeInterval(index) * 0.012, 0.036)
            let beginTime = CACurrentMediaTime() + delay

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.92
            scale.toValue = 1

            let lift = CABasicAnimation(keyPath: "transform.translation.y")
            lift.fromValue = -4
            lift.toValue = 0

            let group = CAAnimationGroup()
            group.animations = [fade, scale, lift]
            group.beginTime = beginTime
            group.duration = 0.18
            group.fillMode = .backwards
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.95, 0.2, 1.0)
            group.isRemovedOnCompletion = true
            layer.add(group, forKey: "pathPalPillEntrance")
        }
    }

    override func layout() {
        super.layout()
        for index in pillViews.indices {
            let pillView = pillViews[index]
            pillView.frame = labelFrames[index]

            // Ensure tint layer is added and sized to fill the effect view
            let pillTintLayer = pillTintLayers[index]
            if pillTintLayer.superlayer == nil, let effectView = pillView.subviews.first as? NSVisualEffectView {
                effectView.layer?.addSublayer(pillTintLayer)
            }
            pillTintLayer.frame = pillView.bounds
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsTarget(at: point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard containsTarget(at: event.locationInWindow) else { return }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard containsTarget(at: event.locationInWindow) else { return }
        onRightClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let fillColor = highlightColor.nsColor.withAlphaComponent(isHovering ? 0.18 : 0.08)
        let borderColor = highlightColor.nsColor.withAlphaComponent(isHovering ? 0.6 : 0.3)
        for regionFrame in regionFrames {
            let path = NSBezierPath(roundedRect: regionFrame.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            fillColor.setFill()
            path.fill()
            borderColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func containsTarget(at point: CGPoint) -> Bool {
        labelFrames.contains { $0.contains(point) } || regionFrames.contains { $0.contains(point) }
    }
}
