/// The shape a dab stamps. Generated procedurally (ProceduralTextures) — no image assets.
enum TipShape: CaseIterable, Sendable {
    case hard, wash, crayon, bristle, ink, spray, glitter, star, dome
}

/// How the dabs of one stroke combine with each other.
enum StrokeBlend: Sendable {
    /// Each dab paints over the last: a stroke crossing itself gets denser.
    case over
    /// Coverage is the max of the dabs: a stroke has one even tone however it overlaps.
    case max
}

/// Where a finished stroke lands, and how.
enum MergeMode: Sendable {
    /// Onto the paint layer, under the line art.
    case over
    /// Onto the stamp layer, over the line art: a stamp is a sticker.
    case aboveLines
    /// Cuts through paint and stamps alike; fills stay.
    case erase

    var layers: [CanvasLayer] {
        switch self {
        case .over: [.paint]
        case .aboveLines: [.stamps]
        case .erase: [.paint, .stamps]
        }
    }
}

/// A brush is data, not a type: every brush runs the same dab pipeline with different
/// numbers, so tuning a texture on device is editing this table, not the engine.
struct BrushStyle: Sendable {
    var tip: TipShape
    /// Multiplier on BrushSize.canvasPixels.
    var scale: Float = 1
    /// Distance between dabs as a fraction of the dab size.
    var spacing: Float
    /// Coverage of a single dab.
    var opacity: Float
    var blend: StrokeBlend
    var merge: MergeMode = .over
    /// Applied to the whole stroke when it lands, so a stroke's self-overlap doesn't
    /// stack (watercolor wash).
    var strokeOpacity: Float = 1
    /// Pigment pooling at the wet edge (watercolor).
    var edgeDarken: Float = 0
    /// How deep the paper's valleys are against the tip's pressure (coverage × opacity):
    /// paint lands where the pressure beats the depth. 0 = smooth paper.
    var grain: Float = 0
    /// Grain feature size multiplier.
    var grainScale: Float = 1
    /// Small: paper either takes paint or stays bare (crayon specks). 1: the grain only
    /// makes the paint lighter and darker (watercolor mottling).
    var grainSoftness: Float = 1
    var sizeJitter: Float = 0
    /// As a fraction of the dab size.
    var positionJitter: Float = 0
    /// Radians.
    var rotationJitter: Float = 0
    /// ±fraction of brightness per dab.
    var lightnessJitter: Float = 0
    /// Rotate the tip to face the direction of travel (bristles drag behind the brush).
    var followsDirection = false
    /// Width lost at full speed (ink: a fast flick leaves a thin line).
    var speedThinning: Float = 0
    /// Dryness at full speed (ink: a fast flick leaves white between the hairs, 飛白).
    var speedDrying: Float = 0
    /// Canvas pixels one load of paint lasts; 0 = never runs out.
    var paintLength: Float = 0
    /// Dryness once that length is used up.
    var paintDrying: Float = 0
    /// How much dryness pales a dab: a wash has no hairs to break, its pigment thins out.
    var dryFading: Float = 0
    /// Canvas pixels per trip round the rainbow, in place of the chosen color; 0 = off.
    var rainbowLength: Float = 0

    /// UserDefaults key of the settings panel's paint-runs-out switch.
    static let paintRunsOutKey = "paintRunsOut"

    /// `paintRunsOut` turns paintLength on for oil, watercolor and ink together: one
    /// brush drying while the next never does reads as a broken brush.
    static func brush(_ kind: BrushKind, paintRunsOut: Bool = false) -> BrushStyle {
        var style: BrushStyle = switch kind {
        case .crayon:
            BrushStyle(tip: .crayon, spacing: 0.1, opacity: 0.9, blend: .max,
                       grain: 1.2, grainScale: 1, grainSoftness: 0.06, sizeJitter: 0.04, rotationJitter: .pi)
        case .marker:
            BrushStyle(tip: .hard, spacing: 0.06, opacity: 0.82, blend: .max)
        case .watercolor:
            BrushStyle(tip: .wash, scale: 1.5, spacing: 0.05, opacity: 0.75, blend: .max,
                       strokeOpacity: 0.75, edgeDarken: 1, grain: 0.18, grainScale: 8,
                       sizeJitter: 0.1, positionJitter: 0.04, paintLength: 1600, paintDrying: 0.5, dryFading: 1)
        case .oil:
            // The jitter keeps the ridges from running dead straight like extruded plastic.
            BrushStyle(tip: .bristle, scale: 1.3, spacing: 0.03, opacity: 1, blend: .over,
                       sizeJitter: 0.04, positionJitter: 0.01, rotationJitter: 0.06, lightnessJitter: 0.03,
                       followsDirection: true, paintLength: 1600, paintDrying: 0.5)
        case .ink:
            BrushStyle(tip: .ink, scale: 1.1, spacing: 0.05, opacity: 0.8, blend: .over,
                       grain: 0.7, grainScale: 1, grainSoftness: 0.15, followsDirection: true,
                       speedThinning: 0.55, speedDrying: 0.45, paintLength: 2000, paintDrying: 0.6)
        case .airbrush:
            // The speckle is in the tip; turning every dab keeps its droplets from lining
            // up, and stacking dabs sprays the middle solid.
            BrushStyle(tip: .spray, scale: 1.6, spacing: 0.1, opacity: 1, blend: .over,
                       positionJitter: 0.03, rotationJitter: .pi)
        case .rainbow:
            // ~3 cm a lap on an iPad mini 4: a child's short stroke still shows several colors.
            BrushStyle(tip: .hard, spacing: 0.06, opacity: 1, blend: .over, rainbowLength: 600)
        case .glitter:
            BrushStyle(tip: .glitter, scale: 1.2, spacing: 0.25, opacity: 1, blend: .over, rotationJitter: .pi)
        case .stars:
            // Scattered off the path, each its own size, angle and shade.
            BrushStyle(tip: .star, spacing: 1.1, opacity: 1, blend: .over, sizeJitter: 0.35, positionJitter: 0.6,
                       rotationJitter: .pi, lightnessJitter: 0.12)
        case .puffy:
            // Max, not over: the brightest dome wins wherever dabs overlap, whatever the
            // order, so the highlight runs unbroken and the light comes from one side.
            BrushStyle(tip: .dome, scale: 1.1, spacing: 0.05, opacity: 1, blend: .max)
        case .chalk:
            // Coarser and softer than crayon: dusty, not blotchy.
            BrushStyle(tip: .crayon, scale: 1.3, spacing: 0.1, opacity: 0.75, blend: .max,
                       grain: 0.9, grainScale: 1.6, grainSoftness: 0.35, sizeJitter: 0.06, rotationJitter: .pi)
        case .pencil:
            BrushStyle(tip: .crayon, scale: 0.45, spacing: 0.1, opacity: 0.75, blend: .max,
                       grain: 0.9, grainScale: 0.5, grainSoftness: 0.12, rotationJitter: .pi)
        }
        if !paintRunsOut { style.paintLength = 0 }
        return style
    }

    static let eraser = BrushStyle(tip: .hard, scale: 1.6, spacing: 0.06, opacity: 1, blend: .max, merge: .erase)

    /// The tip is the stamp's own texture; spacing is relative to its larger side.
    static let stamp = BrushStyle(tip: .hard, spacing: 1.25, opacity: 1, blend: .over, merge: .aboveLines)
}
