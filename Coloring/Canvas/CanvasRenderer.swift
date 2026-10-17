import Metal
import QuartzCore
import UIKit
import os

/// Decoded page + saved artwork, ready to upload. Built off the main thread.
struct PageAssets: Sendable {
    let regions: RegionMap
    let lineCoverage: [UInt8]
    let artwork: Artwork

    static func load(_ page: Page, artwork: Artwork) throws -> PageAssets {
        let regions = try RegionMap(contentsOf: page.regionsURL)
        let line = Bitmap.alphaBytes(of: try Bitmap.image(at: page.lineArtURL), size: CanvasSpec.size)
        return PageAssets(regions: regions, lineCoverage: line, artwork: artwork)
    }
}

/// The GPU side of one open page.
///
/// Layers, top to bottom: stamps → line art → paint → fills → paper. A stroke in
/// progress lives in its own texture until it ends, so the layers are untouched
/// mid-stroke: that is what makes undo a dirty-rect copy instead of a full snapshot.
@MainActor
final class CanvasRenderer {
    private let gpu = RenderContext.shared
    private let size = CanvasSpec.size
    private let labels: MTLTexture
    private let line: MTLTexture
    private let paint: MTLTexture
    private let stamps: MTLTexture
    private let stroke: MTLTexture
    /// 256 premultiplied colors indexed by region ID; written by the CPU, read per frame.
    private let palette: MTLBuffer

    private struct ActiveStroke {
        let style: BrushStyle
        let tip: RenderContext.StrokeTip
        let color: RGBA
        var dirty = PixelRect.empty
        var started = false
    }

    private var active: ActiveStroke?

    /// The page at screen size, kept between frames so a frame recomposes only `stale`
    /// (canvas pixels): recomposing all of it costs the A8 ~12 ms of GPU per frame.
    /// Dab bounds need no margin for what a pixel reads around itself: they are the
    /// rotated quad's circumscribed square plus 2 px, more than 4 px past the tip's
    /// coverage even for the smallest watercolor dab, whose edge darkening reads 4 px out.
    private var screen: MTLTexture?
    private var stale = PixelRect(x: 0, y: 0, width: CanvasSpec.size, height: CanvasSpec.size)
    private var whole: PixelRect { PixelRect(x: 0, y: 0, width: size, height: size) }

    init(assets: PageAssets) {
        labels = gpu.makeTexture(.r8Uint, size, size, usage: .shaderRead)
        line = gpu.makeTexture(.r8Unorm, size, size, usage: .shaderRead, mipmapped: true)
        paint = gpu.makeTexture(.rgba8Unorm, size, size, usage: [.renderTarget, .shaderRead])
        stamps = gpu.makeTexture(.rgba8Unorm, size, size, usage: [.renderTarget, .shaderRead])
        stroke = gpu.makeTexture(.rgba8Unorm, size, size, usage: [.renderTarget, .shaderRead])
        palette = gpu.device.makeBuffer(length: 256 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)!

        gpu.upload(assets.regions.labels, to: labels, bytesPerPixel: 1)
        gpu.upload(assets.lineCoverage, to: line, bytesPerPixel: 1)
        for (texture, saved) in [(paint, assets.artwork.layer), (stamps, assets.artwork.stamps)] {
            if let saved {
                gpu.upload(saved, to: texture, bytesPerPixel: 4)
            } else {
                clear(texture)
            }
        }
        let colors = palette.contents().bindMemory(to: SIMD4<Float>.self, capacity: 256)
        for i in 0..<256 {
            colors[i] = RGBA.white.premultiplied
        }
        for (region, color) in assets.artwork.fills {
            colors[Int(region)] = color.premultiplied
        }
    }

    private func clear(_ texture: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let commands = gpu.queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.commit()
    }

    // MARK: - Fill

    func setFill(_ color: RGBA, region: UInt8) {
        palette.contents().bindMemory(to: SIMD4<Float>.self, capacity: 256)[Int(region)] = color.premultiplied
        stale = whole
    }

    // MARK: - Strokes

    func beginStroke(style: BrushStyle, tip: RenderContext.StrokeTip, color: RGBA) {
        active = ActiveStroke(style: style, tip: tip, color: color)
    }

    func draw(_ dabs: [Dab]) {
        guard var current = active, !dabs.isEmpty, let commands = gpu.queue.makeCommandBuffer() else { return }
        // The first batch clears the stroke texture, so a cancelled stroke can't leak in.
        gpu.encodeDabs(dabs, into: stroke, clear: !current.started, style: current.style, tip: current.tip,
                       color: current.color, commands: commands)
        Self.reportGPUTime(of: commands, as: "dabs")
        commands.commit()
        current.started = true
        var batch = PixelRect.empty
        for dab in dabs {
            batch = batch.union(dab.bounds(aspect: current.tip.aspect))
        }
        current.dirty = current.dirty.union(batch)
        stale = stale.union(batch)
        active = current
    }

