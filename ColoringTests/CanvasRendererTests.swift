import XCTest
@testable import Coloring

/// End-to-end through the GPU: fill, stroke and undo as the composite shows them.
@MainActor
final class CanvasRendererTests: XCTestCase {
    private var renderer: CanvasRenderer!
    private var assets: PageAssets!
    private let pixels = 512
    private var scale: Int { CanvasSpec.size / pixels }

    override func setUp() async throws {
        let page = try XCTUnwrap(Page.bundled().first)
        assets = try PageAssets.load(page, artwork: Artwork())
        renderer = CanvasRenderer(assets: assets)
    }

    /// BGRA → RGB at a canvas point.
    private func color(atCanvas x: Int, _ y: Int) -> [UInt8] {
        let bytes = renderer.snapshot(pixels: pixels)
        let i = ((y / scale) * pixels + x / scale) * 4
        return [bytes[i + 2], bytes[i + 1], bytes[i]]
    }

    private func isClose(_ rgb: [UInt8], to color: RGBA, tolerance: Int = 4) -> Bool {
        zip(rgb, [color.r, color.g, color.b]).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
    }

    /// A canvas point deep inside a line, so the downscaled snapshot still reads solid ink.
    private func pointOnLine() throws -> SIMD2<Int> {
        let size = CanvasSpec.size, r = 6
        for y in stride(from: 64, to: size - 64, by: 4) {
            for x in stride(from: 64, to: size - 64, by: 4) {
                let solid = (-r...r).allSatisfy { dy in
                    (-r...r).allSatisfy { dx in assets.lineCoverage[(y + dy) * size + x + dx] == 255 }
                }
                if solid { return SIMD2(x, y) }
            }
        }
        return try XCTUnwrap(SIMD2<Int>?.none, "page has no line thick enough to sample")
    }

    private func stroke(_ style: BrushStyle, tip: RenderContext.StrokeTip, size: Float, color: RGBA,
                        from: SIMD2<Float>, to: SIMD2<Float>) -> CanvasEdit? {
        var builder = StrokeBuilder(style: style, baseSize: size, aspect: tip.aspect, seed: 3)
        renderer.beginStroke(style: style, tip: tip, color: color)
        renderer.draw(builder.begin(at: from, time: 0))
        if from != to { renderer.draw(builder.move(to: to, time: 0.1)) }
        renderer.draw(builder.end())
        return renderer.endStroke()
    }

    func testFillShowsAndUndoRestoresPaper() {
        let red = Palette.colors[0]
        XCTAssertEqual(color(atCanvas: 20, 20), [255, 255, 255])
        renderer.setFill(red, region: 1)  // the page background, see PageAssetTests
        XCTAssertEqual(color(atCanvas: 20, 20), [red.r, red.g, red.b])
        renderer.setFill(.white, region: 1)
        XCTAssertEqual(color(atCanvas: 20, 20), [255, 255, 255])
    }

    func testStrokeLandsAboveFillAndUndoRemovesOnlyIt() throws {
        let blue = Palette.colors[6], black = Palette.colors[12]
        renderer.setFill(blue, region: 1)
        let style = BrushStyle.brush(.marker)
        var builder = StrokeBuilder(style: style, baseSize: 48, seed: 1)
        renderer.beginStroke(style: style, tip: RenderContext.shared.tip(for: style), color: black)
        renderer.draw(builder.begin(at: SIMD2(40, 40), time: 0))
        renderer.draw(builder.move(to: SIMD2(300, 40), time: 0.1))
        renderer.draw(builder.end())
        let edit = try XCTUnwrap(renderer.endStroke())

        let painted = color(atCanvas: 160, 40)
        XCTAssertLessThan(Int(painted[0]) + Int(painted[1]) + Int(painted[2]), 200, "marker shows over the fill")
        XCTAssertEqual(color(atCanvas: 160, 200), [blue.r, blue.g, blue.b], "fill untouched beside the stroke")

        guard case .raster(let rect, let before) = edit else { return XCTFail("expected a raster edit") }
        XCTAssertEqual(Array(before.keys), [.paint], "a brush only touches the paint layer")
        renderer.restore(rect, .paint, from: before[.paint]!)
        XCTAssertEqual(color(atCanvas: 160, 40), [blue.r, blue.g, blue.b], "undo leaves the fill showing")
    }

    /// Stamps are stickers: over the line art and over paint laid down after them; the
    /// eraser peels them off and the line shows again.
    func testStampCoversLineArtAndEraserPeelsItOff() throws {
        let p = try pointOnLine()
        let at = SIMD2<Float>(Float(p.x), Float(p.y))
        let red = Palette.colors[0], blue = Palette.colors[6]
        XCTAssertLessThan(color(atCanvas: p.x, p.y).map(Int.init).reduce(0, +), 100, "starts on solid ink")

        // A hard round tip in the stamp style: same layer and merge as an emoji, but
        // with a known solid color at its center.
        let stampTip = RenderContext.shared.tip(for: .stamp)
        _ = stroke(.stamp, tip: stampTip, size: 96, color: red, from: at, to: at)
        XCTAssertTrue(isClose(color(atCanvas: p.x, p.y), to: red), "stamp hides the line under it")

        let marker = BrushStyle.brush(.marker)
        _ = stroke(marker, tip: RenderContext.shared.tip(for: marker), size: 120, color: blue,
                   from: at - SIMD2(200, 0), to: at + SIMD2(200, 0))
        XCTAssertTrue(isClose(color(atCanvas: p.x, p.y), to: red), "later paint goes under the stamp")

        let erase = try XCTUnwrap(stroke(.eraser, tip: RenderContext.shared.tip(for: .eraser), size: 200,
                                         color: .white, from: at, to: at))
        XCTAssertLessThan(color(atCanvas: p.x, p.y).map(Int.init).reduce(0, +), 100, "line shows again")

        guard case .raster(let rect, let before) = erase else { return XCTFail("expected a raster edit") }
        XCTAssertEqual(Set(before.keys), [.paint, .stamps], "the eraser cuts through both layers")
        for (layer, bytes) in before { renderer.restore(rect, layer, from: bytes) }
        XCTAssertTrue(isClose(color(atCanvas: p.x, p.y), to: red), "undoing the eraser brings the stamp back")
    }

