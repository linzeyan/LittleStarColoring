import XCTest
@testable import Coloring

/// Guards the contract between tools/build_pages.py and the app, on the files actually
/// bundled: if Xcode re-encoded a PNG, or the pipeline changed format, region IDs would
/// silently become different numbers and fills would land in the wrong places.
final class PageAssetTests: XCTestCase {
    func testEveryBundledPageDecodesToContiguousRegionIDs() throws {
        let pages = Page.bundled()
        XCTAssertFalse(pages.isEmpty)
        for page in pages {
            let map = try RegionMap(contentsOf: page.regionsURL)
            XCTAssertEqual(map.size, CanvasSpec.size, page.id)
            let used = Set(map.labels)
            XCTAssertFalse(used.contains(0), "\(page.id): every pixel must belong to a region")
            let count = Int(used.max() ?? 0)
            XCTAssertEqual(used.count, count, "\(page.id): region IDs must be 1...N with no holes")
            XCTAssertLessThanOrEqual(count, 254, page.id)
            // The pipeline numbers regions largest-first, so the page background — what
            // surrounds the drawing at its corner — is always region 1.
            XCTAssertEqual(map.region(at: SIMD2(4, 4)), 1, page.id)
        }
    }

    /// Artwork is saved under the page ID, so two pages sharing one would overwrite each
    /// other's drawings; a category without a name shows its folder name to parents; and
    /// a category a child opens should offer a real choice, not two or three pages.
    func testCategoriesHaveNamesAndPageIDsAreUnique() {
        let categories = PageCategory.bundled()
        XCTAssertEqual(categories.count, 16)
        for category in categories {
            XCTAssertNotEqual(category.name, category.id, "no name for \(category.id)")
            XCTAssertGreaterThanOrEqual(category.pages.count, 10, category.id)
        }
        let ids = categories.flatMap(\.pages).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLineArtIsInkOverTransparentPaper() throws {
        let page = try XCTUnwrap(Page.bundled().first)
        let alpha = Bitmap.alphaBytes(of: try Bitmap.image(at: page.lineArtURL), size: CanvasSpec.size)
        XCTAssertEqual(alpha[0], 0, "page margin must be transparent")
        XCTAssertEqual(alpha.max(), 255, "lines must be fully opaque somewhere")
    }

    func testRegionLookupClampsOutsideTheCanvas() {
        let map = RegionMap(size: 2, labels: [1, 2, 3, 4])
        XCTAssertEqual(map.region(at: SIMD2(-50, -50)), 1)
        XCTAssertEqual(map.region(at: SIMD2(1.5, 0.2)), 2)
        XCTAssertEqual(map.region(at: SIMD2(0.9, 1.1)), 3)
        XCTAssertEqual(map.region(at: SIMD2(99, 99)), 4)
    }
}
