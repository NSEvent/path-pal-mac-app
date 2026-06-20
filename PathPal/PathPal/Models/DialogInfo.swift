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

    struct Candidate {
        let element: AXUIElement
        let type: DialogType
        let bounds: CGRect?
    }

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

        guard roleStr == kAXWindowRole,
              let bounds,
              isPlausibleDialogBounds(bounds) else {
            return false
        }

        if titleLooksLikeDialog(title) {
            return true
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

    static func candidate(from element: AXUIElement, pid: pid_t) -> Candidate? {
        if let candidate = candidate(in: element) {
            return candidate
        }
        return candidate(inApp: pid)
    }

    static func candidate(inApp pid: pid_t) -> Candidate? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        if let focusedWindow, CFGetTypeID(focusedWindow) == AXUIElementGetTypeID(),
           let candidate = candidate(in: (focusedWindow as! AXUIElement)) {
            return candidate
        }

        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        if let windows = windows as? [AXUIElement] {
            for window in windows {
                if let candidate = candidate(in: window) {
                    return candidate
                }
            }
        }

        return nil
    }

    private static func candidate(in element: AXUIElement) -> Candidate? {
        var sheets: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXSheets" as CFString, &sheets)
        if let sheets = sheets as? [AXUIElement] {
            for sheet in sheets {
                if let candidate = candidateIfValid(sheet) {
                    return candidate
                }
            }
        }

        if let candidate = candidateIfValid(element) {
            return candidate
        }

        return nil
    }

    private static func candidateIfValid(_ element: AXUIElement) -> Candidate? {
        let buttonTitles = findButtonTitles(in: element, depth: 0)
        guard let dialogType = classify(buttonTitles: buttonTitles) else {
            return nil
        }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)

        let roleStr = role as? String
        let subroleStr = subrole as? String
        let titleStr = title as? String
        let bounds = bounds(for: element)

        guard looksLikeDialogElement(
            role: roleStr,
            subrole: subroleStr,
            title: titleStr,
            bounds: bounds,
            buttonTitles: buttonTitles
        ) else {
            return nil
        }

        return Candidate(element: element, type: dialogType, bounds: bounds)
    }

    static func findButtonTitles(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 10 else { return [] }

        var titles: [String] = []
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String

        if roleStr == kAXButtonRole {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            if let title = title as? String, !title.isEmpty {
                titles.append(title)
            }
            return titles
        }

        let skipRoles: Set<String> = [
            kAXScrollAreaRole, kAXTableRole, kAXOutlineRole, kAXListRole,
            kAXBrowserRole, "AXWebArea"
        ]
        if let roleStr = roleStr, skipRoles.contains(roleStr) {
            return []
        }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if let children = children as? [AXUIElement] {
            for child in children {
                titles.append(contentsOf: findButtonTitles(in: child, depth: depth + 1))
            }
        }

        return titles
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
