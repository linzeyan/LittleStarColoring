import XCTest
@testable import Coloring

/// Renders every brush, the eraser and stamps onto a real page and writes PNGs to
/// $SNAPSHOT_DIR (set by `make test`), so brush looks can be reviewed and tuned without
/// a device. Asserts only that each brush leaves paint: looks are a human call.
@MainActor
final class BrushSnapshotTests: XCTestCase {
    func testRenderBrushSheet() throws {
        let page = try XCTUnwrap(Page.bundled().first { $0.id.hasSuffix("bear-face") } ?? Page.bundled().first)
        let renderer = CanvasRenderer(assets: try PageAssets.load(page, artwork: Artwork()))
        renderer.setFill(Palette.colors[2], region: 2)
        let blank = renderer.snapshot(pixels: 512)

        let colors = [0, 6, 4, 7, 12, 8]
        var seed: UInt64 = 1
        func stroke(_ style: BrushStyle, tip: RenderContext.StrokeTip, size: Float, color: RGBA, x: Float = 120,
                    length: Float = 1800, row: Float, fast: Bool = false) {
            var builder = StrokeBuilder(style: style, baseSize: size, aspect: tip.aspect, seed: seed)
            seed += 1
            renderer.beginStroke(style: style, tip: tip, color: color)
            renderer.draw(builder.begin(at: SIMD2(x, row), time: 0))
            for i in 1...40 {
                let t = Float(i) / 40
                let point = SIMD2<Float>(x + length * t, row + 60 * sin(t * 3 * .pi))
                renderer.draw(builder.move(to: point, time: Double(i) / (fast ? 240 : 30)))
            }
            renderer.draw(builder.end())
            _ = renderer.endStroke()
        }

        // Paint running out: a stroke's start is each brush as it is by default, its end
        // the brush used up. Two columns of six: twelve brushes don't fit one.
        for (i, kind) in BrushKind.allCases.enumerated() {
            let style = BrushStyle.brush(kind, paintRunsOut: true)
            let tip = RenderContext.shared.tip(for: style)
            let x = Float(i < 6 ? 120 : 1080), row = Float(170 + (i % 6) * 270)
            stroke(style, tip: tip, size: BrushSize.large.canvasPixels * style.scale,
                   color: Palette.colors[colors[i % colors.count]], x: x, length: 840, row: row)
            stroke(style, tip: tip, size: BrushSize.small.canvasPixels * style.scale,
                   color: Palette.colors[colors[(i + 2) % colors.count]], x: x, length: 840, row: row + 110,
                   fast: true)
        }
        stroke(.eraser, tip: RenderContext.shared.tip(for: .eraser), size: 60, color: .white, row: 1024)
        for (i, stamp) in [Stamps.available.first!, Stamps.available.last!].enumerated() {
            let tip = RenderContext.shared.stampTip(stamp)
            var builder = StrokeBuilder(style: .stamp, baseSize: BrushSize.medium.stampPixels, aspect: tip.aspect,
                                        seed: 99)
            renderer.beginStroke(style: .stamp, tip: tip, color: Palette.colors[7])
            renderer.draw(builder.begin(at: SIMD2(400 + Float(i) * 900, 1900), time: 0))
            _ = renderer.endStroke()
        }

        // Full canvas resolution: grain and hair streaks are a few pixels wide.
        let sheet = renderer.snapshot(pixels: CanvasSpec.size)
        XCTAssertNotEqual(renderer.snapshot(pixels: 512), blank, "brushes must leave paint")

        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let image = try XCTUnwrap(Bitmap.cgImage(premultiplied: sheet, width: CanvasSpec.size,
                                                 height: CanvasSpec.size, layout: .bgra))
        let url = URL(fileURLWithPath: dir).appendingPathComponent("brushes.png")
        try Bitmap.png(image).write(to: url)
    }

    /// A real library: on a current OS every listed stamp draws (a kaomoji typo would be
    /// tofu, an emoji without its picture would drop out), every category is worth a
    /// shortcut, and nothing shows up twice.
    func testEveryStampCanBeDrawnOnThisOS() {
        XCTAssertEqual(Stamps.kaomoji.count, Stamps.emoji.count, "kaomoji share the emoji categories")
        XCTAssertEqual(Stamps.available.count, Stamps.emoji.joined().count + Stamps.kaomoji.joined().count)
        // The UI shows an emoji only through its thumbnail: never as an Apple emoji glyph.
        XCTAssertEqual(Stamps.thumbnails.count, Stamps.emoji.joined().count, "run `make stamps`")
        XCTAssertEqual(Stamps.groups.count, Stamps.emoji.count)
        for group in Stamps.groups {
            XCTAssertGreaterThanOrEqual(group.count, 10)
            // The picker starts the kaomoji rows where the first kaomoji is.
            let kinds = Stamps.available[group].map(\.kind)
            XCTAssertEqual(kinds.first, .emoji, "the shortcut shows the category's first emoji")
            XCTAssertTrue(kinds.contains(.kaomoji))
            XCTAssertFalse(zip(kinds, kinds.dropFirst()).contains { $0 == .kaomoji && $1 == .emoji },
                           "a category's emoji come before its kaomoji")
        }
        XCTAssertEqual(Set(Stamps.available).count, Stamps.available.count, "no stamp listed twice")
        XCTAssertFalse(Stamps.isRenderable(Stamp(text: "\u{E000}", kind: .kaomoji)), "private-use glyph is tofu")
    }
}
