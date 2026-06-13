import XCTest
@testable import PathPal

final class AppFolderMemoryServiceTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppFolderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRecordFolderPath() {
        let service = AppFolderMemoryService(storageDirectory: tempDir)
        service.recordNavigation(toPath: tempDir.path, bundleID: "com.example.app", appName: "Example")
        XCTAssertEqual(service.folder(forBundleID: "com.example.app"), tempDir.path)
    }

    func testRecordFilePathStoresContainingFolder() throws {
        let file = tempDir.appendingPathComponent("doc.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let service = AppFolderMemoryService(storageDirectory: tempDir)
        service.recordNavigation(toPath: file.path, bundleID: "com.example.app", appName: "Example")
        XCTAssertEqual(service.folder(forBundleID: "com.example.app"), tempDir.path)
    }

    func testPinnedEntryNotOverwrittenByLearning() throws {
        let other = tempDir.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let service = AppFolderMemoryService(storageDirectory: tempDir)
        service.recordNavigation(toPath: tempDir.path, bundleID: "com.example.app", appName: "Example")
        service.setPinned(true, forBundleID: "com.example.app")
        service.recordNavigation(toPath: other.path, bundleID: "com.example.app", appName: "Example")
        XCTAssertEqual(service.folder(forBundleID: "com.example.app"), tempDir.path)
    }

    func testFolderNilWhenDeleted() throws {
        let gone = tempDir.appendingPathComponent("gone")
        try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
        let service = AppFolderMemoryService(storageDirectory: tempDir)
        service.recordNavigation(toPath: gone.path, bundleID: "com.example.app", appName: "Example")
        try FileManager.default.removeItem(at: gone)
        XCTAssertNil(service.folder(forBundleID: "com.example.app"))
    }

    func testPersistenceAcrossInstances() {
        let first = AppFolderMemoryService(storageDirectory: tempDir)
        first.recordNavigation(toPath: tempDir.path, bundleID: "com.example.app", appName: "Example")
        first.setPinned(true, forBundleID: "com.example.app")

        let second = AppFolderMemoryService(storageDirectory: tempDir)
        XCTAssertEqual(second.folder(forBundleID: "com.example.app"), tempDir.path)
        XCTAssertTrue(second.entries["com.example.app"]?.pinned ?? false)
    }

    func testRemoveEntry() {
        let service = AppFolderMemoryService(storageDirectory: tempDir)
        service.recordNavigation(toPath: tempDir.path, bundleID: "com.example.app", appName: "Example")
        service.removeEntry(forBundleID: "com.example.app")
        XCTAssertNil(service.folder(forBundleID: "com.example.app"))
    }

    func testSortedEntriesPinnedFirst() {
        let service = AppFolderMemoryService(storageDirectory: tempDir)
        service.recordNavigation(toPath: tempDir.path, bundleID: "com.a", appName: "Alpha")
        service.recordNavigation(toPath: tempDir.path, bundleID: "com.z", appName: "Zulu")
        service.setPinned(true, forBundleID: "com.z")
        XCTAssertEqual(service.sortedEntries.map(\.bundleID), ["com.z", "com.a"])
    }
}
