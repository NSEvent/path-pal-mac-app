import XCTest
@testable import PathPal

final class SettingsServiceTests: XCTestCase {
    private let settings = SettingsService.shared

    func testDefaultMaxRecentFolders() {
        // Clear any stored value
        UserDefaults.standard.removeObject(forKey: "maxRecentFolders")
        XCTAssertEqual(settings.maxRecentFolders, 50)
    }

    func testDefaultMaxRecentFiles() {
        UserDefaults.standard.removeObject(forKey: "maxRecentFiles")
        XCTAssertEqual(settings.maxRecentFiles, 50)
    }

    func testDefaultFinderPollingInterval() {
        UserDefaults.standard.removeObject(forKey: "finderPollingInterval")
        XCTAssertEqual(settings.finderPollingInterval, 10.0)
    }

    func testHighlightFinderWindowsDefaultTrue() {
        UserDefaults.standard.removeObject(forKey: "highlightFinderWindows")
        XCTAssertTrue(settings.highlightFinderWindows)
    }

    func testPathBarHotKeyEnabledDefaultTrue() {
        UserDefaults.standard.removeObject(forKey: "pathBarHotKeyEnabled")
        XCTAssertTrue(settings.pathBarHotKeyEnabled)
    }

    func testSettingsPersist() {
        settings.maxRecentFolders = 25
        XCTAssertEqual(settings.maxRecentFolders, 25)

        settings.highlightFinderWindows = false
        XCTAssertFalse(settings.highlightFinderWindows)

        // Reset
        settings.maxRecentFolders = 50
        settings.highlightFinderWindows = true
    }
}