    /// Lands the stroke on its layer(s); returns how to take it back.
    func endStroke() -> CanvasEdit? {
        guard let current = active else { return nil }
        active = nil
        let rect = current.dirty.clamped(to: size)
        stale = stale.union(rect)
        guard current.started, !rect.isEmpty else { return nil }
        let targets = current.style.merge.layers
        var before: [CanvasLayer: Data] = [:]
        for target in targets {
            before[target] = gpu.download(texture(target), bytesPerPixel: 4, rect: rect)
        }

        guard let commands = gpu.queue.makeCommandBuffer() else { return nil }
        var uniforms = strokeUniforms(current.style)
        for target in targets {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture(target)
            pass.colorAttachments[0].loadAction = .load
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
            encoder.setRenderPipelineState(current.style.merge == .erase ? gpu.mergeErasePipeline : gpu.mergeOverPipeline)
            encoder.setScissorRect(MTLScissorRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
            encoder.setFragmentTexture(stroke, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ComposeUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        Self.reportGPUTime(of: commands, as: "merge")
        commands.commit()
        return .raster(rect: rect, before: before)
    }

    func restore(_ rect: PixelRect, _ layer: CanvasLayer, from bytes: Data) {
        gpu.upload(bytes, to: texture(layer), bytesPerPixel: 4, rect: rect)
        stale = stale.union(rect)
    }

    /// Wipes paint and stamps; returns both as they were. Fills are the caller's.
    func clearLayers() -> [CanvasLayer: Data] {
        var before: [CanvasLayer: Data] = [:]
        for layer in CanvasLayer.allCases {
            before[layer] = bytes(of: layer)
            clear(texture(layer))
        }
        stale = whole
        return before
    }

    private func texture(_ layer: CanvasLayer) -> MTLTexture {
        switch layer {
        case .paint: paint
        case .stamps: stamps
        }
    }

    private func strokeUniforms(_ style: BrushStyle) -> ComposeUniforms {
        let mode = switch style.merge {
        case .over: ComposeUniforms.over
        case .aboveLines: ComposeUniforms.above
        case .erase: ComposeUniforms.erase
        }
        return ComposeUniforms(
            strokeOpacity: style.strokeOpacity, edgeDarken: style.edgeDarken, edgeRadius: 4 / Float(size),
            canvasSize: Float(size), strokeMode: mode)
    }

    // MARK: - Output

    /// The page as the child sees it, including any stroke in progress; `only` keeps the
    /// rest of `target` as it was.
    func encodeComposite(into target: MTLTexture, commands: MTLCommandBuffer, only: MTLScissorRect? = nil) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = only == nil ? .dontCare : .load
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let only { encoder.setScissorRect(only) }
        var uniforms = active.map { strokeUniforms($0.style) } ?? ComposeUniforms()
        if active?.started != true { uniforms.strokeMode = ComposeUniforms.none }
        encoder.setRenderPipelineState(gpu.composePipeline)
        encoder.setFragmentTexture(labels, index: 0)
        encoder.setFragmentTexture(paint, index: 1)
        encoder.setFragmentTexture(stroke, index: 2)
        encoder.setFragmentTexture(line, index: 3)
        encoder.setFragmentTexture(stamps, index: 4)
        encoder.setFragmentBuffer(palette, offset: 0, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ComposeUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    func draw(in view: CAMetalLayer) {
        let interval = Self.signposter.beginInterval("frame")
        defer { Self.signposter.endInterval("frame", interval) }
        guard let drawable = view.nextDrawable(), let commands = gpu.queue.makeCommandBuffer() else { return }
        let screen = refreshScreen(width: drawable.texture.width, height: drawable.texture.height, commands: commands)
        // A drawable comes back with whatever it last held, so it gets the whole page.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        if let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(gpu.copyPipeline)
            encoder.setFragmentTexture(screen, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        commands.present(drawable)
        Self.reportGPUTime(of: commands, as: "frame")
        commands.commit()
    }

    /// Brings the kept screen-size page up to date, recomposing only what went stale.
    func refreshScreen(width: Int, height: Int, commands: MTLCommandBuffer) -> MTLTexture {
        if screen?.width != width || screen?.height != height {
            screen = gpu.makeTexture(.bgra8Unorm, width, height, usage: [.renderTarget, .shaderRead])
            stale = whole
        }
        let screen = screen!
        let rect = stale.clamped(to: size)
        stale = .empty
        if !rect.isEmpty {
            let sx = Double(width) / Double(size), sy = Double(height) / Double(size)
            let x0 = Int(Double(rect.x) * sx), y0 = Int(Double(rect.y) * sy)
            let x1 = min(width, Int((Double(rect.x + rect.width) * sx).rounded(.up)))
            let y1 = min(height, Int((Double(rect.y + rect.height) * sy).rounded(.up)))
            encodeComposite(into: screen, commands: commands,
                            only: MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        }
        return screen
    }

    // MARK: - Profiling

    // Metal System Trace records no GPU intervals on the A8, so while Instruments is
    // recording, each command buffer reports its own GPU time as a `gpu` event.
    nonisolated static let signposter = OSSignposter(subsystem: "com.zeyanlin.littlestarcoloring", category: .pointsOfInterest)

    /// Metal calls the handler on its own thread: written in a main-actor method, the
    /// closure would be main-actor isolated and Swift 6 would trap (see `addToPhotos`).
    private nonisolated static func reportGPUTime(of commands: MTLCommandBuffer, as work: String) {
        guard signposter.isEnabled else { return }
        commands.addCompletedHandler { done in
            let ms = (done.gpuEndTime - done.gpuStartTime) * 1000
            signposter.emitEvent("gpu", "\(work, privacy: .public) \(ms, format: .fixed(precision: 2))")
        }
    }

    /// Premultiplied BGRA8, `pixels`².
    func snapshot(pixels: Int) -> Data {
        let target = gpu.makeTexture(.bgra8Unorm, pixels, pixels, usage: [.renderTarget, .shaderRead])
        guard let commands = gpu.queue.makeCommandBuffer() else { return Data() }
        encodeComposite(into: target, commands: commands)
        commands.commit()
        return gpu.download(target, bytesPerPixel: 4)
    }

    /// Premultiplied RGBA8, the whole canvas.
    func bytes(of layer: CanvasLayer) -> Data {
        gpu.download(texture(layer), bytesPerPixel: 4)
    }
}
