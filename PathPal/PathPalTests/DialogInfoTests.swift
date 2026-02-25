import XCTest
@testable import PathPal

final class DialogInfoTests: XCTestCase {

    // MARK: - classify() edge cases beyond DialogDetectionTests

    func testClassifiesWithManyIrrelevantButtons() {
        let buttons = ["Cancel", "OK", "Help", "More Info", "Details", "Retry", "Open"]
        let result = DialogInfo.classify(buttonTitles: buttons)
        XCTAssertEqual(result, .open)
    }

    func testClassifiesWithWhitespaceVariants() {
        // " save " lowercased is " save ", which does not equal "save"
        let result = DialogInfo.classify(buttonTitles: [" save ", "Cancel"])
        XCTAssertNil(result, "Whitespace-padded 'save' should not match because lowercased() does not trim")
    }

    func testMultipleOpenSynonyms() {
        let result = DialogInfo.classify(buttonTitles: ["Upload", "Choose", "Cancel"])
        XCTAssertEqual(result, .open)
    }

    func testSingleButtonOpen() {
        let result = DialogInfo.classify(buttonTitles: ["Open"])
        XCTAssertEqual(result, .open)
    }

    func testSingleButtonSave() {
        let result = DialogInfo.classify(buttonTitles: ["Save"])
        XCTAssertEqual(result, .save)
    }

    func testDialogTypeRawValues() {
        XCTAssertEqual(DialogType.open.rawValue, "open")
        XCTAssertEqual(DialogType.save.rawValue, "save")
    }

    func testClassifyWithDuplicateButtons() {
        let result = DialogInfo.classify(buttonTitles: ["Open", "Open", "Cancel"])
        XCTAssertEqual(result, .open)
    }

    func testClassifyWithNumericButtonTitles() {
        let result = DialogInfo.classify(buttonTitles: ["1", "2", "3"])
        XCTAssertNil(result)
    }

    func testClassifyWithSpecialCharacters() {
        // "Open..." with an ellipsis character is not equal to "open"
        let result = DialogInfo.classify(buttonTitles: ["Open\u{2026}", "Cancel"])
        XCTAssertNil(result, "Button title with ellipsis character should not match plain 'open'")
    }
}
