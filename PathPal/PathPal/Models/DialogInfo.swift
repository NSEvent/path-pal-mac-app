import ApplicationServices
import Foundation

enum DialogType: String {
    case open
    case save
}

struct DialogInfo {
    let pid: pid_t
    let element: AXUIElement
    let type: DialogType
    let appName: String

    /// Classify a dialog based on button titles found in its AX children.
    static func classify(buttonTitles: [String]) -> DialogType? {
        let titles = Set(buttonTitles.map { $0.lowercased() })
        if titles.contains("save") || titles.contains("export") {
            return .save
        }
        if titles.contains("open") || titles.contains("upload") || titles.contains("choose") {
            return .open
        }
        return nil
    }

    /// Reject transient browser/UI strips that can expose Open/Save buttons but
    /// are not the actual modal panel.
    static func isPlausibleDialogBounds(_ bounds: CGRect) -> Bool {
        guard !bounds.isNull,
              !bounds.isEmpty,
              bounds.width >= 240,
              bounds.height >= 120 else {
            return false
        }
        return true
    }

    /// Gate AX candidates before PathPal treats them as Open/Save dialogs.
    static func looksLikeDialogElement(
        role: String?,
        subrole: String?,
        title: String?,
        bounds: CGRect?,
        buttonTitles: [String]
    ) -> Bool {
        let roleStr = role ?? ""
        let subroleStr = subrole ?? ""

        if roleStr == "AXSheet" || roleStr == "AXDialog" ||
            subroleStr == "AXSheet" || subroleStr == "AXDialog" {
            return true
        }

        if titleLooksLikeDialog(title) {
            return true
        }

        guard roleStr == kAXWindowRole,
              let bounds,
              isPlausibleDialogBounds(bounds) else {
            return false
        }

        let normalizedButtons = Set(buttonTitles.map { normalize($0) })
        let primaryButtons: Set<String> = ["open", "save", "export", "upload", "choose"]
        return normalizedButtons.contains("cancel")
            && !normalizedButtons.isDisjoint(with: primaryButtons)
    }

    static func bounds(for element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              let rawPosition = positionValue,
              CFGetTypeID(rawPosition) == AXValueGetTypeID() else {
            return nil
        }
        let position = rawPosition as! AXValue
        guard AXValueGetType(position) == .cgPoint else { return nil }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let rawSize = sizeValue,
              CFGetTypeID(rawSize) == AXValueGetTypeID() else {
            return nil
        }
        let size = rawSize as! AXValue
        guard AXValueGetType(size) == .cgSize else { return nil }

        var origin = CGPoint.zero
        var boundsSize = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &boundsSize) else {
            return nil
        }

        let bounds = CGRect(origin: origin, size: boundsSize)
        guard isPlausibleDialogBounds(bounds) else { return nil }
        return bounds
    }

    private static func titleLooksLikeDialog(_ title: String?) -> Bool {
        let normalizedTitle = normalize(title ?? "")
        return normalizedTitle == "open"
            || normalizedTitle == "save"
            || normalizedTitle == "save as"
            || normalizedTitle.hasPrefix("open ")
            || normalizedTitle.hasPrefix("save ")
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
