import Metal
import QuartzCore
import UIKit

/// Square canvas surface. Hands touches, in canvas pixels, to its owner and redraws
/// on request. A plain CAMetalLayer-backed view: drawing happens only when something
/// changed, so an idle page costs no GPU time.
@MainActor
final class CanvasView: UIView {
    struct Sample {
        let point: SIMD2<Float>
        let time: TimeInterval
    }

    var onDraw: ((CAMetalLayer) -> Void)?
    var onBegan: ((Sample) -> Void)?
    var onMoved: (([Sample]) -> Void)?
    var onEnded: (() -> Void)?

    private var needsRedraw = false

    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    init(device: MTLDevice) {
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        isOpaque = true
        backgroundColor = .white
        // One finger paints. A resting palm or a second finger is ignored by UIKit
        // itself rather than by bookkeeping here.
        isMultipleTouchEnabled = false
        isAccessibilityElement = true
        // VoiceOver users draw by touch here too, rather than swiping between elements.
        accessibilityTraits = .allowsDirectInteraction
        accessibilityIdentifier = "canvas"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if metalLayer.drawableSize != pixels, pixels.width > 0 {
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = pixels
            setNeedsRedraw()
        }
    }

    /// Coalesces any number of requests into one draw on the next run-loop turn.
    func setNeedsRedraw() {
        guard !needsRedraw else { return }
        needsRedraw = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.needsRedraw = false
            guard self.bounds.width > 0 else { return }
            self.onDraw?(self.metalLayer)
        }
    }

    private func sample(_ touch: UITouch) -> Sample {
        let p = touch.location(in: self)
        let scale = Float(CanvasSpec.size) / Float(bounds.width)
        return Sample(point: SIMD2(Float(p.x) * scale, Float(p.y) * scale), time: touch.timestamp)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        onBegan?(sample(touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        // On 120 Hz iPads several samples arrive per frame; using all of them keeps a
        // fast curve round instead of a polygon.
        let samples = (event?.coalescedTouches(for: touch) ?? [touch]).map(sample)
        onMoved?(samples)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Keep what was drawn: a system gesture interrupting a stroke shouldn't eat it.
        onEnded?()
    }
}
