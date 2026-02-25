import XCTest
@testable import PathPal

final class OverlayWindowServiceTests: XCTestCase {

    private var service: OverlayWindowService!

    override func setUp() {
        super.setUp()
        let appState = AppState()
        service = OverlayWindowService(appState: appState)
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Sum the areas of all rects in the array.
    private func totalArea(_ rects: [CGRect]) -> CGFloat {
        rects.reduce(0) { $0 + $1.width * $1.height }
    }

    /// Check that every rect in `rects` is fully contained within `container`.
    private func assertAllContained(in container: CGRect, rects: [CGRect], file: StaticString = #file, line: UInt = #line) {
        for (i, rect) in rects.enumerated() {
            XCTAssertTrue(
                container.contains(rect),
                "Rect \(i) \(rect) is not contained within \(container)",
                file: file, line: line
            )
        }
    }

    /// Check that no rect in `rects` intersects with `excluded`.
    private func assertNoneOverlap(with excluded: CGRect, rects: [CGRect], file: StaticString = #file, line: UInt = #line) {
        for (i, rect) in rects.enumerated() {
            let intersection = rect.intersection(excluded)
            XCTAssertTrue(
                intersection.isNull || intersection.isEmpty,
                "Rect \(i) \(rect) unexpectedly overlaps with \(excluded); intersection=\(intersection)",
                file: file, line: line
            )
        }
    }

    // MARK: - Tests

    func testNoExclusionReturnsSource() {
        let source = CGRect(x: 100, y: 100, width: 500, height: 400)
        let result = service.subtractRects(from: source, excluding: [])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, source)
    }

