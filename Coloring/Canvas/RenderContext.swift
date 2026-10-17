import CoreText
import Metal
import UIKit

/// Matches `DabUniforms` in Shaders.metal (48 bytes with padding).
struct DabUniforms {
    var color: SIMD4<Float>
    var targetSize: SIMD2<Float>
    var grainAmount: Float
    var grainScale: Float
    var grainSoftness: Float
    var aspect: Float
    var tintMode: UInt32

    static let tintShape: UInt32 = 0
    static let tintGlyph: UInt32 = 1
    static let tintImage: UInt32 = 2
}

/// Matches `ComposeUniforms` in Shaders.metal.
struct ComposeUniforms {
    var strokeOpacity: Float = 1
    var edgeDarken: Float = 0
    var edgeRadius: Float = 0
    var canvasSize: Float = Float(CanvasSpec.size)
    var strokeMode: UInt32 = 0

    static let none: UInt32 = 0
    static let over: UInt32 = 1
    static let erase: UInt32 = 2
    static let above: UInt32 = 3
}

/// Everything GPU-side that outlives a page: device, pipelines, brush tips, grain,
/// stamp textures. Built once at launch.
///
/// All textures are `.private` and move through blits. The simulator rejects shared
/// render-target textures, and a private texture is the fast path on device anyway.
@MainActor
final class RenderContext {
    static let shared = RenderContext()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let composePipeline: MTLRenderPipelineState
    let copyPipeline: MTLRenderPipelineState
    let mergeOverPipeline: MTLRenderPipelineState
    let mergeErasePipeline: MTLRenderPipelineState
    let dabOverPipeline: MTLRenderPipelineState
    let dabMaxPipeline: MTLRenderPipelineState
    let tips: [TipShape: MTLTexture]
    let grain: MTLTexture
    private var stampTextures: [Stamp: (texture: MTLTexture, aspect: Float)] = [:]

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { fatalError("Metal is unavailable — every supported iPad has it") }
        self.device = device
        self.queue = queue

