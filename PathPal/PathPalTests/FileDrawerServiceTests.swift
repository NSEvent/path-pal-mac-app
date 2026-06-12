import XCTest
@testable import PathPal

final class FileDrawerServiceTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDrawerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "test".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testAddFiles() throws {
        let service = FileDrawerService(storageDirectory: tempDir)
        let file = try makeFile("a.txt")
        service.addFiles([file])
        XCTAssertEqual(service.state.items.map(\.lastPathComponent), ["a.txt"])
    }

    func testAddDeduplicatesAndMovesToFront() throws {
        let service = FileDrawerService(storageDirectory: tempDir)
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        service.addFiles([a, b])
        service.addFiles([a])
        XCTAssertEqual(service.state.items.map(\.lastPathComponent), ["a.txt", "b.txt"])
        XCTAssertEqual(service.state.items.count, 2)
    }

    func testAddSkipsNonexistentFiles() {
        let service = FileDrawerService(storageDirectory: tempDir)
        service.addFiles([tempDir.appendingPathComponent("missing.txt")])
        XCTAssertTrue(service.state.items.isEmpty)
    }

    func testRemoveFile() throws {
        let service = FileDrawerService(storageDirectory: tempDir)
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        service.addFiles([a, b])
        service.removeFile(a)
        XCTAssertEqual(service.state.items.map(\.lastPathComponent), ["b.txt"])
    }

    func testClear() throws {
        let service = FileDrawerService(storageDirectory: tempDir)
        service.addFiles([try makeFile("a.txt")])
        service.clear()
        XCTAssertTrue(service.state.items.isEmpty)
    }

    func testPersistenceAcrossInstances() throws {
        let first = FileDrawerService(storageDirectory: tempDir)
        first.addFiles([try makeFile("a.txt"), try makeFile("b.txt")])

        let second = FileDrawerService(storageDirectory: tempDir)
        XCTAssertEqual(second.state.items.map(\.lastPathComponent), ["a.txt", "b.txt"])
    }

    func testLoadDropsDeletedFiles() throws {
        let first = FileDrawerService(storageDirectory: tempDir)
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        first.addFiles([a, b])
        try FileManager.default.removeItem(at: a)

        let second = FileDrawerService(storageDirectory: tempDir)
        XCTAssertEqual(second.state.items.map(\.lastPathComponent), ["b.txt"])
    }

    func testPruneMissingItems() throws {
        let service = FileDrawerService(storageDirectory: tempDir)
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        service.addFiles([a, b])
        try FileManager.default.removeItem(at: b)
        service.pruneMissingItems()
        XCTAssertEqual(service.state.items.map(\.lastPathComponent), ["a.txt"])
    }
}
