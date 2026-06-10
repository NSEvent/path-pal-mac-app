import AppKit
import QuartzCore

/// A floating panel that appears alongside Open/Save dialogs.
/// Uses worksWhenModal to be interactive even when a modal dialog is active.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        worksWhenModal = true
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false
    }

    func orderFrontWithEntranceAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            alphaValue = 1
            orderFrontRegardless()
            return
        }

        alphaValue = 0
        contentView?.wantsLayer = true
        contentView?.layer?.removeAnimation(forKey: "pathPalPanelEntrance")

        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.9, 0.2, 1.0)
            animator().alphaValue = 1
        }

        guard let layer = contentView?.layer else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.965
        scale.toValue = 1

        let lift = CABasicAnimation(keyPath: "transform.translation.y")
        lift.fromValue = -6
        lift.toValue = 0

        let group = CAAnimationGroup()
        group.animations = [scale, lift]
        group.duration = 0.22
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        group.isRemovedOnCompletion = true
        layer.add(group, forKey: "pathPalPanelEntrance")
    }
}
