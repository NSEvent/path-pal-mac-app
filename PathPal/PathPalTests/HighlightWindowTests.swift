import XCTest
@testable import PathPal

final class HighlightWindowTests: XCTestCase {

    // MARK: - Finder Path

    func testFinderPathReturnsCorrectPath() {
        let finderWindow = FinderWindow(
            windowID: 1,
            title: "Documents",
            bounds: CGRect(x: 100, y: 200, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.finderPath, "/Users/kevin/Documents")
    }

    func testFinderPathWithNestedPath() {
        let finderWindow = FinderWindow(
            windowID: 2,
            title: "Models",
            bounds: CGRect(x: 50, y: 100, width: 600, height: 400),
            path: "/Users/kevin/Projects/App/Sources/Models"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.finderPath, "/Users/kevin/Projects/App/Sources/Models")
    }

    func testFinderPathWithSpaces() {
        let finderWindow = FinderWindow(
            windowID: 3,
            title: "Work",
            bounds: CGRect(x: 0, y: 0, width: 500, height: 300),
            path: "/Users/kevin/My Projects/Work"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.finderPath, "/Users/kevin/My Projects/Work")
    }

    // MARK: - onClick Callback

    func testOnClickCallbackFires() {
        let finderWindow = FinderWindow(
            windowID: 4,
            title: "Downloads",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Downloads"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)

        var callbackFired = false
        highlightWindow.onClick = { callbackFired = true }

        // Invoke the closure directly to verify the property assignment works
        highlightWindow.onClick?()
        XCTAssertTrue(callbackFired)
    }

    // MARK: - Style Mask

    func testWindowIsNonActivating() {
        let finderWindow = FinderWindow(
            windowID: 5,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertTrue(highlightWindow.styleMask.contains(.nonactivatingPanel))
    }

    func testWindowIsBorderless() {
        let finderWindow = FinderWindow(
            windowID: 6,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertTrue(highlightWindow.styleMask.contains(.borderless))
    }

    // MARK: - Window Behavior

    func testWindowWorksWhenModal() {
        let finderWindow = FinderWindow(
            windowID: 7,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertTrue(highlightWindow.worksWhenModal)
    }

    func testWindowLevel() {
        let finderWindow = FinderWindow(
            windowID: 8,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.level, .modalPanel)
    }

    // MARK: - Coordinate Conversion

    func testCoordinateConversion() {
        guard let screenFrame = NSScreen.main?.frame else {
            XCTFail("No main screen available")
            return
        }

        // CG coords: top-left origin at (100, 200), size 400x300
        let cgBounds = CGRect(x: 100, y: 200, width: 400, height: 300)
        let finderWindow = FinderWindow(
            windowID: 9,
            title: "Test",
            bounds: cgBounds,
            path: "/tmp"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)

        // Expected Cocoa Y: screenHeight - cgY - cgHeight
        let expectedCocoaY = screenFrame.height - cgBounds.origin.y - cgBounds.height

        let windowFrame = highlightWindow.frame
        XCTAssertEqual(windowFrame.origin.x, 100, accuracy: 0.5)
        XCTAssertEqual(windowFrame.origin.y, expectedCocoaY, accuracy: 0.5)
        XCTAssertEqual(windowFrame.width, 400, accuracy: 0.5)
        XCTAssertEqual(windowFrame.height, 300, accuracy: 0.5)
    }
}
