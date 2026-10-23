import XCTest
@testable import Coloring

final class PaletteTests: XCTestCase {
    /// "There's no gray": the palette has to offer one without the custom panel.
    func testPaletteHasGraysBetweenWhiteAndBlack() {
        let grays = Palette.colors.filter { $0.r == $0.g && $0.g == $0.b }
        XCTAssertGreaterThanOrEqual(grays.count, 5, "white, three grays, black")
        let lightness = grays.map(\.r)
        XCTAssertEqual(lightness, lightness.sorted(by: >), "the grays run light to dark, side by side")
    }

    /// The vividness slider is what makes gray and muted colors reachable; at full it must
    /// leave the hue + shade colors children already had untouched.
    func testVividnessRunsFromTheFullColorToAGrayOfTheSameLightness() {
        let full = CustomColor(hue: 0.6, shade: 0.3, vividness: 1)
        var old = CustomColor(hue: 0.6, shade: 0.3)
        XCTAssertEqual(full.rgba, old.rgba)

        old.vividness = 0
        let gray = old.rgba
        XCTAssertEqual(gray.r, gray.g)
        XCTAssertEqual(gray.g, gray.b)
        let luma = { (c: RGBA) in 0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b) }
        XCTAssertEqual(luma(gray), luma(full.rgba), accuracy: 1.5, "graying keeps the lightness")

        // Halfway is a muted color: still blue, just less of it.
        let muted = CustomColor(hue: 0.6, shade: 0.3, vividness: 0.5).rgba
        XCTAssertGreaterThan(muted.b, muted.r)
        XCTAssertLessThan(Int(muted.b) - Int(muted.r), Int(full.rgba.b) - Int(full.rgba.r))
    }
}