        func pipeline(_ vertex: String, _ fragment: String, _ format: MTLPixelFormat,
                      blend: ((MTLRenderPipelineColorAttachmentDescriptor) -> Void)? = nil) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = format
            if let blend {
                descriptor.colorAttachments[0].isBlendingEnabled = true
                blend(descriptor.colorAttachments[0])
            }
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                fatalError("pipeline \(fragment): \(error)")
            }
        }
        let premultipliedOver: (MTLRenderPipelineColorAttachmentDescriptor) -> Void = {
            $0.sourceRGBBlendFactor = .one
            $0.sourceAlphaBlendFactor = .one
            $0.destinationRGBBlendFactor = .oneMinusSourceAlpha
            $0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        composePipeline = pipeline("fullscreen_vertex", "compose_fragment", .bgra8Unorm)
        copyPipeline = pipeline("fullscreen_vertex", "copy_fragment", .bgra8Unorm)
        mergeOverPipeline = pipeline("fullscreen_vertex", "merge_fragment", .rgba8Unorm, blend: premultipliedOver)
        mergeErasePipeline = pipeline("fullscreen_vertex", "merge_fragment", .rgba8Unorm) {
            // layer × (1 − stroke coverage)
            $0.sourceRGBBlendFactor = .zero
            $0.sourceAlphaBlendFactor = .zero
            $0.destinationRGBBlendFactor = .oneMinusSourceAlpha
            $0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        dabOverPipeline = pipeline("dab_vertex", "dab_fragment", .rgba8Unorm, blend: premultipliedOver)
        dabMaxPipeline = pipeline("dab_vertex", "dab_fragment", .rgba8Unorm) {
            $0.rgbBlendOperation = .max
            $0.alphaBlendOperation = .max
        }

        var tips: [TipShape: MTLTexture] = [:]
        for shape in TipShape.allCases {
            let size = ProceduralTextures.tipSize
            // Mipmapped: a small brush draws the 128 px tip at ~30 px, and without mips its
            // hair streaks alias into pinstripes.
            let texture = Self.makeTexture(device, .rgba8Unorm, size, size, usage: .shaderRead, mipmapped: true)
            tips[shape] = texture
        }
        self.tips = tips
        grain = Self.makeTexture(device, .r8Unorm, ProceduralTextures.grainSize, ProceduralTextures.grainSize,
                                 usage: .shaderRead)
        for (shape, texture) in tips {
            upload(ProceduralTextures.tip(shape), to: texture, bytesPerPixel: 4)
        }
        upload(ProceduralTextures.grain(), to: grain, bytesPerPixel: 1)
    }

    // MARK: - Textures

    static func makeTexture(_ device: MTLDevice, _ format: MTLPixelFormat, _ width: Int, _ height: Int,
                            usage: MTLTextureUsage, mipmapped: Bool = false) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: mipmapped)
        descriptor.usage = usage
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("out of GPU memory for a \(width)×\(height) texture")
        }
        return texture
    }

    func makeTexture(_ format: MTLPixelFormat, _ width: Int, _ height: Int,
                     usage: MTLTextureUsage, mipmapped: Bool = false) -> MTLTexture {
        Self.makeTexture(device, format, width, height, usage: usage, mipmapped: mipmapped)
    }

    /// Queued behind earlier GPU work, so it's safe against frames still reading `texture`.
    func upload<C: Collection>(_ bytes: C, to texture: MTLTexture, bytesPerPixel: Int,
                               rect: PixelRect? = nil) where C.Element == UInt8 {
        let rect = rect ?? PixelRect(x: 0, y: 0, width: texture.width, height: texture.height)
        let rowBytes = rect.width * bytesPerPixel
        precondition(bytes.count == rowBytes * rect.height, "upload size mismatch")
        let staging = bytes.withContiguousStorageIfAvailable {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        } ?? Array(bytes).withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
        guard let staging, let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder()
        else { fatalError("upload: out of GPU memory") }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: rowBytes,
                  sourceBytesPerImage: rowBytes * rect.height,
                  sourceSize: MTLSize(width: rect.width, height: rect.height, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: rect.x, y: rect.y, z: 0))
        if texture.mipmapLevelCount > 1 {
            blit.generateMipmaps(for: texture)
        }
        blit.endEncoding()
        commands.commit()
    }

    /// Waits for every GPU command queued so far, then copies `rect` out.
    func download(_ texture: MTLTexture, bytesPerPixel: Int, rect: PixelRect? = nil) -> Data {
        let rect = rect ?? PixelRect(x: 0, y: 0, width: texture.width, height: texture.height)
        let rowBytes = rect.width * bytesPerPixel
        guard let buffer = device.makeBuffer(length: rowBytes * rect.height, options: .storageModeShared),
              let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder()
        else { fatalError("download: out of GPU memory") }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: rect.x, y: rect.y, z: 0),
                  sourceSize: MTLSize(width: rect.width, height: rect.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes,
                  destinationBytesPerImage: rowBytes * rect.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return Data(bytes: buffer.contents(), count: buffer.length)
    }

    // MARK: - Dabs

    struct StrokeTip {
        let texture: MTLTexture
        let tintMode: UInt32
        let aspect: Float
    }

    func tip(for style: BrushStyle) -> StrokeTip {
        StrokeTip(texture: tips[style.tip]!, tintMode: DabUniforms.tintShape, aspect: 1)
    }

    func encodeDabs(_ dabs: [Dab], into target: MTLTexture, clear: Bool, style: BrushStyle, tip: StrokeTip,
                    color: RGBA, commands: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = clear ? .clear : .load
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        if !dabs.isEmpty {
            var uniforms = DabUniforms(
                color: color.premultiplied,
                targetSize: SIMD2(Float(target.width), Float(target.height)),
                grainAmount: tip.tintMode == DabUniforms.tintImage ? 0 : style.grain,
                grainScale: style.grainScale, grainSoftness: style.grainSoftness, aspect: tip.aspect,
                tintMode: tip.tintMode)
            let buffer = dabs.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
            }
            encoder.setRenderPipelineState(style.blend == .max ? dabMaxPipeline : dabOverPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<DabUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DabUniforms>.stride, index: 1)
            encoder.setFragmentTexture(tip.texture, index: 0)
            encoder.setFragmentTexture(grain, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: dabs.count)
        }
        encoder.endEncoding()
    }

    // MARK: - Stamps

    func stampTip(_ stamp: Stamp) -> StrokeTip {
        if let cached = stampTextures[stamp] {
            return StrokeTip(texture: cached.texture,
                             tintMode: stamp.kind == .emoji ? DabUniforms.tintImage : DabUniforms.tintGlyph,
                             aspect: cached.aspect)
        }
        // Rendered once per stamp at the largest stamp size, so big stamps stay crisp.
        let height = 256
        let picture = stamp.pictureURL.flatMap { UIImage(contentsOfFile: $0.path)?.cgImage }
        let text = NSAttributedString(string: stamp.text, attributes: [
            .font: UIFont.systemFont(ofSize: 150, weight: .bold), .foregroundColor: UIColor.white,
        ])
        let bounds = picture == nil
            ? text.boundingRect(with: CGSize(width: 4000, height: 4000), options: .usesLineFragmentOrigin, context: nil)
            : .zero
        let width = max(height, Int(bounds.width.rounded(.up)) + 24)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            if let picture {
                // As big as the 200 pt emoji glyph it replaced: S/M/L keep the sizes
                // tuned on device.
                context.draw(picture, in: CGRect(x: 28, y: 28, width: 200, height: 200))
            } else {
                // UIKit text drawing wants a top-left origin.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(context)
                text.draw(at: CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: (CGFloat(height) - bounds.height) / 2))
                UIGraphicsPopContext()
            }
        }
        let texture = makeTexture(.rgba8Unorm, width, height, usage: .shaderRead)
        upload(bytes, to: texture, bytesPerPixel: 4)
        let aspect = Float(width) / Float(height)
        stampTextures[stamp] = (texture, aspect)
        return stampTip(stamp)
    }
}