    func testNonOverlappingExclusionReturnsSource() {
        let source = CGRect(x: 100, y: 100, width: 500, height: 400)
        // Exclusion is completely outside the source
        let exclusion = CGRect(x: 700, y: 700, width: 200, height: 200)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, source)
    }

    func testFullyCoveredReturnsEmpty() {
        let source = CGRect(x: 100, y: 100, width: 500, height: 400)
        // Exclusion exactly covers the source
        let exclusion = source
        let result = service.subtractRects(from: source, excluding: [exclusion])

        XCTAssertTrue(result.isEmpty, "Expected empty result when exclusion fully covers source, got \(result)")
    }

    func testExclusionInCenter() {
        // Source: 1000x800 starting at origin
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Centered exclusion: 200x200 in the middle
        let exclusion = CGRect(x: 400, y: 300, width: 200, height: 200)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        // Should produce 4 strips: top, bottom, left, right
        XCTAssertEqual(result.count, 4, "Expected 4 strips around centered exclusion, got \(result.count)")

        // All result rects should be within the source
        assertAllContained(in: source, rects: result)
        // None should overlap the exclusion
        assertNoneOverlap(with: exclusion, rects: result)

        // Verify total area: source area (800000) minus exclusion area (40000) = 760000
        let expectedArea: CGFloat = 1000 * 800 - 200 * 200
        XCTAssertEqual(totalArea(result), expectedArea, accuracy: 1.0)
    }

    func testExclusionAtTop() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Exclusion covers the full width at the top half (y: 0 to 400)
        let exclusion = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        // Only the bottom strip remains (y: 400..800, full width)
        XCTAssertEqual(result.count, 1, "Expected 1 strip (bottom half), got \(result.count)")

        let bottom = result[0]
        XCTAssertEqual(bottom.origin.x, 0, accuracy: 0.1)
        XCTAssertEqual(bottom.origin.y, 400, accuracy: 0.1)
        XCTAssertEqual(bottom.width, 1000, accuracy: 0.1)
        XCTAssertEqual(bottom.height, 400, accuracy: 0.1)

        assertAllContained(in: source, rects: result)
        assertNoneOverlap(with: exclusion, rects: result)
    }

    func testExclusionAtLeft() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Exclusion covers the full height on the left half
        let exclusion = CGRect(x: 0, y: 0, width: 500, height: 800)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        // Only the right strip remains (x: 500..1000, full height)
        XCTAssertEqual(result.count, 1, "Expected 1 strip (right half), got \(result.count)")

        let right = result[0]
        XCTAssertEqual(right.origin.x, 500, accuracy: 0.1)
        XCTAssertEqual(right.origin.y, 0, accuracy: 0.1)
        XCTAssertEqual(right.width, 500, accuracy: 0.1)
        XCTAssertEqual(right.height, 800, accuracy: 0.1)

        assertAllContained(in: source, rects: result)
        assertNoneOverlap(with: exclusion, rects: result)
    }

    func testExclusionAtCorner() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Exclusion at top-left corner: 300x300
        let exclusion = CGRect(x: 0, y: 0, width: 300, height: 300)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        // Expected strips:
        //   - Bottom strip: full width, y: 300..800 (height 500)
        //   - Right strip: x: 300..1000, y: 0..300 (within exclusion's Y range)
        // No top strip (exclusion starts at minY of source)
        // No left strip (exclusion starts at minX of source)
        XCTAssertEqual(result.count, 2, "Expected 2 strips for corner exclusion, got \(result.count)")

        assertAllContained(in: source, rects: result)
        assertNoneOverlap(with: exclusion, rects: result)

        // Total area: source (800000) minus exclusion (90000) = 710000
        let expectedArea: CGFloat = 1000 * 800 - 300 * 300
        XCTAssertEqual(totalArea(result), expectedArea, accuracy: 1.0)
    }

    func testMultipleExclusions() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Two non-overlapping exclusions inside the source
        let exclusion1 = CGRect(x: 100, y: 100, width: 200, height: 200)
        let exclusion2 = CGRect(x: 600, y: 400, width: 200, height: 200)
        let result = service.subtractRects(from: source, excluding: [exclusion1, exclusion2])

        // Result should have multiple strips; exact count depends on splitting order
        // but all should be within source and not overlap either exclusion
        XCTAssertFalse(result.isEmpty, "Should have visible regions after two small exclusions")

        assertAllContained(in: source, rects: result)
        assertNoneOverlap(with: exclusion1, rects: result)
        assertNoneOverlap(with: exclusion2, rects: result)

        // Total area should be source minus both exclusions (no overlap between exclusions)
        // Some area may be lost to the >10px sliver filter, but these exclusions are large enough
        // that all resulting strips should be well above 10px in both dimensions.
        let exclusionArea: CGFloat = 200 * 200 + 200 * 200
        let expectedArea: CGFloat = 1000 * 800 - exclusionArea
        XCTAssertEqual(totalArea(result), expectedArea, accuracy: 1.0)
    }

    func testTinySliversFiltered() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Exclusion leaves only a 5px strip on the right (below the 10px threshold)
        // and a full-height left portion plus top/bottom strips
        let exclusion = CGRect(x: 0, y: 0, width: 995, height: 800)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        // The only remaining strip would be 5px wide on the right (x: 995..1000, height 800)
        // which is < 10px wide, so it should be filtered out
        XCTAssertTrue(result.isEmpty, "Expected empty result because remaining strip is < 10px wide, got \(result)")
    }

    func testTinySliversFilteredVertical() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Exclusion leaves only a 5px strip at the bottom
        let exclusion = CGRect(x: 0, y: 0, width: 1000, height: 795)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        // Remaining strip is 5px tall, should be filtered out
        XCTAssertTrue(result.isEmpty, "Expected empty result because remaining strip is < 10px tall, got \(result)")
    }

    func testExclusionLargerThanSource() {
        let source = CGRect(x: 100, y: 100, width: 500, height: 400)
        // Exclusion is bigger than source on all sides
        let exclusion = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        XCTAssertTrue(result.isEmpty, "Expected empty result when exclusion is larger than source on all sides")
    }

    func testExclusionPartialOverlapRight() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Exclusion overlaps only the right half (extends beyond source on the right)
        let exclusion = CGRect(x: 500, y: 0, width: 1000, height: 800)
        let result = service.subtractRects(from: source, excluding: [exclusion])

        // Intersection is (500, 0, 500, 800) — the right half of source
        // Remaining: left strip x: 0..500, y: 0..800 (within intersection Y range)
        // No top/bottom strips because intersection spans full height
        XCTAssertEqual(result.count, 1, "Expected 1 strip (left half), got \(result.count)")

        let left = result[0]
        XCTAssertEqual(left.origin.x, 0, accuracy: 0.1)
        XCTAssertEqual(left.origin.y, 0, accuracy: 0.1)
        XCTAssertEqual(left.width, 500, accuracy: 0.1)
        XCTAssertEqual(left.height, 800, accuracy: 0.1)

        assertAllContained(in: source, rects: result)
        assertNoneOverlap(with: exclusion, rects: result)
    }
}
