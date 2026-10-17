import SwiftUI

// SF Symbols' paint bucket needs iOS 26 and its eraser iOS 16; the app runs on 15.

/// A tipped bucket pouring the current color.
struct BucketIcon: View {
    let paint: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let ink = GraphicsContext.Shading.color(Theme.selection)
            let fill = GraphicsContext.Shading.color(paint)
            let line = 0.045 * s

            let pool = Path(ellipseIn: CGRect(x: 0.5 * s, y: 0.72 * s, width: 0.42 * s, height: 0.15 * s))
            context.fill(pool, with: fill)
            context.stroke(pool, with: ink, lineWidth: line * 0.6)
            var drip = Path()
            drip.move(to: CGPoint(x: 0.64 * s, y: 0.42 * s))
            drip.addQuadCurve(to: CGPoint(x: 0.72 * s, y: 0.77 * s), control: CGPoint(x: 0.8 * s, y: 0.5 * s))
            context.stroke(drip, with: fill, style: StrokeStyle(lineWidth: 0.09 * s, lineCap: .round))

            var bucket = context
            bucket.translateBy(x: 0.38 * s, y: 0.45 * s)
            bucket.rotate(by: .degrees(35))
            var body = Path()
            body.move(to: CGPoint(x: -0.2 * s, y: -0.18 * s))
            body.addLine(to: CGPoint(x: 0.2 * s, y: -0.18 * s))
            body.addLine(to: CGPoint(x: 0.15 * s, y: 0.22 * s))
            body.addLine(to: CGPoint(x: -0.15 * s, y: 0.22 * s))
            body.closeSubpath()
            bucket.fill(body, with: .color(Color(white: 0.86)))
            bucket.stroke(body, with: ink, style: StrokeStyle(lineWidth: line, lineJoin: .round))
            let mouth = Path(ellipseIn: CGRect(x: -0.2 * s, y: -0.24 * s, width: 0.4 * s, height: 0.12 * s))
            bucket.fill(mouth, with: fill)
            bucket.stroke(mouth, with: ink, lineWidth: line)
            var handle = Path()
            handle.addArc(center: CGPoint(x: 0, y: -0.14 * s), radius: 0.22 * s,
                          startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
            bucket.stroke(handle, with: ink, style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))
        }
    }
}

/// Each brush as the real tool a child knows, with its tip or paint in the current color.
/// Drawn along the x axis, tip at −x, then turned so the tip points to the bottom left.
struct BrushIcon: View {
    let kind: BrushKind
    let paint: Color

