import XCTest
@testable import PathPal

final class FinderFavoritesServiceTests: XCTestCase {

    // MARK: - Singleton

    func testSharedInstanceExists() {
        let shared = FinderFavoritesService.shared
        XCTAssertNotNil(shared)
    }

    // MARK: - getFavorites

    func testGetFavoritesReturnsArray() {
        let service = FinderFavoritesService.shared
        let favorites = service.getFavorites()
        // May be empty without Full Disk Access, but must return a valid array
        XCTAssertNotNil(favorites)
        // Verify each element has non-empty name and path if any exist
        for favorite in favorites {
            XCTAssertFalse(favorite.name.isEmpty, "Favorite name should not be empty")
            XCTAssertFalse(favorite.path.isEmpty, "Favorite path should not be empty")
        }
    }

    // MARK: - Refresh

    func testRefreshClearsCache() {
        let service = FinderFavoritesService.shared
        // Populate the cache by calling getFavorites
        _ = service.getFavorites()
        // Refresh should clear the cache without crashing
        service.refresh()
        // Calling getFavorites again after refresh should succeed
        let favorites = service.getFavorites()
        XCTAssertNotNil(favorites)
    }

    // MARK: - Caching Consistency

    func testGetFavoritesConsistentOnMultipleCalls() {
        let service = FinderFavoritesService.shared
        service.refresh()
        let first = service.getFavorites()
        let second = service.getFavorites()

        // Both calls should return the same count and content (cached)
        XCTAssertEqual(first.count, second.count)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.name, b.name)
            XCTAssertEqual(a.path, b.path)
        }
    }
}
