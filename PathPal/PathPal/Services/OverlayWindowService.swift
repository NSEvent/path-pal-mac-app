import AppKit
import SwiftUI

final class OverlayWindowService {
    private var overlayPanel: OverlayPanel?
    private var highlightWindows: [CGWindowID: HighlightWindow] = [:]
    private let appState: AppState
    private let dialogNavigationService = DialogNavigationService()
    private let finderWindowService = FinderWindowService()

    init(appState: AppState) {
        self.appState = appState
    }

    func showOverlay(for dialog: DialogInfo) {
        // Refresh Finder windows
        let finderWindows = finderWindowService.getFinderWindows()
        appState.finderWindows = finderWindows

        // Create overlay panel near the dialog
        let panel = OverlayPanel()
        let contentView = OverlayPanelView(
            finderWindows: finderWindows,
            dialogType: dialog.type,
            onFolderSelected: { [weak self] path in
                self?.navigateDialog(dialog, toPath: path)
            },
            onDesktopSelected: { [weak self] in
                let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
                self?.navigateDialog(dialog, toPath: desktop)
            },
            onDismiss: { [weak self] in
                self?.hideOverlay()
            }
        )
        panel.contentView = NSHostingView(rootView: contentView)

        // Position overlay to the left of dialog
        positionOverlay(panel, relativeTo: dialog)

        panel.orderFront(nil)
        overlayPanel = panel

        // Show Finder window highlights
        if SettingsService.shared.highlightFinderWindows {
            showHighlights(for: finderWindows, dialog: dialog)
        }
    }

    func hideOverlay() {
        overlayPanel?.close()
        overlayPanel = nil
        hideHighlights()
    }

    private func navigateDialog(_ dialog: DialogInfo, toPath path: String) {
        dialogNavigationService.navigateDialog(pid: dialog.pid, toPath: path)
    }

    private func positionOverlay(_ panel: OverlayPanel, relativeTo dialog: DialogInfo) {
        // Get dialog window position via AX
        var positionValue: CFTypeRef?
        AXUIElementCopyAttributeValue(dialog.element, kAXPositionAttribute as CFString, &positionValue)

        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(dialog.element, kAXSizeAttribute as CFString, &sizeValue)

        var dialogOrigin = CGPoint.zero
        var dialogSize = CGSize(width: 500, height: 400)

        if let positionValue = positionValue {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &dialogOrigin)
        }
        if let sizeValue = sizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &dialogSize)
        }

        // Position overlay to the left of the dialog
        let panelWidth: CGFloat = 260
        let panelHeight: CGFloat = 400
        var x = dialogOrigin.x - panelWidth - 10
        let y = dialogOrigin.y

        // If no room on left, try right
        if x < 0 {
            x = dialogOrigin.x + dialogSize.width + 10
        }

        // Convert from screen coords (top-left origin) to Cocoa coords (bottom-left origin)
        if let screen = NSScreen.main {
            let cocoaY = screen.frame.height - y - panelHeight
            panel.setFrame(NSRect(x: x, y: cocoaY, width: panelWidth, height: panelHeight), display: true)
        }
    }

    // MARK: - Finder Window Highlights

    private func showHighlights(for windows: [FinderWindow], dialog: DialogInfo) {
        for window in windows {
            let highlight = HighlightWindow(finderWindow: window)
            highlight.onClick = { [weak self] in
                guard SettingsService.shared.clickFinderWindowToChoose else { return }
                self?.navigateDialog(dialog, toPath: window.path)
            }
            highlight.orderFront(nil)
            highlightWindows[window.windowID] = highlight
        }
    }

    private func hideHighlights() {
        for (_, window) in highlightWindows {
            window.close()
        }
        highlightWindows.removeAll()
    }
}
