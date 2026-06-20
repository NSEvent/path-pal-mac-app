import XCTest
import ApplicationServices
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

    func testRejectsThinChromeWindowCandidate() {
        let result = DialogInfo.looksLikeDialogElement(
            role: kAXWindowRole,
            subrole: nil,
            title: nil,
            bounds: CGRect(x: -1, y: 1260, width: 491, height: 22),
            buttonTitles: ["Cancel", "Save"]
        )

        XCTAssertFalse(result, "Thin browser UI strips must not be treated as Save dialogs")
    }

    func testAcceptsPlausibleWindowCandidateWithCancelAndSave() {
        let result = DialogInfo.looksLikeDialogElement(
            role: kAXWindowRole,
            subrole: nil,
            title: nil,
            bounds: CGRect(x: 422, y: 449, width: 1052, height: 448),
            buttonTitles: ["Cancel", "Save"]
        )

        XCTAssertTrue(result)
    }

    func testAcceptsSheetCandidateBeforeBoundsAreReady() {
        let result = DialogInfo.looksLikeDialogElement(
            role: "AXSheet",
            subrole: nil,
            title: nil,
            bounds: nil,
            buttonTitles: ["Cancel", "Save"]
        )

        XCTAssertTrue(result)
    }

    func testRejectsImplausibleDialogBounds() {
        XCTAssertFalse(DialogInfo.isPlausibleDialogBounds(CGRect(x: -1, y: 1260, width: 491, height: 22)))
        XCTAssertTrue(DialogInfo.isPlausibleDialogBounds(CGRect(x: 422, y: 449, width: 1052, height: 448)))
    }
}
