import Foundation

/// Region ID per canvas pixel, as computed by tools/build_pages.py. Every pixel —
/// including those under the lines — belongs to some region, so every tap fills.
struct RegionMap: Sendable {
    let size: Int
    let labels: [UInt8]

    init(size: Int, labels: [UInt8]) {
        precondition(labels.count == size * size)
        self.size = size
        self.labels = labels
    }

    init(contentsOf url: URL) throws {
        let image = try Bitmap.image(at: url)
        guard image.width == CanvasSpec.size, image.height == CanvasSpec.size else {
            throw Bitmap.Failure.unexpectedFormat("regions \(image.width)×\(image.height)")
        }
        self.init(size: image.width, labels: try Bitmap.grayBytes(of: image))
    }

    func region(at point: SIMD2<Float>) -> UInt8 {
        let x = min(max(Int(point.x), 0), size - 1)
        let y = min(max(Int(point.y), 0), size - 1)
        return labels[y * size + x]
    }
}
