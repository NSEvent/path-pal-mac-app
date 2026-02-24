import XCTest
@testable import PathPal

final class DialogDetectionTests: XCTestCase {

    func testClassifiesOpenDialog() {
        let result = DialogInfo.classify(buttonTitles: ["Cancel", "Open"])
        XCTAssertEqual(result, .open)
    }

    func testClassifiesSaveDialog() {
        let result = DialogInfo.classify(buttonTitles: ["Cancel", "Save"])
        XCTAssertEqual(result, .save)
    }

    func testClassifiesUploadAsOpen() {
        let result = DialogInfo.classify(buttonTitles: ["Cancel", "Upload"])
        XCTAssertEqual(result, .open)
    }

    func testClassifiesExportAsSave() {
        let result = DialogInfo.classify(buttonTitles: ["Cancel", "Export"])
        XCTAssertEqual(result, .save)
    }

    func testClassifiesChooseAsOpen() {
        let result = DialogInfo.classify(buttonTitles: ["Cancel", "Choose"])
        XCTAssertEqual(result, .open)
    }

    func testRejectsNonDialogWindow() {
        let result = DialogInfo.classify(buttonTitles: ["OK", "Cancel"])
        XCTAssertNil(result)
    }

    func testRejectsEmptyButtons() {
        let result = DialogInfo.classify(buttonTitles: [])
        XCTAssertNil(result)
    }

    func testCaseInsensitive() {
        let result = DialogInfo.classify(buttonTitles: ["cancel", "OPEN"])
        XCTAssertEqual(result, .open)
    }

    func testSaveTakesPriority() {
        // If both "Save" and "Open" appear (shouldn't happen but test priority)
        let result = DialogInfo.classify(buttonTitles: ["Save", "Open"])
        XCTAssertEqual(result, .save)
    }
}
