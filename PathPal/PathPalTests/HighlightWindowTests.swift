import XCTest
@testable import PathPal

final class HighlightWindowTests: XCTestCase {

    // MARK: - Finder Path

    func testFinderPathReturnsCorrectPath() {
        let finderWindow = FinderWindow(
            windowID: 1,
            title: "Documents",
            bounds: CGRect(x: 100, y: 200, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.finderPath, "/Users/kevin/Documents")
    }

    func testFinderPathWithNestedPath() {
        let finderWindow = FinderWindow(
            windowID: 2,
            title: "Models",
            bounds: CGRect(x: 50, y: 100, width: 600, height: 400),
            path: "/Users/kevin/Projects/App/Sources/Models"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.finderPath, "/Users/kevin/Projects/App/Sources/Models")
    }

    func testFinderPathWithSpaces() {
        let finderWindow = FinderWindow(
            windowID: 3,
            title: "Work",
            bounds: CGRect(x: 0, y: 0, width: 500, height: 300),
            path: "/Users/kevin/My Projects/Work"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.finderPath, "/Users/kevin/My Projects/Work")
    }

    func testFinderWindowIDReturnsOriginalID() {
        let finderWindow = FinderWindow(
            windowID: 123,
            title: "Work",
            bounds: CGRect(x: 0, y: 0, width: 500, height: 300),
            path: "/Users/kevin/Work"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.finderWindowID, 123)
    }

    func testFrameInScreenCGReturnsFinderBounds() {
        let bounds = CGRect(x: 40, y: 80, width: 500, height: 300)
        let finderWindow = FinderWindow(
            windowID: 124,
            title: "Work",
            bounds: bounds,
            path: "/Users/kevin/Work"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.frameInScreenCG, bounds)
    }

    func testSetHighlightedTracksHoverState() {
        let finderWindow = FinderWindow(
            windowID: 125,
            title: "Work",
            bounds: CGRect(x: 0, y: 0, width: 500, height: 300),
            path: "/Users/kevin/Work"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)

        XCTAssertFalse(highlightWindow.isHighlightedForHover)
        highlightWindow.setHighlighted(true)
        XCTAssertTrue(highlightWindow.isHighlightedForHover)
        highlightWindow.setHighlighted(false)
        XCTAssertFalse(highlightWindow.isHighlightedForHover)
    }

    func testMultiRegionHitTestingOnlyIncludesVisibleRegions() {
        let finderWindow = FinderWindow(
            windowID: 126,
            title: "Work",
            bounds: CGRect(x: 0, y: 0, width: 500, height: 300),
            path: "/Users/kevin/Work"
        )
        let regions = [
            CGRect(x: 0, y: 0, width: 200, height: 300),
            CGRect(x: 300, y: 0, width: 200, height: 300),
        ]
        let highlightWindow = HighlightWindow(
            finderWindow: finderWindow,
            visibleRegionsInScreenCG: regions,
            labelFramesInScreenCG: []
        )

        XCTAssertNotNil(highlightWindow.hitRegionFrameInScreenCG(at: CGPoint(x: 100, y: 100)))
        XCTAssertNil(highlightWindow.hitRegionFrameInScreenCG(at: CGPoint(x: 250, y: 100)))
        XCTAssertNotNil(highlightWindow.hitRegionFrameInScreenCG(at: CGPoint(x: 400, y: 100)))
    }

    // MARK: - onClick Callback

    func testOnClickCallbackFires() {
        let finderWindow = FinderWindow(
            windowID: 4,
            title: "Downloads",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Downloads"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)

        var callbackFired = false
        highlightWindow.onClick = { callbackFired = true }

        highlightWindow.onClick?()
        XCTAssertTrue(callbackFired)
    }

    // MARK: - Style Mask

    func testWindowIsNonActivating() {
        let finderWindow = FinderWindow(
            windowID: 5,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertTrue(highlightWindow.styleMask.contains(.nonactivatingPanel))
    }

    func testWindowIsBorderless() {
        let finderWindow = FinderWindow(
            windowID: 6,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertTrue(highlightWindow.styleMask.contains(.borderless))
    }

    // MARK: - Window Behavior

    func testWindowWorksWhenModal() {
        let finderWindow = FinderWindow(
            windowID: 7,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertTrue(highlightWindow.worksWhenModal)
    }

    func testWindowLevel() {
        let finderWindow = FinderWindow(
            windowID: 8,
            title: "Documents",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            path: "/Users/kevin/Documents"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)
        XCTAssertEqual(highlightWindow.level, .modalPanel)
    }

    // MARK: - Coordinate Conversion

    func testCoordinateConversion() {
        guard let screenFrame = NSScreen.main?.frame else {
            XCTFail("No main screen available")
            return
        }

        let cgBounds = CGRect(x: 100, y: 200, width: 400, height: 300)
        let finderWindow = FinderWindow(
            windowID: 9,
            title: "Test",
            bounds: cgBounds,
            path: "/tmp"
        )
        let highlightWindow = HighlightWindow(finderWindow: finderWindow)

        let expectedCocoaY = screenFrame.height - cgBounds.origin.y - cgBounds.height

        let windowFrame = highlightWindow.frame
        XCTAssertEqual(windowFrame.origin.x, 100, accuracy: 0.5)
        XCTAssertEqual(windowFrame.origin.y, expectedCocoaY, accuracy: 0.5)
        XCTAssertEqual(windowFrame.width, 400, accuracy: 0.5)
        XCTAssertEqual(windowFrame.height, 300, accuracy: 0.5)
    }

    // MARK: - Color Assignment

    func testDifferentColorIndicesProduceDifferentColors() {
        let fw = FinderWindow(windowID: 1, title: "A", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), path: "/tmp/a")
        let hw0 = HighlightWindow(finderWindow: fw, colorIndex: 0)
        let hw1 = HighlightWindow(finderWindow: fw, colorIndex: 1)

        // Different color indices should produce different highlight colors.
        XCTAssertNotEqual(hw0.highlightColor, hw1.highlightColor)
    }

    func testColorIndexWrapsAround() {
        // There are 8 colors in the palette, index 8 should wrap to index 0
        let color0 = HighlightColor.forIndex(0)
        let color8 = HighlightColor.forIndex(8)
        XCTAssertEqual(color0.nsColor, color8.nsColor)
    }

    func testAllHighlightColorsDistinct() {
        let all = HighlightColor.allCases
        var seen = Set<String>()
        for c in all {
            let desc = c.nsColor.description
            XCTAssertFalse(seen.contains(desc), "Duplicate color: \(c)")
            seen.insert(desc)
        }
    }

    // MARK: - Label Layout

    func testLabelLayoutAssignsOneLabelPerVisibleRegion() {
        let regions = [
            HighlightLabelRegion(
                windowIndex: 0,
                regionIndex: 0,
                bounds: CGRect(x: 0, y: 0, width: 500, height: 260),
                path: "/Users/kevin/Documents"
            ),
            HighlightLabelRegion(
                windowIndex: 0,
                regionIndex: 1,
                bounds: CGRect(x: 520, y: 0, width: 300, height: 260),
                path: "/Users/kevin/Documents"
            ),
        ]

        let assignments = HighlightLabelLayout.assignments(for: regions)

        XCTAssertEqual(assignments.count, 2)
        XCTAssertNotNil(assignments[regions[0].id])
        XCTAssertNotNil(assignments[regions[1].id])
    }

    func testLabelLayoutAvoidsOverlappingLabels() {
        let regions = [
            HighlightLabelRegion(
                windowIndex: 0,
                regionIndex: 0,
                bounds: CGRect(x: 0, y: 0, width: 420, height: 240),
                path: "/Users/kevin/Documents"
            ),
            HighlightLabelRegion(
                windowIndex: 1,
                regionIndex: 0,
                bounds: CGRect(x: 0, y: 0, width: 420, height: 240),
                path: "/Users/kevin/Downloads"
            ),
        ]

        let frames = Array(HighlightLabelLayout.assignments(for: regions).values)

        XCTAssertEqual(frames.count, 2)
        XCTAssertFalse(frames[0].intersects(frames[1]))
    }

    func testLabelLayoutKeepsLabelsInsideRegions() throws {
        let region = HighlightLabelRegion(
            windowIndex: 0,
            regionIndex: 0,
            bounds: CGRect(x: 50, y: 80, width: 320, height: 180),
            path: "/Users/kevin/Projects/folder-buddy-mac-app"
        )

        let assignments = HighlightLabelLayout.assignments(for: [region])
        let frame = try XCTUnwrap(assignments[region.id])

        XCTAssertTrue(region.bounds.contains(frame))
    }

    func testLabelLayoutUsesCompactLabelForNarrowRegion() throws {
        let region = HighlightLabelRegion(
            windowIndex: 0,
            regionIndex: 0,
            bounds: CGRect(x: 20, y: 40, width: 62, height: 34),
            path: "/Users/kevin/Downloads"
        )

        let assignments = HighlightLabelLayout.assignments(for: [region])
        let frame = try XCTUnwrap(assignments[region.id])

        XCTAssertTrue(region.bounds.contains(frame))
        XCTAssertLessThanOrEqual(frame.width, region.bounds.width)
    }
}
