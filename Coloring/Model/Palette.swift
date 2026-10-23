import UIKit

/// Straight (non-premultiplied) sRGB color — the unit fills are chosen and saved in.
struct RGBA: Hashable, Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8 = 255

    static let white = RGBA(r: 255, g: 255, b: 255)

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// Premultiplied, 0...1 — what the shaders consume.
    var premultiplied: SIMD4<Float> {
        let alpha = Float(a) / 255
        return SIMD4(Float(r) / 255 * alpha, Float(g) / 255 * alpha, Float(b) / 255 * alpha, alpha)
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

enum Palette {
    /// Two skin tones because children color people, and a single "peach" tells some
    /// of them their own skin isn't a color. White doubles as "back to paper". White to
    /// black run light to dark, three grays between them, so the row reads as one scale.
    static let colors: [RGBA] = [
        "#E53935", "#FB8C00", "#FDD835", "#9CCC65", "#43A047", "#4FC3F7", "#1E88E5",
        "#8E24AA", "#F48FB1", "#F6D3B3", "#A86B4C", "#6D4C41",
        "#FFFFFF", "#C8C8C8", "#9A9A9A", "#616161", "#212121",
    ].map { RGBA(hex: $0)! }
}

/// The child's own color: pick a hue, make it paler or darker, then as bright or as gray
/// as wanted. Every slider draws its track with this same function, so the track shows
/// exactly what you'll get.
struct CustomColor: Equatable, Sendable {
    /// 0...1 around the color wheel.
    var hue = 0.55
    /// 0 pale … 0.5 the pure hue … 1 dark.
    var shade = 0.5
    /// 0 gray … 1 the full color. Toward a gray of the same lightness, so the muted colors
    /// in between (dusty blue, olive) keep the lightness the shade slider chose.
    var vividness = 1.0

    var rgba: RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
        // Up to 85% of the way to white or black, so even the ends keep a trace of the hue.
        let t = (shade - 0.5) * 2 * 0.85
        let toward: CGFloat = t < 0 ? 1 : 0
        let amount = CGFloat(abs(t))
        func shaded(_ c: CGFloat) -> CGFloat { c + (toward - c) * amount }
        let (sr, sg, sb) = (shaded(r), shaded(g), shaded(b))
        let gray = 0.299 * sr + 0.587 * sg + 0.114 * sb
        func channel(_ c: CGFloat) -> UInt8 { UInt8((gray + (c - gray) * CGFloat(vividness)) * 255 + 0.5) }
        return RGBA(r: channel(sr), g: channel(sg), b: channel(sb))
    }
}

enum BrushSize: Int, CaseIterable, Sendable {
    case small, medium, large

    /// Diameter in canvas pixels before a brush's own scale. The 2048 px canvas shows
    /// at ~720 pt on an iPad mini 4, so these are roughly 8 / 17 / 34 pt.
    var canvasPixels: Float { [24, 48, 96][rawValue] }

    /// Stamps read as pictures, so they start much larger than a line.
    var stampPixels: Float { [96, 160, 256][rawValue] }

    /// The size slider's 0...1 → 8...200 px. Exponential, so the small sizes a child
    /// tells apart easily aren't squeezed into one end of the track.
    static func canvasPixels(custom t: Float) -> Float { 8 * pow(25, t) }

    /// 64...320 px; stamp textures are drawn at 256, so the top end softens only slightly.
    static func stampPixels(custom t: Float) -> Float { 64 * pow(5, t) }
}