    private static let wood = Color(red: 0.93, green: 0.78, blue: 0.56)
    private static let metal = Color(white: 0.8)

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            var page = context
            page.translateBy(x: size.width / 2, y: size.height / 2)
            var tool = page
            tool.rotate(by: .degrees(-45))
            let pen = Pen(context: tool, s: s)
            switch kind {
            case .crayon: crayon(pen)
            case .marker: marker(pen)
            case .watercolor: watercolor(pen)
            case .oil: oil(pen)
            case .ink: ink(pen, page: page, s: s)
            // Upright: a spray gun reads by its grip and cup, which a tilt would hide.
            case .airbrush: airbrush(Pen(context: page, s: s))
            case .rainbow: rainbow(pen)
            case .glitter: glitter(pen, page: Pen(context: page, s: s))
            case .stars: wand(Pen(context: page, s: s))
            case .puffy: puffy(pen)
            case .chalk: chalk(pen)
            case .pencil: pencil(pen)
            }
        }
    }

    private func crayon(_ pen: Pen) {
        pen.draw(pen.polygon([(-0.2, -0.1), (-0.4, -0.035), (-0.4, 0.035), (-0.2, 0.1)]), paint)
        let body = pen.box(-0.2, 0.42, height: 0.2, radius: 0.03)
        pen.context.fill(body, with: .color(paint))
        // The paper wrapper, lighter than the wax, with its two printed bands.
        pen.context.fill(pen.box(-0.08, 0.3, height: 0.2), with: .color(.white.opacity(0.5)))
        for x in [-0.04, 0.26] {
            pen.context.stroke(pen.polygon([(x, -0.1), (x, 0.1)], closed: false), with: .color(Theme.selection),
                               lineWidth: pen.line * 0.6)
        }
        pen.context.stroke(body, with: .color(Theme.selection), style: pen.outline)
    }

    private func marker(_ pen: Pen) {
        pen.draw(pen.polygon([(-0.24, -0.06), (-0.32, -0.06), (-0.39, 0.06), (-0.24, 0.06)]), paint)
        pen.draw(pen.polygon([(-0.12, -0.12), (-0.24, -0.07), (-0.24, 0.07), (-0.12, 0.12)]), Color(white: 0.7))
        pen.draw(pen.box(-0.13, 0.28, height: 0.24, radius: 0.05), Color(white: 0.97))
        pen.draw(pen.box(0.2, 0.42, height: 0.27, radius: 0.07), paint)
    }

    private func watercolor(_ pen: Pen) {
        // A wash drying around the tip, its rim darker — the watercolor brush's own look.
        let wash = Path(ellipseIn: CGRect(x: -0.52 * pen.s, y: -0.16 * pen.s, width: 0.32 * pen.s, height: 0.32 * pen.s))
        pen.context.fill(wash, with: .color(paint.opacity(0.35)))
        pen.context.stroke(wash, with: .color(paint.opacity(0.7)), lineWidth: pen.line * 0.6)
        pen.draw(pen.box(0.02, 0.44, height: 0.08, radius: 0.04), Self.wood)
        pen.draw(pen.box(-0.12, 0.04, height: 0.11, radius: 0.02), Self.metal)
        pen.draw(pen.tuft(from: -0.12, to: -0.4, width: 0.13, bulge: 0.3), paint)
    }

    private func oil(_ pen: Pen) {
        pen.draw(pen.box(0.06, 0.44, height: 0.1, radius: 0.05), Color(red: 0.72, green: 0.48, blue: 0.3))
        pen.draw(pen.polygon([(0.08, -0.06), (-0.1, -0.1), (-0.1, 0.1), (0.08, 0.06)]), Self.metal)
        let bristles = pen.box(-0.34, -0.09, height: 0.2, radius: 0.03)
        pen.context.fill(bristles, with: .color(paint))
        for y in [-0.035, 0.035] {
            pen.context.stroke(pen.polygon([(-0.3, y), (-0.12, y)], closed: false),
                               with: .color(Theme.selection.opacity(0.5)), lineWidth: pen.line * 0.4)
        }
        pen.context.stroke(bristles, with: .color(Theme.selection), style: pen.outline)
    }

    private func ink(_ pen: Pen, page: GraphicsContext, s: CGFloat) {
        // Bamboo handle with its nodes, lacquered collar, long pointed hair.
        let handle = pen.box(0.0, 0.44, height: 0.075, radius: 0.035)
        pen.draw(handle, Color(red: 0.86, green: 0.8, blue: 0.52))
        for x in [0.16, 0.31] {
            pen.context.stroke(pen.polygon([(x, -0.0375), (x, 0.0375)], closed: false),
                               with: .color(Theme.selection), lineWidth: pen.line * 0.5)
        }
        pen.draw(pen.box(-0.06, 0.02, height: 0.1, radius: 0.015), Color(white: 0.25))
        pen.draw(pen.tuft(from: -0.06, to: -0.44, width: 0.115, bulge: 0.45), paint)
        // An ink drop, upright on the page rather than along the brush.
        let cx = 0.18 * s, cy = 0.3 * s, r = 0.065 * s
        var drop = Path()
        drop.move(to: CGPoint(x: cx, y: cy - 1.9 * r))
        drop.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + 0.9 * r, y: cy - r))
        drop.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(0), endAngle: .degrees(180),
                    clockwise: false)
        drop.addQuadCurve(to: CGPoint(x: cx, y: cy - 1.9 * r), control: CGPoint(x: cx - 0.9 * r, y: cy - r))
        page.fill(drop, with: .color(paint))
        page.stroke(drop, with: .color(Theme.selection), lineWidth: pen.line * 0.8)
    }

    private func airbrush(_ pen: Pen) {
        // The mist it throws, fanning out from the nozzle.
        let mist: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.27, -0.05, 0.035), (-0.34, -0.13, 0.03), (-0.35, 0.03, 0.03), (-0.42, -0.06, 0.025),
            (-0.43, 0.09, 0.022), (-0.44, -0.19, 0.02), (-0.36, 0.14, 0.018), (-0.3, -0.21, 0.016),
        ]
        for (x, y, r) in mist {
            pen.context.fill(Path(ellipseIn: CGRect(x: (x - r) * pen.s, y: (y - r) * pen.s,
                                                    width: 2 * r * pen.s, height: 2 * r * pen.s)),
                             with: .color(paint))
        }
        pen.draw(pen.polygon([(0.12, 0.02), (0.27, 0.02), (0.23, 0.38), (0.08, 0.38)]), Color(white: 0.4))
        pen.draw(pen.polygon([(-0.21, -0.09), (-0.1, -0.09), (-0.1, -0.01), (-0.21, -0.01)]), Self.metal)
        pen.draw(Path(roundedRect: CGRect(x: -0.12 * pen.s, y: -0.13 * pen.s, width: 0.48 * pen.s, height: 0.17 * pen.s),
                      cornerRadius: 0.06 * pen.s), Color(white: 0.92))
        // The cup on top holds the paint.
        pen.draw(pen.polygon([(-0.01, -0.13), (0.19, -0.13), (0.22, -0.4), (-0.04, -0.4)]), paint)
    }

    /// A marker striped in its own colors: this one ignores the palette.
    private func rainbow(_ pen: Pen) {
        let bands = [Color(red: 0.9, green: 0.22, blue: 0.21), Color(red: 1, green: 0.55, blue: 0),
                     Color(red: 1, green: 0.84, blue: 0.2), Color(red: 0.26, green: 0.63, blue: 0.28),
                     Color(red: 0.12, green: 0.53, blue: 0.9), Color(red: 0.56, green: 0.14, blue: 0.67)]
        pen.draw(pen.polygon([(-0.24, -0.06), (-0.32, -0.06), (-0.39, 0.06), (-0.24, 0.06)]), bands[0])
        pen.draw(pen.polygon([(-0.12, -0.12), (-0.24, -0.07), (-0.24, 0.07), (-0.12, 0.12)]), Color(white: 0.7))
        let body = pen.box(-0.13, 0.42, height: 0.24, radius: 0.05)
        var striped = pen.context
        striped.clip(to: body)
        for (i, band) in bands.enumerated() {
            striped.fill(Path(CGRect(x: -0.13 * pen.s, y: (-0.12 + CGFloat(i) * 0.04) * pen.s,
                                     width: 0.55 * pen.s, height: 0.04 * pen.s)), with: .color(band))
        }
        pen.context.stroke(body, with: .color(Theme.selection), style: pen.outline)
    }

    /// A glitter-glue tube, flecked, with sparkles by its nozzle.
    private func glitter(_ pen: Pen, page: Pen) {
        pen.draw(pen.polygon([(-0.22, -0.05), (-0.4, -0.015), (-0.4, 0.015), (-0.22, 0.05)]), Color(white: 0.95))
        let body = pen.box(-0.22, 0.4, height: 0.22, radius: 0.08)
        pen.context.fill(body, with: .color(paint))
        for (x, y) in [(-0.13, -0.04), (-0.04, 0.05), (0.06, -0.06), (0.15, 0.03), (0.25, -0.03), (0.33, 0.05)] {
            pen.context.fill(Path(ellipseIn: CGRect(x: (x - 0.018) * pen.s, y: (y - 0.018) * pen.s,
                                                    width: 0.036 * pen.s, height: 0.036 * pen.s)),
                             with: .color(.white))
        }
        pen.context.stroke(body, with: .color(Theme.selection), style: pen.outline)
        for (x, y, r) in [(-0.38, 0.05, 0.1), (-0.06, 0.37, 0.075)] {
            page.draw(sparkle(x: x * page.s, y: y * page.s, r: r * page.s), paint)
        }
    }

    /// A magic wand.
    private func wand(_ pen: Pen) {
        var stick = Path()
        stick.move(to: CGPoint(x: -0.36 * pen.s, y: 0.36 * pen.s))
        stick.addLine(to: CGPoint(x: 0.06 * pen.s, y: -0.06 * pen.s))
        pen.context.stroke(stick, with: .color(Theme.selection), style: StrokeStyle(lineWidth: 0.11 * pen.s, lineCap: .round))
        pen.context.stroke(stick, with: .color(Self.wood), style: StrokeStyle(lineWidth: 0.05 * pen.s, lineCap: .round))
        pen.draw(star(x: 0.13 * pen.s, y: -0.13 * pen.s, r: 0.26 * pen.s), paint)
        for (x, y, r) in [(-0.24, -0.26, 0.08), (0.33, 0.18, 0.07)] {
            pen.draw(star(x: x * pen.s, y: y * pen.s, r: r * pen.s), paint)
        }
    }

    /// A squeeze tube with a bead of paint at its nozzle.
    private func puffy(_ pen: Pen) {
        pen.draw(pen.box(-0.17, 0.36, height: 0.26, radius: 0.05), Color(white: 0.95))
        pen.draw(pen.box(-0.06, 0.24, height: 0.13, radius: 0.03), paint)
        pen.draw(pen.box(0.36, 0.42, height: 0.28, radius: 0.01), Color(white: 0.8))
        pen.draw(pen.polygon([(-0.17, -0.07), (-0.28, -0.035), (-0.28, 0.035), (-0.17, 0.07)]), Color(white: 0.8))
        let bead = Path(ellipseIn: CGRect(x: -0.43 * pen.s, y: -0.075 * pen.s, width: 0.15 * pen.s, height: 0.15 * pen.s))
        pen.draw(bead, paint)
        pen.context.fill(Path(ellipseIn: CGRect(x: -0.4 * pen.s, y: -0.05 * pen.s, width: 0.04 * pen.s, height: 0.04 * pen.s)),
                         with: .color(.white.opacity(0.9)))
    }

    /// A blunt stick, its end worn flat, a puff of dust at the tip.
    private func chalk(_ pen: Pen) {
        for (x, y, r) in [(-0.4, -0.08, 0.025), (-0.43, 0.04, 0.02), (-0.37, 0.12, 0.018)] {
            pen.context.fill(Path(ellipseIn: CGRect(x: (x - r) * pen.s, y: (y - r) * pen.s,
                                                    width: 2 * r * pen.s, height: 2 * r * pen.s)),
                             with: .color(paint.opacity(0.6)))
        }
        pen.draw(pen.box(-0.3, 0.3, height: 0.22, radius: 0.03), paint)
        let end = Path(ellipseIn: CGRect(x: -0.34 * pen.s, y: -0.11 * pen.s, width: 0.08 * pen.s, height: 0.22 * pen.s))
        pen.context.fill(end, with: .color(paint))
        pen.context.fill(end, with: .color(.white.opacity(0.35)))
        pen.context.stroke(end, with: .color(Theme.selection), style: pen.outline)
    }

    /// A colored pencil: lead, shaved wood, painted body, ferrule and eraser.
    private func pencil(_ pen: Pen) {
        pen.draw(pen.polygon([(-0.18, -0.08), (-0.31, -0.03), (-0.31, 0.03), (-0.18, 0.08)]), Self.wood)
        pen.draw(pen.polygon([(-0.31, -0.03), (-0.42, 0), (-0.31, 0.03)]), paint)
        pen.draw(pen.box(-0.18, 0.3, height: 0.16), paint)
        pen.context.stroke(pen.polygon([(-0.18, 0), (0.3, 0)], closed: false),
                           with: .color(Theme.selection.opacity(0.4)), lineWidth: pen.line * 0.5)
        pen.draw(pen.box(0.3, 0.36, height: 0.17), Self.metal)
        pen.draw(pen.box(0.36, 0.44, height: 0.16, radius: 0.03), Color(red: 0.98, green: 0.62, blue: 0.68))
    }

    private func star(x: CGFloat, y: CGFloat, r: CGFloat) -> Path {
        var path = Path()
        for i in 0..<10 {
            let radius = i % 2 == 0 ? r : r * 0.45
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let point = CGPoint(x: x + radius * cos(angle), y: y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Four points, pinched in: the twinkle drawn beside anything shiny.
    private func sparkle(x: CGFloat, y: CGFloat, r: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: y - r))
        for (dx, dy) in [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)] {
            path.addQuadCurve(to: CGPoint(x: x + dx * r, y: y + dy * r), control: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }

    /// Shapes in units of the icon size, along the tool's axis.
    private struct Pen {
        let context: GraphicsContext
        let s: CGFloat
        var line: CGFloat { 0.04 * s }
        var outline: StrokeStyle { StrokeStyle(lineWidth: line, lineJoin: .round) }

        func draw(_ path: Path, _ fill: Color) {
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(Theme.selection), style: outline)
        }

        func box(_ x0: CGFloat, _ x1: CGFloat, height: CGFloat, radius: CGFloat = 0) -> Path {
            Path(roundedRect: CGRect(x: x0 * s, y: -height / 2 * s, width: (x1 - x0) * s, height: height * s),
                 cornerRadius: radius * s)
        }

        func polygon(_ points: [(CGFloat, CGFloat)], closed: Bool = true) -> Path {
            var path = Path()
            path.addLines(points.map { CGPoint(x: $0.0 * s, y: $0.1 * s) })
            if closed { path.closeSubpath() }
            return path
        }

        /// A brush's hair: full width at the collar, swelling, then drawn to a point.
        func tuft(from base: CGFloat, to tip: CGFloat, width: CGFloat, bulge: CGFloat) -> Path {
            let half = width / 2
            let control = base + (tip - base) * bulge
            var path = Path()
            path.move(to: CGPoint(x: base * s, y: -half * s))
            path.addQuadCurve(to: CGPoint(x: tip * s, y: 0), control: CGPoint(x: control * s, y: -half * 1.6 * s))
            path.addQuadCurve(to: CGPoint(x: base * s, y: half * s), control: CGPoint(x: control * s, y: half * 1.6 * s))
            path.closeSubpath()
            return path
        }
    }
}

/// A two-tone school eraser.
struct EraserIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            var eraser = context
            eraser.translateBy(x: 0.5 * s, y: 0.5 * s)
            eraser.rotate(by: .degrees(-35))
            let w = 0.72 * s, h = 0.32 * s
            let whole = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let shape = Path(roundedRect: whole, cornerRadius: 0.07 * s)
            eraser.fill(shape, with: .color(Color(red: 0.36, green: 0.56, blue: 0.92)))
            var tip = eraser
            tip.clip(to: Path(CGRect(x: -w / 2, y: -h / 2, width: w * 0.42, height: h)))
            tip.fill(shape, with: .color(Color(red: 0.98, green: 0.62, blue: 0.68)))
            eraser.stroke(shape, with: .color(Theme.selection), lineWidth: 0.045 * s)
        }
    }
}
