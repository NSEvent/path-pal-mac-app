import XCTest
@testable import PathPal

final class AppStateTests: XCTestCase {

    func testInitialState() {
        let state = AppState()
        XCTAssertTrue(state.recentFolders.isEmpty)
        XCTAssertTrue(state.recentFiles.isEmpty)
        XCTAssertTrue(state.finderWindows.isEmpty)
        XCTAssertNil(state.currentDialog)
        XCTAssertFalse(state.isAccessibilityGranted)
        XCTAssertFalse(state.hasCompletedOnboarding)
    }

    func testFinderWindowsStartEmpty() {
        let state = AppState()
        XCTAssertTrue(state.finderWindows.isEmpty)
        XCTAssertEqual(state.finderWindows.count, 0)
    }

    func testCurrentDialogStartsNil() {
        let state = AppState()
        XCTAssertNil(state.currentDialog)
    }

    func testAccessibilityDefaultFalse() {
        let state = AppState()
        XCTAssertFalse(state.isAccessibilityGranted)
    }

    func testOnboardingDefaultFalse() {
        let state = AppState()
        XCTAssertFalse(state.hasCompletedOnboarding)
    }

    func testCanSetFinderWindows() {
        let state = AppState()
        let windows = [
            FinderWindow(windowID: 1, title: "Desktop", bounds: .zero, path: "/Users/test/Desktop"),
            FinderWindow(windowID: 2, title: "Downloads", bounds: .zero, path: "/Users/test/Downloads"),
        ]
        state.finderWindows = windows
        XCTAssertEqual(state.finderWindows.count, 2)
        XCTAssertEqual(state.finderWindows[0].title, "Desktop")
        XCTAssertEqual(state.finderWindows[1].path, "/Users/test/Downloads")
    }

    func testCanSetRecentFolders() {
        let state = AppState()
        let folders = [
            RecentFolder(path: "/Users/test/Documents", lastAccessed: Date(), accessCount: 5),
            RecentFolder(path: "/Users/test/Projects", lastAccessed: Date(), accessCount: 3),
        ]
        state.recentFolders = folders
        XCTAssertEqual(state.recentFolders.count, 2)
        XCTAssertEqual(state.recentFolders[0].path, "/Users/test/Documents")
        XCTAssertEqual(state.recentFolders[1].accessCount, 3)
    }
}
