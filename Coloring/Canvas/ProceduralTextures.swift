import Foundation
import simd

/// Brush tips and paper grain, generated at launch instead of shipped as images: the
/// numbers here are the art, and changing one is a rebuild, not a trip through an editor.
enum ProceduralTextures {
    static let tipSize = 128
    static let grainSize = 256

    /// RGBA8: R = lightness (128 keeps the color), G = the hair's paint load (dryness
    /// drops low loads first), B unused, A = coverage. x runs across the brush, y along
    /// the stroke for tips that face the direction of travel.
    static func tip(_ shape: TipShape) -> [UInt8] {
        let n = tipSize
        var rng = SplitMix64(state: 0x5EED_0000 &+ UInt64(TipShape.allCases.firstIndex(of: shape)!))
        let rim = RimNoise(rng: &rng)
        let hairs = Hairs(shape: shape, columns: n, rng: &rng)
        var out = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let u = (Float(x) + 0.5) / Float(n) - 0.5
                let v = (Float(y) + 0.5) / Float(n) - 0.5
                let d = (u * u + v * v).squareRoot()
                let angle = atan2(v, u)
                var coverage: Float
                var light: Float = 0.5
                switch shape {
                case .hard:
                    coverage = smoothstep(0.5, 0.47, d)
                case .wash:
                    // Flat in the middle with a definite, wobbly edge: the wet edge the
                    // pigment pools against.
                    let r = 0.45 + 0.05 * rim.value(angle)
                    coverage = smoothstep(r, r - 0.06, d)
                case .crayon:
                    // Full pressure in the middle, easing off toward a worn, uneven rim:
                    // against the paper grain that's solid wax inside, broken at the edge.
                    let r = 0.48 - 0.04 * rim.value(angle)
                    coverage = smoothstep(r, r - 0.22, d)
                case .ink:
                    // A soaked core, and a fringe too weak to reach the paper's valleys:
                    // against the grain it frays like ink wicking into fibers.
                    let core = smoothstep(0.39, 0.34, d)
                    let fringe = 0.45 * smoothstep(0.47 + 0.02 * rim.value(angle), 0.34, d)
                    coverage = max(core, fringe)
                case .bristle:
                    // A flat brush touches the paper along one line across the stroke, so
                    // a stroke starts and ends square; the ridges come from the hairs.
                    coverage = smoothstep(0.14, 0.06, abs(v)) * smoothstep(0.47, 0.42, abs(u))
                        * min(1, 0.4 + hairs.height[x])
                    light = 0.5 + 0.22 * hairs.slope[x]
                case .spray:
                    // A faint mist; the paint itself is the droplets splatted on below.
                    coverage = 0.18 * exp(-pow(d / 0.24, 2))
                case .glitter:
                    // Nothing but the flakes splatted on below.
                    coverage = 0
                case .star:
                    // Rounded points: a sticker-like star, not a spiky one.
                    let distance = starDistance(SIMD2(u, v), radius: 0.42, inner: 0.5) - 0.03
                    coverage = smoothstep(0.006, -0.006, distance)
                case .dome:
                    // A bead of paint lit from the top left: shade plus a highlight. The tip
                    // never turns, so every stroke is lit from the same side.
                    coverage = smoothstep(0.47, 0.44, d)
                    let nx = u / 0.46, ny = v / 0.46
                    let normal = SIMD3(nx, ny, max(0, 1 - nx * nx - ny * ny).squareRoot())
                    let diffuse = max(0, simd_dot(normal, simd_normalize(SIMD3<Float>(-0.45, -0.55, 0.7))))
                    let highlight = pow(max(0, simd_dot(normal, simd_normalize(SIMD3<Float>(-0.45, -0.55, 1.7)))), 60)
                    light = min(1, 0.5 + 0.28 * (diffuse - 0.75) + 0.5 * highlight)
                }
                let i = (y * n + x) * 4
                out[i] = UInt8(clamping: Int((light * 255).rounded()))
                out[i + 1] = UInt8(clamping: Int((hairs.load[x] * 255).rounded()))
                out[i + 2] = out[i]
                out[i + 3] = UInt8(clamping: Int((min(max(coverage, 0), 1) * 255).rounded()))
            }
        }
        if shape == .spray || shape == .glitter { splat(shape, into: &out, rng: &rng) }
        return out
    }

    /// Solid dots on the tip. Spray: droplets thick in the middle and thinning out (a 2D
    /// Gaussian), so overlapping dabs spray a stroke's middle solid while its edge stays
    /// speckled. Glitter: flakes all over, each catching the light its own way.
    private static func splat(_ shape: TipShape, into out: inout [UInt8], rng: inout SplitMix64) {
        let n = tipSize
        var placed = 0
        while placed < (shape == .spray ? 400 : 800) {
            let u1 = max((rng.signed() + 1) / 2, 1e-6), u2 = (rng.signed() + 1) / 2
            // Box–Muller for a droplet's distance from the center; a flake's is even over the disc.
            let radius = shape == .spray ? 0.17 * (-2 * log(u1)).squareRoot() : 0.44 * u1.squareRoot()
            // Flakes big enough to read as flakes: smaller, they blur into a spray.
            let size = shape == .spray ? 0.7 + (rng.signed() + 1) * 0.45 : 1.6 + (rng.signed() + 1) * 0.4
            let light: Float = shape == .spray ? 0.5 : flakeLight(rng.signed())
            // Inside the quad: a droplet cut by its edge would print a straight line.
            guard radius < 0.45 else { continue }
            let cx = (0.5 + radius * cos(2 * .pi * u2)) * Float(n)
            let cy = (0.5 + radius * sin(2 * .pi * u2)) * Float(n)
            let shade = UInt8(clamping: Int((light * 255).rounded()))
            for y in Int(cy - size - 1)...Int(cy + size + 1) {
                for x in Int(cx - size - 1)...Int(cx + size + 1) {
                    let dx = Float(x) + 0.5 - cx, dy = Float(y) + 0.5 - cy
                    let coverage = smoothstep(size + 0.5, size - 0.5, (dx * dx + dy * dy).squareRoot())
                    let alpha = UInt8(clamping: Int((coverage * 255).rounded()))
                    let i = (y * n + x) * 4
                    // The later dot lies on top.
                    if alpha > out[i + 3] {
                        out[i + 3] = alpha
                        out[i] = shade
                        out[i + 2] = shade
                    }
                }
            }
            placed += 1
        }
    }

    /// Most flakes are the color or darker; one in five is lighter, and one in seven is
    /// white: the ones catching the light. The dark ones make the white ones sparkle.
    private static func flakeLight(_ noise: Float) -> Float {
        let p = (noise + 1) / 2
        if p < 0.15 { return 1 }
        if p < 0.35 { return 0.75 }
        return 0.3 + 0.18 * (p - 0.35) / 0.65
    }

    /// Signed distance to a five-pointed star, negative inside (Inigo Quilez's sdStar5);
    /// `inner` is the inner radius as a fraction of the outer.
    private static func starDistance(_ point: SIMD2<Float>, radius: Float, inner: Float) -> Float {
        let k1 = SIMD2<Float>(0.809016994375, -0.587785252292)
        let k2 = SIMD2<Float>(-k1.x, k1.y)
        var p = SIMD2(abs(point.x), point.y)
        p -= 2 * max(simd_dot(k1, p), 0) * k1
        p -= 2 * max(simd_dot(k2, p), 0) * k2
        p.x = abs(p.x)
        p.y -= radius
        let ba = inner * SIMD2(-k1.y, k1.x) - SIMD2(0, 1)
        let h = min(max(simd_dot(p, ba) / simd_dot(ba, ba), 0), radius)
        let distance = simd_length(p - ba * h)
        return p.y * ba.x - p.x * ba.y < 0 ? -distance : distance
    }

    /// R8 tileable value noise: fine paper tooth (2 px at grainScale 1, the size of a
    /// crayon's bare specks) over a softer mottle.
    static func grain() -> [UInt8] {
        let n = grainSize
        var rng = SplitMix64(state: 0x9A9E_4000)
        var field = [Float](repeating: 0, count: n * n)
        for (cells, amplitude) in [(128, Float(0.4)), (64, 0.3), (32, 0.2), (8, 0.1)] {
            let lattice = (0..<(cells * cells)).map { _ in rng.signed() }
            let scale = Float(cells) / Float(n)
            for y in 0..<n {
                for x in 0..<n {
                    let fx = Float(x) * scale, fy = Float(y) * scale
                    let x0 = Int(fx), y0 = Int(fy)
                    let tx = fade(fx - Float(x0)), ty = fade(fy - Float(y0))
                    func at(_ i: Int, _ j: Int) -> Float { lattice[(j % cells) * cells + (i % cells)] }
                    let top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx
                    let bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx
                    field[y * n + x] += amplitude * (top + (bottom - top) * ty)
                }
            }
        }
        let lo = field.min()!, hi = field.max()!
        return field.map { UInt8(clamping: Int(((($0 - lo) / (hi - lo)) * 255).rounded())) }
    }

    /// One row across the brush: the paint ridge each column sits on, which way it slopes
    /// (for light and shade), and how much paint that column's hair carries.
    private struct Hairs {
        var height: [Float]
        /// −1…1; positive faces the light.
        var slope: [Float]
        var load: [Float]

        init(shape: TipShape, columns n: Int, rng: inout SplitMix64) {
            height = [Float](repeating: 0, count: n)
            slope = [Float](repeating: 0, count: n)
            load = [Float](repeating: 1, count: n)
            guard shape == .bristle || shape == .ink else { return }
            // A few clumps of hair make the broad ridges, single hairs the fine ones.
            var bumps: [(x: Float, width: Float, height: Float)] = (0..<6).map { i in
                (-0.4 + Float(i) * 0.16 + rng.signed() * 0.03, 0.05 + (rng.signed() + 1) * 0.02,
                 0.5 + (rng.signed() + 1) * 0.25)
            }
            bumps += (0..<40).map { _ in
                (rng.signed() * 0.45, 0.008 + (rng.signed() + 1) * 0.006, 0.05 + (rng.signed() + 1) * 0.04)
            }
            // Hairs dry out in clumps, not one by one: a drying brush leaves a few broad
            // streaks, not a comb of hairlines.
            let clumps = (0...8).map { _ in (rng.signed() + 1) / 2 }
            let hairWidth = shape == .ink ? 2 : 3
            var hair: Float = 1
            for x in 0..<n {
                let u = (Float(x) + 0.5) / Float(n) - 0.5
                height[x] = bumps.reduce(0) { $0 + $1.height * exp(-pow((u - $1.x) / $1.width, 2)) }
                let t = (u + 0.5) * 8, k = min(Int(t), 7)
                let clump = clumps[k] + (clumps[k + 1] - clumps[k]) * smoothstep(0, 1, t - Float(k))
                if x % hairWidth == 0 { hair = (rng.signed() + 1) / 2 }
                // Never 0: a fully loaded brush (dryness 0) paints with every hair.
                load[x] = 0.15 + 0.85 * (0.65 * clump + 0.35 * hair)
            }
            let top = height.max()!
            height = height.map { $0 / top }
            for x in 0..<n {
                slope[x] = height[max(x - 1, 0)] - height[min(x + 1, n - 1)]
            }
            let steepest = slope.map(abs).max()!
            slope = slope.map { $0 / steepest }
        }
    }

    /// A few random harmonics around the rim, so round tips aren't perfect circles.
    private struct RimNoise {
        let phases: [Float]

        init(rng: inout SplitMix64) {
            phases = (0..<5).map { _ in rng.signed() * .pi }
        }

        func value(_ angle: Float) -> Float {
            var sum: Float = 0
            for (k, phase) in phases.enumerated() {
                sum += sin(Float(k + 3) * angle + phase) / Float(k + 1)
            }
            return sum / 2.3
        }
    }
}

/// Hermite step from `edge0` to `edge1`; edges may be reversed for a falling step.
func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

private func fade(_ t: Float) -> Float { t * t * (3 - 2 * t) }
