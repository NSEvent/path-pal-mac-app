import XCTest
@testable import PathPal

final class FinderWindowTests: XCTestCase {

    // MARK: - Name Property

    func testNameReturnsLastPathComponent() {
        let window = FinderWindow(
            windowID: 1,
            title: "Documents",
            bounds: .zero,
            path: "/Users/kevin/Documents"
        )
        XCTAssertEqual(window.name, "Documents")
    }

    func testNameForRootPath() {
        let window = FinderWindow(
            windowID: 2,
            title: "/",
            bounds: .zero,
            path: "/"
        )
        XCTAssertEqual(window.name, "/")
    }

    func testNameForNestedPath() {
        let window = FinderWindow(
            windowID: 3,
            title: "Sources",
            bounds: .zero,
            path: "/Users/kevin/Projects/MyApp/Sources"
        )
        XCTAssertEqual(window.name, "Sources")
    }

    func testNameWithSpacesInPath() {
        let window = FinderWindow(
            windowID: 10,
            title: "Work Files",
            bounds: .zero,
            path: "/Users/kevin/My Documents/Work Files"
        )
        XCTAssertEqual(window.name, "Work Files")
    }

    func testNameWithUnicodeInPath() {
        let window = FinderWindow(
            windowID: 11,
            title: "Fotos",
            bounds: .zero,
            path: "/Users/kevin/Escritorio/Fotos \u{1F4F7}"
        )
        XCTAssertEqual(window.name, "Fotos \u{1F4F7}")
    }

    // MARK: - URL Property

    func testUrlConstruction() {
        let window = FinderWindow(
            windowID: 4,
            title: "Documents",
            bounds: .zero,
            path: "/Users/kevin/Documents"
        )
        let expectedURL = URL(fileURLWithPath: "/Users/kevin/Documents")
        XCTAssertEqual(window.url, expectedURL)
        XCTAssertTrue(window.url.isFileURL)
        XCTAssertEqual(window.url.path, "/Users/kevin/Documents")
    }

    // MARK: - ID Property

    func testIdReturnsWindowID() {
        let windowID: CGWindowID = 42
        let window = FinderWindow(
            windowID: windowID,
            title: "Downloads",
            bounds: .zero,
            path: "/Users/kevin/Downloads"
        )
        XCTAssertEqual(window.id, windowID)
        XCTAssertEqual(window.id, 42)
    }

    // MARK: - Equality

    func testEqualityByWindowIDTitlePath() {
        let window1 = FinderWindow(
            windowID: 5,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let window2 = FinderWindow(
            windowID: 5,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        XCTAssertEqual(window1, window2)
    }

    func testInequalityDifferentWindowID() {
        let window1 = FinderWindow(
            windowID: 6,
            title: "Documents",
            bounds: .zero,
            path: "/Users/kevin/Documents"
        )
        let window2 = FinderWindow(
            windowID: 7,
            title: "Documents",
            bounds: .zero,
            path: "/Users/kevin/Documents"
        )
        XCTAssertNotEqual(window1, window2)
    }

    func testInequalityDifferentPath() {
        let window1 = FinderWindow(
            windowID: 8,
            title: "Documents",
            bounds: .zero,
            path: "/Users/kevin/Documents"
        )
        let window2 = FinderWindow(
            windowID: 8,
            title: "Documents",
            bounds: .zero,
            path: "/Users/kevin/Downloads"
        )
        XCTAssertNotEqual(window1, window2)
    }

    func testEqualityIgnoresBounds() {
        let window1 = FinderWindow(
            windowID: 9,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let window2 = FinderWindow(
            windowID: 9,
            title: "Documents",
            bounds: CGRect(x: 100, y: 200, width: 1024, height: 768),
            path: "/Users/kevin/Documents"
        )
        XCTAssertEqual(window1, window2)
    }
}
