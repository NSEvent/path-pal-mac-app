import XCTest
@testable import PathPal

final class RecentItemsServiceTests: XCTestCase {
    private var tempDir: URL!
    private var service: RecentItemsService!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = RecentItemsService(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAddFolderMovesToTop() {
        service.addFolder("/Users/test/Documents")
        service.addFolder("/Users/test/Downloads")
        service.addFolder("/Users/test/Documents") // Re-add

        XCTAssertEqual(service.recentFolders.first?.path, "/Users/test/Documents")
        XCTAssertEqual(service.recentFolders.count, 2)
    }

    func testAddFolderIncrementsAccessCount() {
        service.addFolder("/Users/test/Documents")
        service.addFolder("/Users/test/Documents")
        service.addFolder("/Users/test/Documents")

        XCTAssertEqual(service.recentFolders.first?.accessCount, 3)
    }

    func testCapacityEvictsOldest() {
        // Default max is 50, but we add enough to test
        for i in 0..<60 {
            service.addFolder("/Users/test/folder_\(i)")
        }

        XCTAssertLessThanOrEqual(service.recentFolders.count, 50)
        // Most recent should be first
        XCTAssertEqual(service.recentFolders.first?.path, "/Users/test/folder_59")
    }

    func testDeduplication() {
        service.addFolder("/Users/test/Documents")
        service.addFolder("/Users/test/Documents")

        XCTAssertEqual(service.recentFolders.count, 1)
    }

    func testPersistenceRoundTrip() {
        service.addFolder("/Users/test/Documents")
        service.addFile("/Users/test/Documents/file.txt")

        // Create new service pointing to same directory
        let service2 = RecentItemsService(storageDirectory: tempDir)

        XCTAssertEqual(service2.recentFolders.count, 1)
        XCTAssertEqual(service2.recentFolders.first?.path, "/Users/test/Documents")
        XCTAssertEqual(service2.recentFiles.count, 1)
        XCTAssertEqual(service2.recentFiles.first?.path, "/Users/test/Documents/file.txt")
    }

    func testAddFile() {
        service.addFile("/Users/test/file1.txt")
        service.addFile("/Users/test/file2.txt")
        service.addFile("/Users/test/file1.txt") // Re-add

        XCTAssertEqual(service.recentFiles.first?.path, "/Users/test/file1.txt")
        XCTAssertEqual(service.recentFiles.count, 2)
    }
}
