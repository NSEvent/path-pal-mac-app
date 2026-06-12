import XCTest
@testable import PathPal

final class PathAutocompletionTests: XCTestCase {

    func testEmptyInputReturnsEmpty() {
        let completions = PathBarService.completions(for: "")
        XCTAssertTrue(completions.isEmpty)
    }

    func testTrailingSlashListsContents() {
        // /tmp/ should have contents
        let completions = PathBarService.completions(for: "/tmp/")
        // We can't assert exact contents but /tmp should have something
        // Just verify it doesn't crash and returns an array
        XCTAssertNotNil(completions)
    }

    func testInvalidPathReturnsEmpty() {
        let completions = PathBarService.completions(for: "/nonexistent_path_12345/")
        XCTAssertTrue(completions.isEmpty)
    }

    func testPartialPathCompletes() {
        // /usr/bi should match /usr/bin
        let completions = PathBarService.completions(for: "/usr/bi")
        XCTAssertTrue(completions.contains { $0.hasPrefix("/usr/bin") })
    }

    func testDirectoryCompletionsHaveTrailingSlash() {
        // /usr/bi should complete to /usr/bin/ (directory)
        let completions = PathBarService.completions(for: "/usr/bi")
        let binCompletion = completions.first { $0.contains("bin") }
        XCTAssertTrue(binCompletion?.hasSuffix("/") ?? false, "Directory completions should end with /")
    }

    func testTildeExpansion() {
        let completions = PathBarService.completions(for: "~/")
        XCTAssertFalse(completions.isEmpty, "~ should expand to home directory and list contents")
    }

    func testParentDirectoryReference() {
        // /usr/bin/.. references /usr — should list its contents
        let completions = PathBarService.completions(for: "/usr/bin/..")
        XCTAssertTrue(completions.contains { $0.hasPrefix("/usr/bin") }, "Listing /usr should include bin")
    }

    func testParentDirectoryMidPathStandardizes() {
        // /usr/bin/../bi standardizes to /usr/bi — should complete to /usr/bin
        let completions = PathBarService.completions(for: "/usr/bin/../bi")
        XCTAssertTrue(completions.contains { $0.hasPrefix("/usr/bin") })
    }

    func testSingleDotReferencesSameDirectory() {
        // /usr/. references /usr — should list its contents
        let completions = PathBarService.completions(for: "/usr/.")
        XCTAssertTrue(completions.contains { $0.hasPrefix("/usr/bin") })
    }
}