    func testClearLayersLeavesBarePageAndReturnsWhatWasThere() {
        let marker = BrushStyle.brush(.marker)
        _ = stroke(marker, tip: RenderContext.shared.tip(for: marker), size: 96, color: Palette.colors[12],
                   from: SIMD2(40, 40), to: SIMD2(300, 40))
        _ = stroke(.stamp, tip: RenderContext.shared.tip(for: .stamp), size: 96, color: Palette.colors[0],
                   from: SIMD2(160, 300), to: SIMD2(160, 300))
        let painted = renderer.snapshot(pixels: pixels)

        let before = renderer.clearLayers()
        XCTAssertEqual(color(atCanvas: 160, 40), [255, 255, 255])
        XCTAssertEqual(color(atCanvas: 160, 300), [255, 255, 255])

        let whole = PixelRect(x: 0, y: 0, width: CanvasSpec.size, height: CanvasSpec.size)
        for (layer, bytes) in before { renderer.restore(whole, layer, from: bytes) }
        XCTAssertEqual(renderer.snapshot(pixels: pixels), painted, "restoring both layers is a perfect undo")
    }

    /// A frame recomposes only what changed since the last one: recomposing the whole
    /// page costs the iPad mini 4 ~12 ms of its 16.7 ms frame. Whatever a frame skips
    /// must still be right, so after every step the kept screen equals a full
    /// recompose, byte for byte.
    func testScreenKeptBetweenFramesMatchesAFullRecompose() throws {
        let gpu = RenderContext.shared
        // Not a divisor of the canvas, so update rects round at their edges.
        func matches(_ step: String, side: Int = 704, file: StaticString = #filePath, line: UInt = #line) {
            guard let commands = gpu.queue.makeCommandBuffer() else { return XCTFail("no command buffer") }
            let screen = renderer.refreshScreen(width: side, height: side, commands: commands)
            commands.commit()
            XCTAssertTrue(gpu.download(screen, bytesPerPixel: 4) == renderer.snapshot(pixels: side), step,
                          file: file, line: line)
        }

        matches("first frame")
        renderer.setFill(Palette.colors[4], region: 1)
        matches("fill")
        // Watercolor darkens its edge from texels 4 px away: the farthest any pixel reads.
        let tools: [(String, BrushStyle, RGBA)] = [("watercolor", .brush(.watercolor), Palette.colors[6]),
                                                   ("stamp", .stamp, Palette.colors[0]),
                                                   ("eraser", .eraser, .white)]
        for (name, style, color) in tools {
            let tip = gpu.tip(for: style)
            var builder = StrokeBuilder(style: style, baseSize: 96, aspect: tip.aspect, seed: 5)
            renderer.beginStroke(style: style, tip: tip, color: color)
            renderer.draw(builder.begin(at: SIMD2(300, 300), time: 0))
            matches("\(name): first dab")
            for i in 1...4 {
                renderer.draw(builder.move(to: SIMD2(300 + Float(i) * 150, 300 + Float(i) * 40), time: Double(i) / 30))
                matches("\(name): mid-stroke \(i)")
            }
            renderer.draw(builder.end())
            let edit = renderer.endStroke()
            matches("\(name): landed")
            if name == "eraser", case .raster(let rect, let before)? = edit {
                for (layer, bytes) in before { renderer.restore(rect, layer, from: bytes) }
                matches("eraser undone")
            }
        }
        // No frame between two strokes: the second clears the stroke texture first.
        let marker = BrushStyle.brush(.marker)
        _ = stroke(marker, tip: gpu.tip(for: marker), size: 60, color: Palette.colors[12],
                   from: SIMD2(100, 900), to: SIMD2(900, 950))
        _ = stroke(marker, tip: gpu.tip(for: marker), size: 60, color: Palette.colors[2],
                   from: SIMD2(100, 1000), to: SIMD2(900, 1050))
        matches("two strokes between frames")
        _ = renderer.clearLayers()
        matches("cleared")
        matches("screen resized, nothing else changed", side: 512)
    }

    func testEraserRemovesPaintButNotFill() {
        let green = Palette.colors[4]
        renderer.setFill(green, region: 1)
        for style in [BrushStyle.brush(.crayon), .eraser] {
            var builder = StrokeBuilder(style: style, baseSize: 80, seed: 2)
            renderer.beginStroke(style: style, tip: RenderContext.shared.tip(for: style), color: Palette.colors[0])
            renderer.draw(builder.begin(at: SIMD2(40, 60), time: 0))
            renderer.draw(builder.move(to: SIMD2(400, 60), time: 0.2))
            renderer.draw(builder.end())
            _ = renderer.endStroke()
        }
        XCTAssertEqual(color(atCanvas: 200, 60), [green.r, green.g, green.b])
    }
}
