import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG ⇄ raw pixel bytes. Everything here is synchronous and actor-free so page loads
/// and saves can run off the main thread.
enum Bitmap {
    enum Failure: Error, CustomStringConvertible {
        case unreadable(URL)
        case unexpectedFormat(String)
        case encodeFailed

        var description: String {
            switch self {
            case .unreadable(let url): "unreadable image: \(url.lastPathComponent)"
            case .unexpectedFormat(let detail): "unexpected image format: \(detail)"
            case .encodeFailed: "PNG encoding failed"
            }
        }
    }

    static func image(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable(url) }
        return image
    }

    static func image(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unexpectedFormat("undecodable data") }
        return image
    }

    /// The image's own 8-bit gray samples, untouched by any color conversion. Region IDs
    /// are numbers, not colors: drawing into a context would color-manage them.
    static func grayBytes(of image: CGImage) throws -> [UInt8] {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 8,
              image.colorSpace?.model == .monochrome, image.alphaInfo == .none,
              let data = image.dataProvider?.data as Data?
        else {
            throw Failure.unexpectedFormat(
                "want 8-bit gray, got \(image.bitsPerPixel)bpp \(String(describing: image.colorSpace?.model))")
        }
        let width = image.width, rowBytes = image.bytesPerRow
        var out = [UInt8](repeating: 0, count: width * image.height)
        data.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                for y in 0..<image.height {
                    dst.baseAddress!.advanced(by: y * width)
                        .copyMemory(from: src.baseAddress!.advanced(by: y * rowBytes), byteCount: width)
                }
            }
        }
        return out
    }

    /// Alpha channel only, scaled to `size`².
    static func alphaBytes(of image: CGImage, size: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: size * size)
        out.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        return out
    }

    /// Premultiplied RGBA8, top row first, scaled to `size`².
    static func rgbaBytes(of image: CGImage, size: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: size * size * 4)
        out.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        return out
    }

    enum Layout {
        /// R, G, B, A in memory — the paint layer's MTLPixelFormat.rgba8Unorm.
        case rgba
        /// B, G, R, A in memory — MTLPixelFormat.bgra8Unorm, what composites render to.
        case bgra

        var bitmapInfo: UInt32 {
            switch self {
            case .rgba: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            case .bgra: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            }
        }
    }

    static func cgImage(premultiplied bytes: Data, width: Int, height: Int, layout: Layout) -> CGImage? {
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: layout.bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.encodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodeFailed }
        return data as Data
    }
}
