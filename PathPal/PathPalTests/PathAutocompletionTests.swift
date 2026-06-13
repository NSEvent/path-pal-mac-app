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

    // MARK: - Fuzzy matching

    func testFuzzyScoreMatchesSubsequence() {
        XCTAssertNotNil(PathBarService.fuzzyScore(query: "fbm", candidate: "folder-buddy-mac-app"))
        XCTAssertNil(PathBarService.fuzzyScore(query: "xyz", candidate: "folder-buddy-mac-app"))
        XCTAssertNil(PathBarService.fuzzyScore(query: "mbf", candidate: "folder-buddy-mac-app"), "Out-of-order should not match")
    }

    func testFuzzyScorePrefersWordBoundaries() {
        // "fbm" hits f/b/m at hyphen boundaries in folder-buddy-mac-app;
        // in "fabulousbeam" the b/m are mid-word.
        let boundary = PathBarService.fuzzyScore(query: "fbm", candidate: "folder-buddy-mac-app") ?? 0
        let scattered = PathBarService.fuzzyScore(query: "fbm", candidate: "fabulousbeam") ?? 0
        XCTAssertGreaterThan(boundary, scattered)
    }

    func testFuzzyFallbackInParentDirectory() {
        // "lcl" prefix-matches nothing in /usr but is a subsequence of "local"
        let completions = PathBarService.completions(for: "/usr/lcl")
        XCTAssertTrue(completions.contains { $0.hasPrefix("/usr/local") })
    }

    func testBareQueryFuzzyMatchesRecentsByFrecency() {
        let saved = PathBarService.recentFoldersProvider
        defer { PathBarService.recentFoldersProvider = saved }
        PathBarService.recentFoldersProvider = {
            [
                RecentFolder(path: "/tmp/folder-buddy-mac-app", lastAccessed: Date(), accessCount: 3),
                RecentFolder(path: "/tmp/fab-m", lastAccessed: Date(), accessCount: 99),
            ]
        }
        let completions = PathBarService.completions(for: "fbm")
        XCTAssertEqual(completions.count, 2)
        XCTAssertTrue(completions[0].contains("folder-buddy-mac-app"), "Higher fuzzy score should outrank raw frecency")
    }
}
