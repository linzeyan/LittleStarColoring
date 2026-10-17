import simd
import XCTest
@testable import Coloring

final class StrokeBuilderTests: XCTestCase {
    private let plain = BrushStyle(tip: .hard, spacing: 0.25, opacity: 1, blend: .over)

    private func stroke(_ style: BrushStyle, _ points: [SIMD2<Float>], seed: UInt64 = 1,
                        dt: TimeInterval = 1.0 / 60) -> [Dab] {
        var builder = StrokeBuilder(style: style, baseSize: 40, seed: seed)
        var dabs = builder.begin(at: points[0], time: 0)
        for (i, p) in points.enumerated().dropFirst() {
            dabs += builder.move(to: p, time: Double(i) * dt)
        }
        return dabs + builder.end()
    }

    /// Even spacing is what makes a stroke look continuous instead of beaded.
    func testDabsAreEvenlySpacedAlongAStraightLine() {
        let points = (0...10).map { SIMD2<Float>(Float($0) * 20, 100) }
        let dabs = stroke(plain, points)
        XCTAssertEqual(dabs.count, 21, "200 px at 10 px spacing, plus the touch-down dab")
        for (a, b) in zip(dabs, dabs.dropFirst()) {
            XCTAssertEqual(simd_distance(a.center, b.center), 10, accuracy: 0.01)
        }
        XCTAssertEqual(dabs.last!.center.x, 200, accuracy: 0.01, "the stroke reaches the finger")
    }

    func testTapLeavesOneDab() {
        var builder = StrokeBuilder(style: plain, baseSize: 40, seed: 1)
        XCTAssertEqual(builder.begin(at: SIMD2(5, 5), time: 0).count, 1)
        XCTAssertEqual(builder.end().count, 0)
    }

    /// Brush snapshots are compared run to run; jitter must come out identical.
    func testSameSeedSameStroke() {
        let jittery = BrushStyle.brush(.watercolor)
        let points = (0...8).map { SIMD2<Float>(Float($0) * 15, Float($0 % 3) * 9) }
        XCTAssertEqual(stroke(jittery, points, seed: 42), stroke(jittery, points, seed: 42))
        XCTAssertNotEqual(stroke(jittery, points, seed: 42), stroke(jittery, points, seed: 43))
    }

    /// The rainbow brush brings its own colors: a stroke goes round the color wheel and
    /// back as it runs, while every other brush paints the color the child picked.
    func testRainbowGoesRoundTheColorWheel() {
        let rainbow = BrushStyle.brush(.rainbow)
        let lap = (0...20).map { SIMD2<Float>(Float($0) * rainbow.rainbowLength / 20, 0) }
        let hues = stroke(rainbow, lap).map(\.hue)
        XCTAssertEqual(hues.first!, 0, accuracy: 0.01, "starts at red")
        XCTAssertEqual(hues[hues.count / 2], 0.5, accuracy: 0.05, "halfway round halfway along")
        XCTAssertLessThan(min(hues.last!, 1 - hues.last!), 0.02, "back to red after one lap")
        XCTAssertEqual(hues.dropLast().filter { $0 < 0 }.count, 0)
        for kind in BrushKind.allCases where kind != .rainbow {
            XCTAssertTrue(stroke(.brush(kind), lap).allSatisfy { $0.hue < 0 }, "\(kind) ignores the chosen color")
        }
    }

    /// Ink: a quick flick runs thin and dry (白 shows between the hairs), a slow drag
    /// stays full and wet.
    func testInkThinsAndDriesWithSpeed() {
        let ink = BrushStyle.brush(.ink)
        let points = (0...10).map { SIMD2<Float>(Float($0) * 60, 0) }
        let slow = stroke(ink, points, dt: 1)
        let fast = stroke(ink, points, dt: 1.0 / 120)
        let mid = { (dabs: [Dab]) in dabs[dabs.count / 2] }
        XCTAssertLessThan(mid(fast).size, mid(slow).size * 0.6)
        XCTAssertLessThan(mid(slow).dryness, 0.05)
        XCTAssertGreaterThan(mid(fast).dryness, 0.4)
    }

    /// Paint running out is one switch for every brush that carries paint (spec §7). Off,
    /// no stroke dries however long it runs; on, oil, watercolor and ink do, and only they.
    func testPaintRunsOutOnlyWhenSwitchedOn() {
        let long = (0...40).map { SIMD2<Float>(Float($0) * 60, 0) }
        for kind in BrushKind.allCases {
            let off = stroke(.brush(kind), long, dt: 1)
            XCTAssertEqual(off.map(\.dryness).max(), 0, "\(kind) dries with the switch off")
            let on = stroke(.brush(kind, paintRunsOut: true), long, dt: 1)
            XCTAssertEqual(on.last!.dryness > 0.3, [.oil, .watercolor, .ink].contains(kind), "\(kind)")
        }
        // The wash tip has no hairs for dryness to break, so a watercolor that didn't pale
        // would run out invisibly.
        let wash = stroke(.brush(.watercolor, paintRunsOut: true), long, dt: 1)
        XCTAssertLessThan(wash.last!.opacity, wash.first!.opacity * 0.6)
    }

    /// Oil runs out of paint along a long stroke, but never so far that the stroke
    /// vanishes; lifting the finger reloads the brush.
    func testOilRunsDryAlongAStrokeAndReloads() {
        let oil = BrushStyle.brush(.oil, paintRunsOut: true)
        let long = (0...40).map { SIMD2<Float>(Float($0) * 60, 0) }
        let first = stroke(oil, long, dt: 1)
        XCTAssertEqual(first.first!.dryness, 0)
        XCTAssertGreaterThan(first.last!.dryness, 0.3)
        XCTAssertLessThanOrEqual(first.map(\.dryness).max()!, StrokeBuilder.driest)
        XCTAssertEqual(stroke(oil, long, dt: 1).first!.dryness, 0, "a new stroke starts loaded")
    }

    /// A flat brush laid down sideways would leave a bar across the start of the stroke.
    func testDirectionalTipFacesTheStrokeFromItsFirstDab() {
        let oil = BrushStyle.brush(.oil)
        let down = (0...5).map { SIMD2<Float>(100, 100 + Float($0) * 20) }
        let dabs = stroke(oil, down)
        XCTAssertLessThan(simd_distance(dabs.first!.center, down[0]), 1, "the stroke still starts at the finger")
        // Within the brush's own wobble; laid down sideways would be off by π/2.
        XCTAssertEqual(dabs.first!.rotation, dabs[dabs.count / 2].rotation, accuracy: 2 * oil.rotationJitter + 0.01)

        var builder = StrokeBuilder(style: oil, baseSize: 40, seed: 1)
        XCTAssertEqual(builder.begin(at: SIMD2(5, 5), time: 0).count + builder.end().count, 1,
                       "a tap still leaves a mark")
    }

    func testBoundsCoverARotatedWideStamp() {
        let dab = Dab(center: SIMD2(100, 100), size: 20, rotation: .pi / 4, opacity: 1, lightness: 1)
        let rect = dab.bounds(aspect: 3)
        // Half-diagonal of a 60×20 quad is ~31.6.
        XCTAssertLessThanOrEqual(rect.x, 68)
        XCTAssertGreaterThanOrEqual(rect.x + rect.width, 132)
    }
}
