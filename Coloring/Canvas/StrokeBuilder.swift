import Foundation
import simd

/// One stamp of the brush tip. Layout mirrors `Dab` in Shaders.metal (32 bytes).
struct Dab: Equatable, Sendable {
    var center: SIMD2<Float>
    var size: Float
    var rotation: Float
    var opacity: Float
    var lightness: Float
    /// 0 = loaded with paint; higher drops the hairs carrying the least (BrushStyle).
    var dryness: Float = 0
    /// Turns round the color wheel, for the rainbow brush; negative = the chosen color.
    var hue: Float = -1
}

/// Deterministic per stroke, so the same input draws the same stroke and tests and the
/// brush snapshot sheet can pin it.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [-1, 1).
    mutating func signed() -> Float {
        Float(next() >> 40) / Float(1 << 24) * 2 - 1
    }
}

/// Turns touch samples into evenly spaced dabs along a smoothed path.
///
/// Touches arrive at 60 Hz on an iPad mini 4, so a quick curve is a handful of points;
/// joining them with straight lines shows corners. Each new point instead extends a
/// quadratic Bézier between the midpoints of the last two segments.
struct StrokeBuilder {
    let style: BrushStyle
    /// Dab diameter at rest, canvas pixels.
    let baseSize: Float
    /// Width / height of the tip (stamps); spacing follows the larger side.
    let aspect: Float

    private var rng: SplitMix64
    private var points: [SIMD2<Float>] = []
    private var pathEnd = SIMD2<Float>.zero
    /// Path length walked since the last dab.
    private var carried: Float = 0
    private var direction: Float = 0
    /// A tip that faces the direction of travel can't face anywhere at touch-down; its
    /// first dab waits for the first move.
    private var firstDabPending = false
    /// Path length so far, canvas pixels: how much paint the brush has used up.
    private var travelled: Float = 0
    private var lastTime: TimeInterval = 0
    /// Canvas pixels per second, smoothed.
    private var speed: Float = 0

    /// Speed at which speedThinning / speedDrying reach full effect: a quick toddler
    /// swipe is ~1000 pt/s, ~2800 canvas px/s on a mini 4.
    static let fullSpeed: Float = 3000
    /// Never bone dry: a child's stroke may break into streaks but must not vanish.
    static let driest: Float = 0.7

    init(style: BrushStyle, baseSize: Float, aspect: Float = 1, seed: UInt64) {
        self.style = style
        self.baseSize = baseSize
        self.aspect = aspect
        self.rng = SplitMix64(state: seed)
    }

    mutating func begin(at point: SIMD2<Float>, time: TimeInterval) -> [Dab] {
        points = [point]
        pathEnd = point
        carried = 0
        travelled = 0
        lastTime = time
        speed = 0
        firstDabPending = style.followsDirection
        return firstDabPending ? [] : [makeDab(at: point)]
    }

    mutating func move(to point: SIMD2<Float>, time: TimeInterval) -> [Dab] {
        guard let last = points.last else { return [] }
        let distance = simd_distance(point, last)
        guard distance >= 0.5 else { return [] }
        let dt = Float(max(time - lastTime, 1.0 / 240))
        speed = speed == 0 ? distance / dt : speed * 0.7 + distance / dt * 0.3
        lastTime = time

        points.append(point)
        if points.count > 3 { points.removeFirst() }
        let mid = (last + point) / 2
        var out: [Dab] = []
        if points.count == 2 {
            walkLine(from: pathEnd, to: mid, into: &out)
        } else {
            walkQuad(from: pathEnd, control: last, to: mid, into: &out)
        }
        pathEnd = mid
        return out
    }

    mutating func end() -> [Dab] {
        guard let last = points.last else { return [] }
        if firstDabPending {
            // A tap: there is no direction to face, and the child still expects a mark.
            firstDabPending = false
            return [makeDab(at: last)]
        }
        guard points.count >= 2 else { return [] }
        var out: [Dab] = []
        walkLine(from: pathEnd, to: last, into: &out)
        pathEnd = last
        return out
    }

    // MARK: - Path walking

    private var speedFactor: Float { min(speed / Self.fullSpeed, 1) }
    private var currentSize: Float { baseSize * (1 - style.speedThinning * speedFactor) }
    private var dryness: Float {
        // Only a quick flick breaks up; a steady stroke stays wet.
        let fromSpeed = style.speedDrying * smoothstep(0.4, 1, speedFactor)
        let fromDistance = style.paintLength > 0
            ? style.paintDrying * smoothstep(0.2, 1, travelled / style.paintLength) : 0
        return min(Self.driest, max(fromSpeed, fromDistance))
    }
    private var currentSpacing: Float { max(1, style.spacing * currentSize * max(aspect, 1)) }

    private mutating func walkQuad(
        from a: SIMD2<Float>, control c: SIMD2<Float>, to b: SIMD2<Float>, into out: inout [Dab]
    ) {
        let estimate = simd_distance(a, c) + simd_distance(c, b)
        let steps = max(1, Int((estimate / 4).rounded(.up)))
        var previous = a
        for i in 1...steps {
            let t = Float(i) / Float(steps)
            let u = 1 - t
            let point = u * u * a + 2 * u * t * c + t * t * b
            walkLine(from: previous, to: point, into: &out)
            previous = point
        }
    }

    private mutating func walkLine(from a: SIMD2<Float>, to b: SIMD2<Float>, into out: inout [Dab]) {
        let segment = b - a
        let length = simd_length(segment)
        guard length > 0 else { return }
        direction = atan2(segment.y, segment.x)
        let spacing = currentSpacing
        var along = firstDabPending ? 0 : spacing - carried
        firstDabPending = false
        while along <= length {
            out.append(makeDab(at: a + segment * (along / length), distance: travelled + along))
            along += spacing
        }
        carried = length - (along - spacing)
        travelled += length
    }

    /// `distance`: along the path, for the rainbow; touch-down and a tap's dab are at its start.
    private mutating func makeDab(at point: SIMD2<Float>, distance: Float = 0) -> Dab {
        // Draw every random number in a fixed order so a seed always yields the same stroke.
        let sizeNoise = rng.signed(), jx = rng.signed(), jy = rng.signed()
        let rotationNoise = rng.signed(), lightNoise = rng.signed()
        let size = currentSize * (1 + style.sizeJitter * sizeNoise)
        let jitter = SIMD2(jx, jy) * style.positionJitter * size
        let facing: Float = style.followsDirection ? direction - .pi / 2 : 0
        let dry = dryness
        return Dab(
            center: point + jitter,
            size: size,
            rotation: facing + style.rotationJitter * rotationNoise,
            opacity: style.opacity * (1 - style.dryFading * dry),
            lightness: 1 + style.lightnessJitter * lightNoise,
            dryness: dry,
            hue: style.rainbowLength > 0 ? (distance / style.rainbowLength).truncatingRemainder(dividingBy: 1) : -1)
    }
}

extension Dab {
    /// Canvas pixels this dab can touch, for undo snapshots and merge scissoring.
    func bounds(aspect: Float) -> PixelRect {
        // The rotated quad's circumscribed half-extent.
        let half = size * 0.5 * (aspect * aspect + 1).squareRoot() + 2
        return PixelRect(
            x: Int((center.x - half).rounded(.down)), y: Int((center.y - half).rounded(.down)),
            width: Int((2 * half).rounded(.up)) + 1, height: Int((2 * half).rounded(.up)) + 1)
    }
}
