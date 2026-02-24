import XCTest
@testable import PathPal

final class FinderWindowServiceTests: XCTestCase {

    func testParseCGWindowListFiltersFinderWindows() {
        let windowList: [[String: Any]] = [
            [
                kCGWindowOwnerName as String: "Finder",
                kCGWindowName as String: "Documents",
                kCGWindowNumber as String: CGWindowID(100),
                kCGWindowBounds as String: ["X": CGFloat(0), "Y": CGFloat(0), "Width": CGFloat(800), "Height": CGFloat(600)]
            ],
            [
                kCGWindowOwnerName as String: "Safari",
                kCGWindowName as String: "Apple",
                kCGWindowNumber as String: CGWindowID(200),
                kCGWindowBounds as String: ["X": CGFloat(0), "Y": CGFloat(0), "Width": CGFloat(800), "Height": CGFloat(600)]
            ],
            [
                kCGWindowOwnerName as String: "Finder",
                kCGWindowName as String: "", // Empty title — should be filtered
                kCGWindowNumber as String: CGWindowID(300),
                kCGWindowBounds as String: ["X": CGFloat(0), "Y": CGFloat(0), "Width": CGFloat(800), "Height": CGFloat(600)]
            ],
        ]

        let entries = FinderWindowService.parseCGWindowList(windowList)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Documents")
        XCTAssertEqual(entries.first?.windowID, 100)
    }

    func testParseCGWindowListExtractsBounds() {
        let windowList: [[String: Any]] = [
            [
                kCGWindowOwnerName as String: "Finder",
                kCGWindowName as String: "Desktop",
                kCGWindowNumber as String: CGWindowID(50),
                kCGWindowBounds as String: ["X": CGFloat(100), "Y": CGFloat(200), "Width": CGFloat(400), "Height": CGFloat(300)]
            ]
        ]

        let entries = FinderWindowService.parseCGWindowList(windowList)

        // "Desktop" is a valid title (it's the desktop window name but not "Finder")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.bounds, CGRect(x: 100, y: 200, width: 400, height: 300))
    }

    func testFiltersFinderDesktopWindow() {
        let windowList: [[String: Any]] = [
            [
                kCGWindowOwnerName as String: "Finder",
                kCGWindowName as String: "Finder", // Desktop window is named "Finder"
                kCGWindowNumber as String: CGWindowID(1),
                kCGWindowBounds as String: ["X": CGFloat(0), "Y": CGFloat(0), "Width": CGFloat(1920), "Height": CGFloat(1080)]
            ]
        ]

        let entries = FinderWindowService.parseCGWindowList(windowList)
        XCTAssertEqual(entries.count, 0) // Should be filtered out
    }
}
