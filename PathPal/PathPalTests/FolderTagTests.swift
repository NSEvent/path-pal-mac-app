import XCTest
@testable import PathPal

final class FolderTagTests: XCTestCase {

    func testNoneReturnsNilColor() {
        XCTAssertNil(FolderTag.none.color)
    }

    func testAllNonNoneTagsHaveColors() {
        for tag in FolderTag.allCases where tag != .none {
            XCTAssertNotNil(tag.color, "\(tag.name) should have a color")
        }
    }

    func testRawValues() {
        XCTAssertEqual(FolderTag.none.rawValue, 0)
        XCTAssertEqual(FolderTag.gray.rawValue, 1)
        XCTAssertEqual(FolderTag.green.rawValue, 2)
        XCTAssertEqual(FolderTag.purple.rawValue, 3)
        XCTAssertEqual(FolderTag.blue.rawValue, 4)
        XCTAssertEqual(FolderTag.yellow.rawValue, 5)
        XCTAssertEqual(FolderTag.red.rawValue, 6)
        XCTAssertEqual(FolderTag.orange.rawValue, 7)
    }

    func testInitFromRawValue() {
        XCTAssertEqual(FolderTag(rawValue: 0), FolderTag.none)
        XCTAssertEqual(FolderTag(rawValue: 1), FolderTag.gray)
        XCTAssertEqual(FolderTag(rawValue: 6), FolderTag.red)
        XCTAssertEqual(FolderTag(rawValue: 7), FolderTag.orange)
    }

    func testNames() {
        XCTAssertEqual(FolderTag.red.name, "Red")
        XCTAssertEqual(FolderTag.blue.name, "Blue")
        XCTAssertEqual(FolderTag.none.name, "None")
    }
}
