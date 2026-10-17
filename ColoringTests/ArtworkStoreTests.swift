import XCTest
@testable import Coloring

final class ArtworkStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Leaving a page and coming back must show exactly what was there.
    func testSaveThenLoadRoundTrips() async throws {
        let store = ArtworkStore(root: root)
        let size = CanvasSpec.size
        var layer = [UInt8](repeating: 0, count: size * size * 4)
        // An opaque red pixel survives PNG exactly (premultiplication is lossless at A=255).
        let i = (100 * size + 200) * 4
        layer[i] = 255
        layer[i + 3] = 255
        let thumb = Data(count: 8 * 8 * 4)
        var stamps = [UInt8](repeating: 0, count: size * size * 4)
        stamps[i + 2] = 255
        stamps[i + 3] = 255
        try await store.save("p", fills: [3: Palette.colors[4]], layer: Data(layer), stamps: Data(stamps),
                             thumbnail: thumb, thumbnailSize: 8)

        let loaded = try await store.load("p")
        XCTAssertEqual(loaded.fills, [3: Palette.colors[4]])
        let back = try XCTUnwrap(loaded.layer)
        XCTAssertEqual(Array(back[i..<i + 4]), [255, 0, 0, 255])
        XCTAssertEqual(back[0..<4], [0, 0, 0, 0])
        let stampsBack = try XCTUnwrap(loaded.stamps)
        XCTAssertEqual(Array(stampsBack[i..<i + 4]), [0, 0, 255, 255], "stamps come back on their own layer")
        let thumbnail = await store.thumbnail("p")
        XCTAssertNotNil(thumbnail)
    }

    func testUnsavedPageLoadsBlank() async throws {
        let loaded = try await ArtworkStore(root: root).load("never")
        XCTAssertTrue(loaded.fills.isEmpty)
        XCTAssertNil(loaded.layer)
        XCTAssertNil(loaded.stamps)
    }

    func testDeleteRestartsThePage() async throws {
        let store = ArtworkStore(root: root)
        let blank = Data(count: CanvasSpec.size * CanvasSpec.size * 4)
        try await store.save("p", fills: [1: .white], layer: blank, stamps: blank,
                             thumbnail: Data(count: 4), thumbnailSize: 1)
        try await store.delete("p")
        let loaded = try await store.load("p")
        XCTAssertTrue(loaded.fills.isEmpty)
        XCTAssertNil(loaded.layer)
        let thumbnail = await store.thumbnail("p")
        XCTAssertNil(thumbnail)
    }
}
